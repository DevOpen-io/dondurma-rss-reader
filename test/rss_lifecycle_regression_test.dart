import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/background_fetch_service.dart';
import 'package:ice_cream_rss_reader/services/feed_refresh.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/observed_article_store.dart';

typedef RequestHandler = FutureOr<void> Function(HttpRequest request);

class _FeedServer {
  _FeedServer._(this._server) {
    _server.listen((request) async {
      final handler = handlers[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      counts.update(request.uri.path, (value) => value + 1, ifAbsent: () => 1);
      await handler(request);
    });
  }

  final HttpServer _server;
  final Map<String, RequestHandler> handlers = {};
  final Map<String, int> counts = {};

  static Future<_FeedServer> start() async =>
      _FeedServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String url(String path) =>
      'http://${_server.address.host}:${_server.port}$path';

  Future<void> close() => _server.close(force: true);
}

FeedItem _item(String feedUrl, String id, {DateTime? date}) => FeedItem(
  id: id,
  siteName: 'Test Feed',
  title: id,
  description: '',
  timeAgo: '',
  siteIcon: Icons.rss_feed,
  iconColor: Colors.blue,
  iconBackgroundColor: Colors.blueGrey,
  feedUrl: feedUrl,
  category: 'Test',
  pubDate: date ?? DateTime.utc(2026, 8, 26, 10),
);

String _rss(String title, Iterable<String> ids, {int hour = 10}) {
  final entries = ids.toList();
  return '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>$title</title><link>https://example.test</link>
${entries.indexed.map((entry) {
    final (index, id) = entry;
    final minute = (59 - index).clamp(0, 59).toString().padLeft(2, '0');
    return '<item><title>$id</title><guid>$id</guid><link>https://example.test/$id</link><pubDate>Wed, 26 Aug 2026 ${hour.toString().padLeft(2, '0')}:$minute:00 +0000</pubDate></item>';
  }).join()}
</channel></rss>''';
}

Future<void> _respond200(
  HttpRequest request,
  String body, {
  String? etag,
}) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType('application', 'rss+xml');
  if (etag != null) request.response.headers.set(HttpHeaders.etagHeader, etag);
  request.response.write(body);
  await request.response.close();
}

Future<void> _respondConditional(
  HttpRequest request,
  String body, {
  String etag = '"v1"',
}) async {
  if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
    request.response.statusCode = HttpStatus.notModified;
    await request.response.close();
    return;
  }
  await _respond200(request, body, etag: etag);
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForRefresh(FeedProvider feed) async {
  await _waitUntil(() => !feed.isSyncing);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  if (feed.isSyncing) await _waitUntil(() => !feed.isSyncing);
}

List<FeedItem> _persistedItems() {
  final raw = Hive.box('feeds').get('cachedItemsJson') as String?;
  if (raw == null) return [];
  return (jsonDecode(raw) as List<dynamic>)
      .map((entry) => FeedItem.fromJson(entry as Map<String, dynamic>))
      .toList();
}

Future<void> _seedSubscriptions(Iterable<FeedSubscription> subscriptions) =>
    Hive.box('feeds').put(
      'subscriptions',
      jsonEncode(
        subscriptions.map((subscription) => subscription.toJson()).toList(),
      ),
    );

Future<void> _seedCache(Iterable<FeedItem> items) => Hive.box('feeds').put(
  'cachedItemsJson',
  jsonEncode(items.map((item) => item.toJson()).toList()),
);

({
  SubscriptionProvider subscriptions,
  SettingsProvider settings,
  BookmarkProvider bookmarks,
  FeedProvider feed,
})
_providers({bool wire = true}) {
  final subscriptions = SubscriptionProvider();
  final settings = SettingsProvider();
  final bookmarks = BookmarkProvider();
  final feed = FeedProvider();
  if (wire) feed.update(subscriptions, settings, bookmarks);
  return (
    subscriptions: subscriptions,
    settings: settings,
    bookmarks: bookmarks,
    feed: feed,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late _FeedServer server;

  setUpAll(() async {
    // Flutter's widget-test binding installs a 400-only HttpOverrides client.
    // These lifecycle tests use a real loopback server for deterministic HTTP.
    HttpOverrides.global = null;
    tempDirectory = await Directory.systemTemp.createTemp('rss-lifecycle-red-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDirectory.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('home_widget'),
          (_) async => true,
        );
    Hive.init(tempDirectory.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
  });

  setUp(() async {
    await Hive.box('settings').clear();
    await Hive.box('feeds').clear();
    await Hive.box('bookmarks').clear();
    // The durable record/seen sidecar lives outside the boxes — wipe it too,
    // or members from earlier tests would leak slots into this one.
    await ArticleRecordStore.forBox(Hive.box('feeds')).wipeAll();
    await Hive.box('settings').put('syncBackground', false);
    await Hive.box('settings').put('offlineCacheLimit', 50);
    server = await _FeedServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  tearDownAll(() async {
    await Hive.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'subscription mutation schedules foreground refresh from immutable snapshot',
    () async {
      final url = server.url('/snapshot.xml');
      server.handlers['/snapshot.xml'] = (request) =>
          _respond200(request, _rss('Snapshot', ['snapshot-article']));
      final providers = _providers();
      await _waitForRefresh(providers.feed);

      await providers.subscriptions.addFeed(url, 'Snapshot', 'Test');
      providers.feed.update(
        providers.subscriptions,
        providers.settings,
        providers.bookmarks,
      );
      await _waitUntil(
        () => providers.feed.items.any((item) => item.id == 'snapshot-article'),
      );

      expect(server.counts['/snapshot.xml'], 1);
      expect(
        providers.feed.items.map((item) => item.id),
        contains('snapshot-article'),
      );
      providers.feed.dispose();
    },
  );

  test(
    'manual add immediately fetches, renders, and persists with stale validator',
    () async {
      final url = server.url('/manual.xml');
      final existingUrl = server.url('/manual-existing.xml');
      server.handlers['/manual.xml'] = (request) =>
          _respondConditional(request, _rss('Manual', ['manual-article']));
      server.handlers['/manual-existing.xml'] = (request) =>
          _respond200(request, _rss('Existing', ['existing-article']));
      await _seedSubscriptions([
        FeedSubscription(url: existingUrl, name: 'Existing', category: 'Test'),
      ]);
      await Hive.box('feeds').put(
        'feedValidators',
        jsonEncode({
          url: {'etag': '"v1"'},
        }),
      );
      final providers = _providers();
      await _waitForRefresh(providers.feed);

      expect(
        await providers.feed.addSubscriptionAndRefresh(url, 'Manual', 'Test'),
        isTrue,
      );
      providers.feed.update(
        providers.subscriptions,
        providers.settings,
        providers.bookmarks,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        providers.feed.items.map((item) => item.id),
        contains('manual-article'),
      );
      expect(
        _persistedItems().map((item) => item.id),
        contains('manual-article'),
      );
      expect(
        server.counts['/manual-existing.xml'],
        1,
        reason: 'adding one feed must not refresh every existing subscription',
      );
      providers.feed.dispose();
    },
  );

  test(
    'suggested add uses same immediate foreground fetch and persistence lifecycle',
    () async {
      final url = server.url('/suggested.xml');
      server.handlers['/suggested.xml'] = (request) => _respondConditional(
        request,
        _rss('Suggested', ['suggested-article']),
      );
      await Hive.box('feeds').put(
        'feedValidators',
        jsonEncode({
          url: {'etag': '"v1"'},
        }),
      );
      final providers = _providers();
      await _waitForRefresh(providers.feed);

      expect(
        await providers.feed.addSubscriptionAndRefresh(
          url,
          'Suggested',
          'Test',
        ),
        isTrue,
      );
      expect(
        providers.feed.items.map((item) => item.id),
        contains('suggested-article'),
      );
      expect(
        _persistedItems().map((item) => item.id),
        contains('suggested-article'),
      );
      providers.feed.dispose();
    },
  );

  test(
    'manual and suggested UI use one awaited provider-level subscription API',
    () async {
      final manual = await File(
        'lib/widgets/add_feed_dialog.dart',
      ).readAsString();
      final suggested = await File(
        'lib/screens/explore_feeds_page.dart',
      ).readAsString();

      expect(manual.contains('await feeds.addSubscriptionAndRefresh('), isTrue);
      expect(
        suggested.contains('await feedProvider.addSubscriptionAndRefresh('),
        isTrue,
      );
      expect(manual.contains('subscriptions.addFeed('), isFalse);
    },
  );

  test(
    'queued pull refresh includes subscription added during in-flight refresh',
    () async {
      final aUrl = server.url('/queued-a.xml');
      final bUrl = server.url('/queued-b.xml');
      final aRequested = Completer<void>();
      final releaseA = Completer<void>();
      server.handlers['/queued-a.xml'] = (request) async {
        if (!aRequested.isCompleted) aRequested.complete();
        await releaseA.future;
        await _respond200(request, _rss('A', ['a-article']));
      };
      server.handlers['/queued-b.xml'] = (request) =>
          _respond200(request, _rss('B', ['b-article']));
      await _seedSubscriptions([
        FeedSubscription(url: aUrl, name: 'A', category: 'Test'),
      ]);
      final providers = _providers(wire: false);
      providers.feed.update(
        providers.subscriptions,
        providers.settings,
        providers.bookmarks,
      );
      await aRequested.future;

      await providers.subscriptions.addFeed(bUrl, 'B', 'Test');
      providers.feed.update(
        providers.subscriptions,
        providers.settings,
        providers.bookmarks,
      );
      final queued = providers.feed.refreshAll();
      releaseA.complete();
      await queued;
      await _waitForRefresh(providers.feed);

      expect(server.counts['/queued-b.xml'], 1);
      expect(
        providers.feed.items.map((item) => item.id),
        contains('b-article'),
      );
      providers.feed.dispose();
    },
  );

  test(
    'startup cache load completes before conditional refresh can replace state',
    () async {
      final url = server.url('/startup.xml');
      final cached = _item(url, 'cached-startup');
      await _seedSubscriptions([
        FeedSubscription(url: url, name: 'Startup', category: 'Test'),
      ]);
      await _seedCache([cached]);
      await Hive.box('feeds').put(
        'feedValidators',
        jsonEncode({
          url: {'etag': '"v1"'},
        }),
      );
      late FeedProvider feed;
      server.handlers['/startup.xml'] = (request) async {
        await _waitUntil(() => feed.items.isNotEmpty);
        request.response.statusCode = HttpStatus.notModified;
        await request.response.close();
      };

      final subscriptions = SubscriptionProvider();
      final settings = SettingsProvider();
      final bookmarks = BookmarkProvider();
      feed = FeedProvider();
      feed.update(subscriptions, settings, bookmarks);
      await _waitForRefresh(feed);

      expect(feed.items.map((item) => item.id), contains('cached-startup'));
      feed.dispose();
    },
  );

  test(
    'cacheless 304 retries once without validators and processes 200',
    () async {
      final url = server.url('/cacheless-304.xml');
      server.handlers['/cacheless-304.xml'] = (request) =>
          _respondConditional(request, _rss('304', ['after-retry']));
      await _seedSubscriptions([
        FeedSubscription(url: url, name: '304', category: 'Test'),
      ]);
      await Hive.box('feeds').put(
        'feedValidators',
        jsonEncode({
          url: {'etag': '"v1"'},
        }),
      );
      final providers = _providers();
      await _waitForRefresh(providers.feed);

      expect(server.counts['/cacheless-304.xml'], 2);
      expect(
        providers.feed.items.map((item) => item.id),
        contains('after-retry'),
      );
      expect(_persistedItems().map((item) => item.id), contains('after-retry'));
      providers.feed.dispose();
    },
  );

  test(
    'cacheless 304 retried and still 304 drops the validator (issue #28)',
    () async {
      final url = server.url('/always-304.xml');
      server.handlers['/always-304.xml'] = (request) async {
        request.response.statusCode = HttpStatus.notModified;
        await request.response.close();
      };
      await _seedSubscriptions([
        FeedSubscription(url: url, name: '304', category: 'Test'),
      ]);
      await Hive.box('feeds').put(
        'feedValidators',
        jsonEncode({
          url: {'etag': '"v1"'},
        }),
      );
      final providers = _providers();
      await _waitForRefresh(providers.feed);

      // Conditional 304 + unconditional retry 304 → validator must be gone
      // so the next pass is a plain GET instead of retry-looping.
      expect(server.counts['/always-304.xml'], 2);
      final raw = Hive.box('feeds').get('feedValidators') as String?;
      final validators = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map;
      expect(validators.containsKey(url), isFalse);
      providers.feed.dispose();
    },
  );

  test(
    'redirected feed learns final URL and skips the hop next pass (#31)',
    () async {
      final oldUrl = server.url('/old.xml');
      server.handlers['/new.xml'] = (request) async {
        request.response.write('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>R</title>
<item><title>R1</title><guid>r1</guid><link>https://x/r1</link></item>
</channel></rss>''');
        await request.response.close();
      };
      server.handlers['/old.xml'] = (request) async {
        request.response.statusCode = HttpStatus.movedPermanently;
        request.response.headers.set(HttpHeaders.locationHeader, '/new.xml');
        await request.response.close();
      };
      await _seedSubscriptions([
        FeedSubscription(url: oldUrl, name: 'R', category: 'Test'),
      ]);
      final providers = _providers();
      await _waitForRefresh(providers.feed);

      // Learned redirect persisted against the canonical subscription URL.
      final raw = Hive.box('feeds').get('feedRedirects') as String?;
      final redirects = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map;
      expect(redirects[oldUrl], server.url('/new.xml'));
      expect(providers.feed.items.map((i) => i.id), contains('r1'));

      // Next pass fetches the resolved URL directly — no request to /old.xml.
      final oldHits = server.counts['/old.xml'] ?? 0;
      await providers.feed.refreshAll();
      expect(server.counts['/old.xml'], oldHits);
      expect(server.counts['/new.xml'], greaterThanOrEqualTo(2));

      // Items fetched via the learned URL stay tagged with the canonical
      // subscription URL — feed-scoped cache/filter lookups keep matching.
      expect(
        providers.feed.items.where((i) => i.id == 'r1').map((i) => i.feedUrl),
        everyElement(oldUrl),
      );

      // A failing learned-URL pass keeps the feed's existing items.
      server.handlers['/new.xml'] = (request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      };
      await providers.feed.refreshAll();
      expect(providers.feed.items.map((i) => i.id), contains('r1'));
      providers.feed.dispose();
    },
  );

  test(
    'foreground mixed 200 failure and 304 preserves durable per-feed cache',
    () async {
      final aUrl = server.url('/mixed-a.xml');
      final bUrl = server.url('/mixed-b.xml');
      final cUrl = server.url('/mixed-c.xml');
      await _seedSubscriptions([
        FeedSubscription(url: aUrl, name: 'A', category: 'Test'),
        FeedSubscription(url: bUrl, name: 'B', category: 'Test'),
        FeedSubscription(url: cUrl, name: 'C', category: 'Test'),
      ]);
      await _seedCache([
        _item(aUrl, 'a-old'),
        _item(bUrl, 'b-old'),
        _item(cUrl, 'c-old'),
      ]);
      await Hive.box('feeds').put(
        'feedValidators',
        jsonEncode({
          cUrl: {'etag': '"v1"'},
        }),
      );
      server.handlers['/mixed-a.xml'] = (request) =>
          _respond200(request, _rss('A', ['a-new']));
      server.handlers['/mixed-b.xml'] = (request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      };
      server.handlers['/mixed-c.xml'] = (request) async {
        request.response.statusCode = HttpStatus.notModified;
        await request.response.close();
      };
      final providers = _providers(wire: false);
      await _waitUntil(() => providers.feed.items.length == 3);
      providers.feed.update(
        providers.subscriptions,
        providers.settings,
        providers.bookmarks,
      );
      await _waitForRefresh(providers.feed);

      final ids = _persistedItems().map((item) => item.id).toSet();
      expect(ids, containsAll(<String>['a-new', 'b-old', 'c-old']));
      expect(ids, isNot(contains('a-old')));
      providers.feed.dispose();
    },
  );

  test(
    'background partial failure merges cache instead of deleting failed feed',
    () async {
      final aUrl = server.url('/background-a.xml');
      final bUrl = server.url('/background-b.xml');
      final cUrl = server.url('/background-c.xml');
      await _seedSubscriptions([
        FeedSubscription(url: aUrl, name: 'A', category: 'Test'),
        FeedSubscription(url: bUrl, name: 'B', category: 'Test'),
        FeedSubscription(url: cUrl, name: 'C', category: 'Test'),
      ]);
      await _seedCache([
        _item(aUrl, 'a-old'),
        _item(bUrl, 'b-old'),
        _item(cUrl, 'c-old'),
      ]);
      server.handlers['/background-a.xml'] = (request) =>
          _respond200(request, _rss('A', ['a-new']));
      server.handlers['/background-b.xml'] = (request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      };
      server.handlers['/background-c.xml'] = (request) =>
          _respond200(request, _rss('C', ['c-new']));

      await runBgFetch();

      final ids = _persistedItems().map((item) => item.id).toSet();
      expect(ids, containsAll(<String>['a-new', 'b-old', 'c-new']));
      expect(ids, isNot(contains('a-old')));
      expect(ids, isNot(contains('c-old')));
    },
  );

  test('restart without network refresh restores persisted articles', () async {
    final url = server.url('/restart.xml');
    await _seedSubscriptions([
      FeedSubscription(url: url, name: 'Restart', category: 'Test'),
    ]);
    await _seedCache([_item(url, 'offline-article')]);

    final first = _providers(wire: false).feed;
    await _waitUntil(() => first.items.isNotEmpty);
    expect(first.items.single.id, 'offline-article');
    first.dispose();

    final restarted = _providers(wire: false).feed;
    await _waitUntil(() => restarted.items.isNotEmpty);
    expect(restarted.items.single.id, 'offline-article');
    restarted.dispose();
  });

  test(
    'offline cache limit selects the globally newest items across feeds',
    () async {
      // #37: no per-feed fair share — the limit is the newest N unique
      // articles globally, so a busier feed can hold more slots and the
      // oldest candidates drop regardless of source.
      await Hive.box('settings').put('offlineCacheLimit', 6);
      final aUrl = server.url('/fair-a.xml');
      final bUrl = server.url('/fair-b.xml');
      final cUrl = server.url('/fair-c.xml');
      await _seedSubscriptions([
        FeedSubscription(url: aUrl, name: 'A', category: 'Test'),
        FeedSubscription(url: bUrl, name: 'B', category: 'Test'),
        FeedSubscription(url: cUrl, name: 'C', category: 'Test'),
      ]);
      server.handlers['/fair-a.xml'] = (request) =>
          _respond200(request, _rss('A', ['a1', 'a2', 'a3'], hour: 12));
      server.handlers['/fair-b.xml'] = (request) =>
          _respond200(request, _rss('B', ['b1', 'b2'], hour: 11));
      server.handlers['/fair-c.xml'] = (request) =>
          _respond200(request, _rss('C', ['c1', 'c2'], hour: 10));

      final providers = _providers();
      await _waitForRefresh(providers.feed);

      // Seven candidates, six slots: only the globally oldest (c2) drops.
      expect(_persistedItems().map((item) => item.id).toList(), <String>[
        'a1',
        'a2',
        'a3',
        'b1',
        'b2',
        'c1',
      ]);
      providers.feed.dispose();
    },
  );

  test(
    'hasFeedUrl rejects canonical duplicates and surfaces legacy dupes',
    () async {
      final subs = SubscriptionProvider();
      expect(await subs.addFeed('https://x.com/feed', 'A', 'T'), isTrue);
      // Scheme/host case, default port, and trailing slash all canonicalize
      // to the stored URL → rejected as an already-subscribed feed.
      expect(subs.hasFeedUrl('HTTPS://X.COM/feed/'), isTrue);
      expect(await subs.addFeed('https://x.com/feed/', 'B', 'T'), isFalse);
      expect(subs.subscriptions, hasLength(1));

      // A different path is genuinely different.
      expect(await subs.addFeed('https://x.com/other', 'C', 'T'), isTrue);

      // Legacy dupes seeded directly still surface via duplicateFeedUrls.
      await _seedSubscriptions([
        FeedSubscription(url: 'https://x.com/feed', name: 'A', category: 'T'),
        FeedSubscription(url: 'https://x.com/feed/', name: 'B', category: 'T'),
      ]);
      final seeded = SubscriptionProvider();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seeded.duplicateFeedUrls, {'https://x.com/feed/'});
    },
  );

  test(
    'category add/rename blocks case-variant twins and silent merges',
    () async {
      final subs = SubscriptionProvider();
      await subs.addFeed('https://x.com/a', 'A', 'News');
      await subs.addFeed('https://x.com/b', 'B', 'Sports');

      // Case-variant add → refused, no twin folder.
      expect(await subs.addCategory('news'), isFalse);
      expect(await subs.addCategory('  NEWS  '), isFalse);
      expect(await subs.addCategory('Tech'), isTrue);

      // Rename onto an existing category (any case) → refused: silent
      // merge would also clobber the target's icon.
      expect(await subs.renameCategory('Sports', 'news'), isFalse);
      expect(subs.categories, contains('Sports'));
      expect(subs.subscriptions[1].category, 'Sports');

      // Renaming to the same category stays a no-op success.
      expect(await subs.renameCategory('Sports', 'Sports'), isTrue);
      expect(await subs.renameCategory('Sports', 'sports'), isTrue);
      expect(subs.subscriptions[1].category, 'sports');

      // Renaming to a fresh name works.
      expect(await subs.renameCategory('sports', 'Athletics'), isTrue);
      expect(subs.categories, contains('Athletics'));
      expect(subs.categories, isNot(contains('sports')));
    },
  );

  test(
    'editSubscription rejects invalid URLs and canonical duplicates',
    () async {
      final subs = SubscriptionProvider();
      await subs.addFeed('https://x.com/a', 'A', 'T');
      await subs.addFeed('https://x.com/b', 'B', 'T');

      // Invalid URL format → rejected, subscription unchanged.
      expect(
        await subs.editSubscription('https://x.com/a', 'not a url', 'A'),
        isFalse,
      );
      expect(subs.subscriptions.first.url, 'https://x.com/a');

      // Canonical collision with another subscription → rejected.
      expect(
        await subs.editSubscription('https://x.com/a', 'HTTPS://X.COM/b/', 'A'),
        isFalse,
      );
      expect(subs.subscriptions.first.url, 'https://x.com/a');

      // Renaming to itself (canonical match with own URL) stays allowed.
      expect(
        await subs.editSubscription(
          'https://x.com/a',
          'https://x.com/a/',
          'A2',
        ),
        isTrue,
      );
      expect(subs.subscriptions.first.name, 'A2');

      // A genuinely new URL succeeds.
      expect(
        await subs.editSubscription(
          'https://x.com/a/',
          'https://x.com/c',
          'A2',
        ),
        isTrue,
      );
      expect(subs.subscriptions.first.url, 'https://x.com/c');
    },
  );

  test(
    'failed feed records a persisted error that clears on recovery',
    () async {
      final url = server.url('/flaky.xml');
      var fail = true;
      server.handlers['/flaky.xml'] = (request) async {
        if (fail) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } else {
          await _respond200(request, _rss('Flaky', ['ok-1']));
        }
      };
      await _seedSubscriptions([
        FeedSubscription(url: url, name: 'Flaky', category: 'Test'),
      ]);

      final providers = _providers();
      await _waitForRefresh(providers.feed);

      // Recorded error keeps the real cause (HTTP 500), not a flattened
      // "could not fetch" message — the action sheet shows this text.
      expect(providers.feed.feedErrorFor(url), contains('500'));
      // Persisted so a restart still shows the feed as unhealthy.
      expect(
        (Hive.box('feeds').get('feedErrors') as Map).containsKey(url),
        isTrue,
      );

      fail = false;
      await providers.feed.refreshAll();
      await _waitForRefresh(providers.feed);
      expect(providers.feed.feedErrorFor(url), isNull);
      expect(
        (Hive.box('feeds').get('feedErrors') as Map).containsKey(url),
        isFalse,
      );
      providers.feed.dispose();
    },
  );

  test(
    '429 response backs the feed off — no refetch until Retry-After passes',
    () async {
      final url = server.url('/rate.xml');
      server.handlers['/rate.xml'] = (request) async {
        request.response.statusCode = HttpStatus.tooManyRequests;
        request.response.headers.set('retry-after', '1');
        await request.response.close();
      };
      await _seedSubscriptions([
        FeedSubscription(url: url, name: 'Rate', category: 'Test'),
      ]);

      final providers = _providers();
      await _waitForRefresh(providers.feed);
      expect(server.counts['/rate.xml'], 1);
      expect(providers.feed.feedErrorFor(url), contains('429'));

      // Backoff active — an immediate second refresh must not hit the server.
      await providers.feed.refreshAll();
      await _waitForRefresh(providers.feed);
      expect(server.counts['/rate.xml'], 1);
      // The stored error survives the skipped pass — the feed still reads
      // as unhealthy instead of flipping to a phantom "all good".
      expect(providers.feed.feedErrorFor(url), contains('429'));

      // Once the server-issued wait elapses the feed is fetched again.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await providers.feed.refreshAll();
      await _waitForRefresh(providers.feed);
      expect(server.counts['/rate.xml'], 2);
      providers.feed.dispose();
    },
  );

  test(
    'subscriptions on the same host are fetch-paced',
    () async {
      final hitTimes = <String, List<DateTime>>{};
      void paced(String path) {
        server.handlers[path] = (request) async {
          (hitTimes[path] ??= []).add(DateTime.now());
          await _respond200(request, _rss(path, ['i-$path']));
        };
      }

      paced('/s1.xml');
      paced('/s2.xml');
      paced('/s3.xml');
      final subs = [
        FeedSubscription(
          url: server.url('/s1.xml'),
          name: 'S1',
          category: 'Test',
        ),
        FeedSubscription(
          url: server.url('/s2.xml'),
          name: 'S2',
          category: 'Test',
        ),
        FeedSubscription(
          url: server.url('/s3.xml'),
          name: 'S3',
          category: 'Test',
        ),
      ];

      final refresher = FeedRefresher(
        feedService: FeedService(),
        observedArticleStore: ObservedArticleStore.forBox(Hive.box('feeds')),
        hostGap: const Duration(milliseconds: 300),
      );
      await refresher.refresh(
        subscriptions: subs,
        existingItems: const [],
        validators: const {},
        bookmarkedItems: const [],
        redirects: const {},
      );

      // All three share one authority — hits must be spread by ~300ms.
      final all = hitTimes.values.expand((t) => t).toList()..sort();
      expect(all, hasLength(3));
      expect(
        all.last.difference(all.first),
        greaterThanOrEqualTo(const Duration(milliseconds: 550)),
      );
    },
  );

  test(
    'prefetch stores full text for full-text feeds only (issue #14 policy)',
    () async {
      final ftUrl = server.url('/ft.xml');
      final plainUrl = server.url('/plain.xml');
      final articleUrl = server.url('/a1.html');
      final plainArticleUrl = server.url('/p1.html');
      String feed(String link) =>
          '''<?xml version="1.0"?>
<rss version="2.0"><channel><title>F</title><link>https://x</link>
<item><title>t</title><guid>g</guid><link>$link</link><pubDate>Wed, 26 Aug 2026 10:00:00 +0000</pubDate></item>
</channel></rss>''';
      Future<void> html(HttpRequest r) async {
        r.response.headers.contentType = ContentType('text', 'html');
        r.response.write(
          '<html><body><article><p>${List.filled(40, 'Long paragraph of article body text for extraction.').join(' ')}</p></article></body></html>',
        );
        await r.response.close();
      }

      server.handlers['/ft.xml'] = (r) => _respond200(r, feed(articleUrl));
      server.handlers['/plain.xml'] = (r) =>
          _respond200(r, feed(plainArticleUrl));
      server.handlers['/a1.html'] = html;
      server.handlers['/p1.html'] = html;
      await _seedSubscriptions([
        FeedSubscription(
          url: ftUrl,
          name: 'FT',
          category: 'T',
          fullTextEnabled: true,
        ),
        FeedSubscription(url: plainUrl, name: 'Plain', category: 'T'),
      ]);

      final providers = _providers();
      await _waitForRefresh(providers.feed);

      // Prefetch is fire-and-forget after refresh — poll for the FT item's
      // prefetched body, then the same pass has finished so Plain asserts.
      FeedItem find(String feedUrl) =>
          providers.feed.items.firstWhere((i) => i.feedUrl == feedUrl);
      await _waitUntil(
        () => find(ftUrl).prefetchedFullText != null,
        timeout: const Duration(seconds: 15),
      );

      expect(find(ftUrl).prefetchedFullText, contains('article body text'));
      // Non-full-text feed shares the same pipeline but is never prefetched.
      expect(find(plainUrl).prefetchedFullText, isNull);
      // The feed-supplied body is untouched — prefetch lives in its own field.
      expect(find(ftUrl).content, isNot(contains('article body text')));
      // Persisted inside cachedItemsJson so it survives a restart.
      await _waitUntil(
        () =>
            _persistedItems()
                .singleWhere((item) => item.feedUrl == ftUrl)
                .prefetchedFullText !=
            null,
      );
      expect(
        _persistedItems()
            .singleWhere((i) => i.feedUrl == ftUrl)
            .prefetchedFullText,
        contains('article body text'),
      );
      providers.feed.dispose();
    },
  );

  test('prefetch caps at five, tolerates failures, and survives next refresh '
      '(issue #14 policy)', () async {
    final ftUrl = server.url('/cap.xml');
    var articleRequests = 0;
    final items = List.generate(
      7,
      (i) =>
          '<item><title>a$i</title><guid>g$i</guid>'
          '<link>${server.url('/cap$i.html')}</link>'
          '<pubDate>Wed, 26 Aug 2026 10:${(59 - i).toString().padLeft(2, '0')}:00 +0000</pubDate></item>',
    ).join();
    server.handlers['/cap.xml'] = (r) => _respond200(
      r,
      '<?xml version="1.0"?><rss version="2.0"><channel>'
      '<title>C</title><link>https://x</link>$items</channel></rss>',
    );
    for (var i = 0; i < 7; i++) {
      final n = i;
      server.handlers['/cap$i.html'] = (r) async {
        articleRequests++;
        if (n == 2) {
          // g2's page is bot-blocked — extraction fails, item survives.
          r.response.statusCode = HttpStatus.notFound;
          await r.response.close();
          return;
        }
        r.response.headers.contentType = ContentType('text', 'html');
        r.response.write(
          '<html><body><article><p>${List.filled(40, 'Body $n article text.').join(' ')}</p></article></body></html>',
        );
        await r.response.close();
      };
    }
    await _seedSubscriptions([
      FeedSubscription(
        url: ftUrl,
        name: 'Cap',
        category: 'T',
        fullTextEnabled: true,
      ),
    ]);

    final providers = _providers();
    await _waitForRefresh(providers.feed);
    FeedItem? byId(String id) =>
        providers.feed.items.where((i) => i.id == id).firstOrNull;

    // Newest five attempted; g2 failed; four prefetched, two never touched.
    // Wait on persistence (the pass's last step) so _isPrefetching has
    // settled before the second refresh below — otherwise that pass is
    // skipped by the in-flight guard and the counts drift.
    await _waitUntil(
      () =>
          _persistedItems().where((i) => i.prefetchedFullText != null).length ==
          4,
      timeout: const Duration(seconds: 15),
    );
    expect(articleRequests, 5);
    for (final id in ['g0', 'g1', 'g3', 'g4']) {
      expect(byId(id)?.prefetchedFullText, isNotNull, reason: id);
    }
    for (final id in ['g5', 'g6']) {
      expect(byId(id)?.prefetchedFullText, isNull, reason: id);
    }
    // Extraction failure leaves the RSS item intact, only without content.
    expect(byId('g2'), isNotNull);
    expect(byId('g2')!.prefetchedFullText, isNull);

    // Second refresh: fresh parse must carry prefetched bodies over.
    // Missing set is now [g2, g5, g6]; g2's URL is in the service's
    // session failure cache, so only g5 and g6 hit the network.
    await providers.feed.refreshAll();
    await _waitForRefresh(providers.feed);
    await _waitUntil(
      () =>
          byId('g5')?.prefetchedFullText != null &&
          byId('g6')?.prefetchedFullText != null,
      timeout: const Duration(seconds: 15),
    );
    expect(articleRequests, 7);
    for (final id in ['g0', 'g1', 'g3', 'g4', 'g5', 'g6']) {
      expect(byId(id)?.prefetchedFullText, isNotNull, reason: id);
    }
    expect(byId('g2')!.prefetchedFullText, isNull);
    providers.feed.dispose();
  });

  test('connectivity-only failure does not flag the feed', () async {
    // Bind then close a port so connecting yields a refused socket — the same
    // connectivity class as airplane mode, not a dead feed.
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close(force: true);
    final url = 'http://127.0.0.1:$port/dead.xml';
    await _seedSubscriptions([
      FeedSubscription(url: url, name: 'Dead', category: 'Test'),
    ]);

    final providers = _providers();
    await _waitForRefresh(providers.feed);

    // Whole pass offline → the failure proves nothing → no error recorded.
    expect(providers.feed.feedErrorFor(url), isNull);
    providers.feed.dispose();
  });

  test('offline pass does not stamp lastSyncTime (issue #27)', () async {
    // Only a dead feed → the whole pass fails connectivity → no stamp.
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close(force: true);
    final deadUrl = 'http://127.0.0.1:$deadPort/dead.xml';
    await _seedSubscriptions([
      FeedSubscription(url: deadUrl, name: 'Dead', category: 'T'),
    ]);

    final providers = _providers();
    await _waitForRefresh(providers.feed);
    expect(providers.feed.lastSyncTime, isNull);

    // Swap in a live feed → an online pass must stamp.
    final liveUrl = server.url('/live.xml');
    server.handlers['/live.xml'] = (r) => _respond200(r, _rss('Live', ['l1']));
    await _seedSubscriptions([
      FeedSubscription(url: liveUrl, name: 'Live', category: 'T'),
    ]);
    providers.feed.dispose();

    final providers2 = _providers();
    await _waitForRefresh(providers2.feed);
    expect(providers2.feed.lastSyncTime, isNotNull);
    providers2.feed.dispose();
  });

  test(
    'factory reset during an in-flight refresh voids the whole apply phase',
    () async {
      final url = server.url('/reset-mid-fetch.xml');
      final requested = Completer<void>();
      final release = Completer<void>();
      server.handlers['/reset-mid-fetch.xml'] = (request) async {
        if (!requested.isCompleted) requested.complete();
        await release.future;
        await _respond200(request, _rss('F', ['a1']));
      };
      await _seedSubscriptions([
        FeedSubscription(url: url, name: 'F', category: 'Test'),
      ]);
      final providers = _providers(); // update() kicks the initial refresh
      await requested.future; // the fetch is in flight, response pending

      // The reset completes while the network response is still pending —
      // everything the refresh would apply belongs to the wiped era (#40).
      final wiped = await providers.feed.factoryReset();
      expect(wiped, isTrue);

      release.complete();
      await _waitForRefresh(providers.feed);

      // Voided apply: no items, no snapshot, no validators — the wiped
      // box stays wiped.
      expect(providers.feed.items, isEmpty);
      expect(Hive.box('feeds').get('cachedItemsJson'), isNull);
      expect(Hive.box('feeds').get('feedValidators'), isNull);
      providers.feed.dispose();
    },
  );

  test(
    'factory reset during add-subscription voids the whole transaction',
    () async {
      final url = server.url('/reset-mid-add.xml');
      final requested = Completer<void>();
      final release = Completer<void>();
      server.handlers['/reset-mid-add.xml'] = (request) async {
        if (!requested.isCompleted) requested.complete();
        await release.future;
        await _respond200(request, _rss('F', ['a1']));
      };
      // No seed — the gated handler must only see the add's fetch, so
      // nothing else may trigger a refresh that would park on `release`.
      final providers = _providers();

      final addFuture = providers.feed.addSubscriptionAndRefresh(
        url,
        'New',
        'Test',
      );
      await requested.future; // the authoritative fetch is in flight

      await providers.feed.factoryReset();
      release.complete();

      expect(await addFuture, isFalse);
      expect(providers.subscriptions.hasFeedUrl(url), isFalse);
      expect(providers.feed.items, isEmpty);
      expect(Hive.box('feeds').get('cachedItemsJson'), isNull);
      providers.feed.dispose();
    },
  );

  test('un-bookmark strips the durable bookmark owner', () async {
    final store = ArticleRecordStore.forBox(Hive.box('feeds'));
    final url = server.url('/bm-strip.xml');
    final item = _item(url, 'b1');
    await store.write(
      ArticleRecord(id: 'b1', feedUrl: url, owners: const {'bookmark'}),
    );

    final bookmarks = BookmarkProvider();
    bookmarks.toggleBookmark(item); // add
    await _waitUntil(() => bookmarks.isBookmarked('b1'));
    bookmarks.toggleBookmark(item); // remove → owner strip is unawaited
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    ArticleRecord? record;
    do {
      record = await store.read('b1');
      if (record == null || !record.owners.contains('bookmark')) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    } while (DateTime.now().isBefore(deadline));
    expect(record?.owners ?? const <String>{}, isNot(contains('bookmark')));
  });

  group('S6 offline status wiring', () {
    ArticlePreparationService newPrep() => ArticlePreparationService(
      recordStore: ArticleRecordStore.forBox(Hive.box('feeds')),
      mediaStore: ArticleMediaStore(),
      // Deterministic: no real network for extraction or media.
      extractFullText: (_) async => null,
    );

    test('status map reports loaded only after the first read', () async {
      final providers = _providers(wire: false);
      final prep = newPrep();
      providers.feed.dispose();
      final feed = FeedProvider(preparation: prep);
      expect(feed.articleStatusesLoaded, isFalse);
      feed.update(
        providers.subscriptions,
        providers.settings,
        providers.bookmarks,
      );
      await _waitUntil(() => feed.articleStatusesLoaded);
      feed.dispose();
    });

    test(
      'a committed bookmark claim refreshes the status map on its own',
      () async {
        final prep = newPrep();
        final providers = _providers(wire: false);
        providers.feed.dispose();
        final bookmarks = BookmarkProvider(preparation: prep);
        final feed = FeedProvider(preparation: prep);
        feed.update(providers.subscriptions, providers.settings, bookmarks);
        // Mirror what ChangeNotifierProxyProvider does in the app: every
        // upstream notify re-runs update(), where the claimVersion diff
        // picks up landed claim mutations.
        bookmarks.addListener(
          () => feed.update(
            providers.subscriptions,
            providers.settings,
            bookmarks,
          ),
        );
        await _waitUntil(() => feed.articleStatusesLoaded);

        // The register+prepare chain is unawaited inside toggleBookmark —
        // the claimVersion bump is what must carry the fresh label into
        // the feed's status map (#41 ordering).
        bookmarks.toggleBookmark(_item(server.url('/f.xml'), 'st1'));
        await _waitUntil(() => feed.articleStatus('st1') != null);
        expect(feed.articleStatus('st1')!.hasBookmark, isTrue);
        feed.dispose();
      },
    );

    test('retrySaveArticle keeps the feed full-text preference', () async {
      // Per-feed fullTextEnabled=false with global extraction ON — the
      // retry path must not silently re-arm extraction (#41).
      await Hive.box('settings').put('autoFullText', true);
      final url = server.url('/save-pref.xml');
      await _seedSubscriptions([
        FeedSubscription(
          url: url,
          name: 'Pref',
          category: 'Test',
          fullTextEnabled: false,
        ),
      ]);
      final prep = newPrep();
      final providers = _providers(wire: false);
      providers.feed.dispose();
      final bookmarks = BookmarkProvider(preparation: prep);
      final feed = FeedProvider(preparation: prep);
      feed.update(providers.subscriptions, providers.settings, bookmarks);
      await _waitUntil(() => feed.articleStatusesLoaded);

      final item = _item(url, 'rs1');
      bookmarks.toggleBookmark(item);
      await _waitUntil(() => bookmarks.isBookmarked('rs1'));
      await feed.retrySaveArticle(item.copyWith(isBookmarked: true));

      final record = await ArticleRecordStore.forBox(
        Hive.box('feeds'),
      ).read('rs1');
      expect(record, isNotNull);
      expect(
        record!.bodyState,
        MediaState.ready,
        reason:
            'fullText=false settles the RSS body — a dropped preference '
            'would leave extraction intent pending',
      );
      feed.dispose();
    });

    test('bookmark save honors the feed full-text preference', () async {
      // The SAVE path must respect the same tri-state the retry path does:
      // fullTextFor=false → the RSS body settles, no extraction armed.
      final prep = newPrep();
      final providers = _providers(wire: false);
      providers.feed.dispose();
      final bookmarks = BookmarkProvider(
        preparation: prep,
        fullTextFor: (_) => false,
      );
      final feed = FeedProvider(preparation: prep);
      feed.update(providers.subscriptions, providers.settings, bookmarks);
      bookmarks.addListener(
        () =>
            feed.update(providers.subscriptions, providers.settings, bookmarks),
      );
      await _waitUntil(() => feed.articleStatusesLoaded);

      bookmarks.toggleBookmark(_item(server.url('/f.xml'), 'pf1'));
      // The claim lands async; the status map appearing proves the record
      // committed (status derives only from durable records).
      await _waitUntil(() => feed.articleStatus('pf1') != null);
      final record = await ArticleRecordStore.forBox(
        Hive.box('feeds'),
      ).read('pf1');
      expect(record!.bodyState, MediaState.ready);
      feed.dispose();
    });
  });
}
