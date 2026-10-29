import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/observed_article_store.dart';
import 'package:ice_cream_rss_reader/utils/host_pacer.dart';

class _BatchTimer implements Timer {
  _BatchTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

class _Request {
  _Request(this.url);
  final String url;
  final result = Completer<FeedFetchResult>();
  void complete(String id) => result.complete(
    FeedFetchResult(
      items: [
        FeedItem(
          id: id,
          siteName: 'Test',
          title: id,
          description: '',
          feedUrl: url,
        ),
      ],
    ),
  );
  void failOffline() => result.completeError(
    FeedFetchException(FeedFetchErrorKind.connectivity, 'offline'),
  );
}

class _ControlledFeeds extends FeedService {
  final requests = StreamController<_Request>();
  @override
  Future<FeedFetchResult> fetchFeed(
    String url,
    String category, {
    String? etag,
    String? lastModified,
  }) {
    final request = _Request(url);
    requests.add(request);
    return request.result.future;
  }

  @override
  void dispose() {
    requests.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _ControlledFeeds service;
  late StreamIterator<_Request> requests;
  late FeedProvider feed;
  late SubscriptionProvider subscriptions;
  late SettingsProvider settings;
  late BookmarkProvider bookmarks;
  late List<_BatchTimer> timers;
  late MockStreamHandlerEventSink connectivity;
  var disposed = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('incremental-scheduler-');
    Hive.init(directory.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (_) async => true,
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, events) => connectivity = events),
    );
    await Hive.box('settings').put('syncBackground', false);
    await Hive.box('feeds').put(
      'subscriptions',
      jsonEncode([
        for (final host in ['fast', 'slow'])
          FeedSubscription(
            url: 'https://$host.test/rss',
            name: host,
            category: 'Test',
          ).toJson(),
      ]),
    );
    service = _ControlledFeeds();
    requests = StreamIterator(service.requests.stream);
    timers = [];
    disposed = false;
    feed = FeedProvider(
      feedService: service,
      hostPacer: HostPacer(minGap: Duration.zero),
      scheduleRefreshPublish: (duration, callback) {
        expect(duration, const Duration(milliseconds: 100));
        final timer = _BatchTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    subscriptions = SubscriptionProvider();
    settings = SettingsProvider();
    bookmarks = BookmarkProvider();
    feed.update(subscriptions, settings, bookmarks);
  });

  tearDown(() async {
    // Fire-and-forget archive writes must finish before the directory goes.
    await feed.idle;
    if (!disposed) feed.dispose();
    subscriptions.dispose();
    settings.dispose();
    bookmarks.dispose();
    await requests.cancel();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<_Request> next() async {
    expect(await requests.moveNext(), isTrue);
    return requests.current;
  }

  /// Whether [pass] settles before the provider requests another feed — a
  /// trailing pass would ask first. Ends the test's use of [next].
  Future<bool> settlesAlone(Future<void> pass) => Future.any([
    pass.then((_) => true),
    requests.moveNext().then((_) => false),
  ]);

  Future<void> settleFeed(_Request request, String id, int completed) async {
    final settled = Completer<void>();
    void listener() {
      if (feed.refreshProgress.value.completed == completed &&
          !settled.isCompleted) {
        settled.complete();
      }
    }

    feed.refreshProgress.addListener(listener);
    request.complete(id);
    await settled.future;
    feed.refreshProgress.removeListener(listener);
  }

  test('a reset cancels a pending read-mark batch', () async {
    await feed.markAsRead(
      FeedItem(
        id: 'r1',
        siteName: 'Test',
        title: 'r1',
        description: '',
        feedUrl: 'https://fast.test/rss',
      ),
    );
    feed.discardStateForReset();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(Hive.box('feeds').get('readItemRefs'), isNull);
  });

  test(
    'cache save requests made before the queued save starts join it',
    () async {
      final writes = <Object?>[];
      final sub = Hive.box(
        'feeds',
      ).watch(key: 'cachedItemsJson').listen((e) => writes.add(e.value));
      addTearDown(sub.cancel);
      final first = feed.saveCachedItems();
      final second = feed.saveCachedItems();
      final third = feed.saveCachedItems();
      expect(identical(first, second) && identical(second, third), isTrue);
      await third;
      await feed.idle;
      await Future<void>.delayed(Duration.zero);
      expect(writes, hasLength(1));
    },
  );

  test(
    'a status read never leaves a view older than the last request',
    () async {
      final store = ArticleRecordStore.forBox(Hive.box('feeds'));
      ArticleRecord record(String id) => ArticleRecord(
        id: id,
        feedUrl: 'https://fast.test/rss',
        body: '<p>$id</p>',
        bodyState: MediaState.ready,
        owners: const {'tempCache'},
        generation: 1,
      );
      FeedItem item(String id) => FeedItem(
        id: id,
        siteName: 'Test',
        title: id,
        description: '',
        feedUrl: 'https://fast.test/rss',
      );
      await store.write(record('s1'));
      final first = feed.refreshArticleStatuses();
      // A change lands while the first read may still be running.
      await store.write(record('s2'));
      await feed.refreshArticleStatuses();
      await first;
      expect(feed.articleStatus(item('s1')), isNotNull);
      expect(feed.articleStatus(item('s2')), isNotNull);
    },
  );

  test('read marks are written in one batch, not on every tap', () async {
    FeedItem article(String id) => FeedItem(
      id: id,
      siteName: 'Test',
      title: id,
      description: '',
      feedUrl: 'https://fast.test/rss',
    );
    final box = Hive.box('feeds');
    await feed.markAsRead(article('r1'));
    await feed.markAsRead(article('r2'));
    expect(feed.isRead(article('r1')), isTrue);
    expect(box.get('readItemRefs'), isNull);

    await feed.flushReadStates();
    expect((box.get('readItemRefs') as Map)['refs'], hasLength(2));

    // Without an explicit flush the batch lands after a short quiet period.
    await feed.toggleReadStatus(article('r2'));
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect((box.get('readItemRefs') as Map)['refs'], hasLength(1));
  });

  test(
    'fast result publishes once while slow source remains blocked',
    () async {
      final a = await next();
      final b = await next();
      final done = feed.refreshAll();
      await settleFeed(a, 'fast', 1);
      expect(feed.items, isEmpty);
      expect(timers.where((t) => t.isActive).length, 1);
      timers.single.fire();
      expect(feed.items.single.id, 'fast');
      expect(feed.isLoading, isTrue);
      expect(Hive.box('feeds').get('cachedItemsJson'), isNull);
      b.complete('slow');
      await done;
      expect(feed.items.map((i) => i.id), containsAll(['fast', 'slow']));
      expect(feed.isLoading, isFalse);
      expect(timers.every((t) => !t.isActive), isTrue);
    },
  );

  test(
    'all sources finish before timer; canceled callback cannot republish',
    () async {
      final a = await next();
      final b = await next();
      final done = feed.refreshAll();
      await settleFeed(a, 'fast', 1);
      b.complete('slow');
      await done;
      expect(timers.length, 1);
      expect(timers.single.isActive, isFalse);
      var notifications = 0;
      feed.addListener(() => notifications++);
      // Stronger than Timer's contract: even a captured callback is fenced.
      timers.single.callback();
      expect(notifications, 0);
      expect(feed.items.length, 2);
    },
  );

  for (final action in ['clear', 'reset', 'dispose', 'unsubscribe']) {
    test('$action invalidates pending publication and late result', () async {
      final a = await next();
      final b = await next();
      final done = feed.refreshAll();
      await settleFeed(a, 'fast', 1);
      final stale = timers.single;
      switch (action) {
        case 'clear':
          await feed.clearCache();
        case 'reset':
          expect(await feed.factoryReset(), isTrue);
        case 'dispose':
          feed.dispose();
          disposed = true;
        case 'unsubscribe':
          await subscriptions.removeFeed(a.url);
          await subscriptions.removeFeed(b.url);
      }
      stale.fire();
      b.complete('slow');
      await done;
      expect(feed.items, isEmpty);
      expect(feed.isSyncing, isFalse);
      if (action == 'reset') expect(feed.hasLoadedOnce, isFalse);
      if (action != 'unsubscribe') {
        expect(Hive.box('feeds').get('cachedItemsJson'), isNull);
      }
    });
  }

  test(
    'cache clear during first load still ends first-load suppression',
    () async {
      final a = await next();
      final b = await next();
      final done = feed.refreshAll();
      await settleFeed(a, 'fast', 1);
      // Observation advances regardless; staying "first load" would silence
      // the next pass's genuinely new articles.
      await feed.clearCache();
      b.complete('slow');
      await done;
      expect(feed.hasLoadedOnce, isTrue);
    },
  );

  test(
    'factory reset cannot be followed by stale observation history',
    () async {
      final a = await next();
      final b = await next();
      final epochs = {
        for (final s in subscriptions.subscriptions) s.url: s.notificationEpoch,
      };
      final done = feed.refreshAll();
      expect(await feed.factoryReset(), isTrue);
      a.complete('old-a');
      b.complete('old-b');
      await done;
      final claim = await ObservedArticleStore.forBox(Hive.box('feeds'))
          .claimFeedBatch(
            feedUrl: a.url,
            observationEpoch: epochs[a.url]!,
            items: const [],
          );
      expect(
        claim.initializedFeed,
        isTrue,
        reason: 'old pass must not recreate wiped history',
      );
    },
  );

  for (final reset in [false, true]) {
    test(
      'dispose while ${reset ? 'factory reset' : 'cache clear'} awaits storage',
      () async {
        final a = await next();
        final b = await next();
        final done = feed.refreshAll();
        final clearing = reset ? feed.factoryReset() : feed.clearCache();
        feed.dispose();
        disposed = true;
        a.complete('stale-a');
        b.complete('stale-b');
        await clearing;
        await done;
        expect(Hive.box('feeds').get('cachedItemsJson'), isNull);
      },
    );
  }

  test(
    'refresh preserves source-local read state and bookmark decoration',
    () async {
      final a = await next();
      final b = await next();
      final first = feed.refreshAll();
      a.complete('shared');
      b.complete('shared');
      await first;
      for (final item in List.of(feed.items)) {
        await feed.markAsRead(item);
      }
      bookmarks.toggleBookmark(
        feed.items.firstWhere((i) => i.feedUrl == a.url),
      );
      await bookmarks.persistBookmarks();
      feed.update(subscriptions, settings, bookmarks);
      expect(
        feed.filteredItems.where((i) => i.isBookmarked).single.feedUrl,
        a.url,
      );
      bookmarks.toggleBookmark(
        feed.items.firstWhere((i) => i.feedUrl == b.url),
      );
      await bookmarks.persistBookmarks();
      feed.update(subscriptions, settings, bookmarks);
      expect(feed.filteredItems.where((i) => i.isBookmarked).length, 2);
      final second = feed.refreshAll();
      (await next()).complete('shared');
      (await next()).result.complete(const FeedFetchResult.notModified());
      await second;
      expect(feed.filteredItems.length, 2);
      expect(
        feed.filteredItems.every((i) => i.isRead && i.isBookmarked),
        isTrue,
      );
      await feed.flushReadStates();
      expect(
        (Hive.box('feeds').get('readItemRefs') as Map)['refs'],
        hasLength(2),
      );
    },
  );

  test(
    'queued second pass cannot be overwritten by first batch callback',
    () async {
      final a = await next();
      final b = await next();
      final done = feed.refreshAll(queueIfRunning: true);
      await settleFeed(a, 'first-a', 1);
      final oldTimer = timers.single;
      b.complete('first-b');
      final secondA = await next();
      final secondB = await next();
      await settleFeed(secondA, 'second-a', 1);
      final before = List<FeedItem>.of(feed.items);
      oldTimer.callback();
      expect(feed.items, before);
      expect(timers.last.isActive, isTrue);
      timers.last.fire();
      expect(feed.items.any((i) => i.id == 'second-a'), isTrue);
      secondB.complete('second-b');
      await done;
      expect(
        feed.items.map((i) => i.id),
        containsAll(['second-a', 'second-b']),
      );
      expect(timers.every((t) => !t.isActive), isTrue);
    },
  );

  const third = 'https://third.test/rss';

  test(
    'a subscription change the running pass already read adds no pass',
    () async {
      final startup = feed.refreshAll();
      (await next()).complete('fast-0');
      (await next()).complete('slow-0');
      await startup;

      // Onboarding and Explore add feeds, then refresh; the ProxyProvider
      // update reporting the change lands after the pass read the list.
      await subscriptions.addFeed(third, 'third', 'Test');
      final pass = feed.refreshAll();
      final fetches = [await next(), await next(), await next()];
      expect(fetches.map((r) => r.url), contains(third));
      feed.update(subscriptions, settings, bookmarks);
      for (final r in fetches) {
        r.complete('${r.url}-1');
      }
      expect(await settlesAlone(pass), isTrue);
    },
  );

  test(
    'a subscription added after the pass read the list earns a trailing pass',
    () async {
      final a = await next();
      final b = await next();
      await subscriptions.addFeed(third, 'third', 'Test');
      feed.update(subscriptions, settings, bookmarks);
      final settled = feed.refreshAll();
      a.complete('fast-0');
      b.complete('slow-0');
      final trailing = [await next(), await next(), await next()];
      expect(trailing.map((r) => r.url), contains(third));
      for (final r in trailing) {
        r.complete('${r.url}-1');
      }
      await settled;
    },
  );

  group('connectivity returning mid-pass', () {
    Future<void> failStartupOffline() async {
      final startup = feed.refreshAll();
      (await next()).failOffline();
      (await next()).failOffline();
      await startup;
      expect(feed.isOffline, isTrue);
    }

    test('adds no pass when the running pass reaches the network', () async {
      await failStartupOffline();
      final pass = feed.refreshAll(userInitiated: true);
      final a = await next();
      final b = await next();
      connectivity.success(['wifi']);
      await pumpEventQueue();
      a.complete('fast-1');
      b.complete('slow-1');
      expect(await settlesAlone(pass), isTrue);
      expect(feed.isOffline, isFalse);
    });

    test('retries once when the running pass still ended offline', () async {
      await failStartupOffline();
      final pass = feed.refreshAll(userInitiated: true);
      final a = await next();
      final b = await next();
      connectivity.success(['wifi']);
      await pumpEventQueue();
      a.failOffline();
      b.failOffline();
      final retry = [await next(), await next()];
      for (final r in retry) {
        r.complete('${r.url}-1');
      }
      await pass;
      expect(feed.isOffline, isFalse);
    });
  });
}
