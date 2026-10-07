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
import 'package:ice_cream_rss_reader/services/background_fetch_service.dart';
import 'package:ice_cream_rss_reader/services/feed_cache_policy.dart';

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
    'offline cache limit uses deterministic round-robin across feeds',
    () async {
      await Hive.box('settings').put('offlineCacheLimit', 6);
      final aUrl = server.url('/fair-a.xml');
      final bUrl = server.url('/fair-b.xml');
      final cUrl = server.url('/fair-c.xml');
      await _seedSubscriptions([
        FeedSubscription(url: aUrl, name: 'A', category: 'Test'),
        FeedSubscription(url: bUrl, name: 'B', category: 'Test'),
        FeedSubscription(url: cUrl, name: 'C', category: 'Test'),
      ]);
      server.handlers['/fair-a.xml'] = (request) => _respond200(
        request,
        _rss('A', ['a1', 'a2', 'a3', 'a4', 'a5', 'a6'], hour: 12),
      );
      server.handlers['/fair-b.xml'] = (request) =>
          _respond200(request, _rss('B', ['b1', 'b2'], hour: 10));
      server.handlers['/fair-c.xml'] = (request) =>
          _respond200(request, _rss('C', ['c1', 'c2'], hour: 8));

      final providers = _providers();
      await _waitForRefresh(providers.feed);

      expect(_persistedItems().map((item) => item.id).toList(), <String>[
        'a1',
        'b1',
        'c1',
        'a2',
        'b2',
        'c2',
      ]);
      providers.feed.dispose();
    },
  );

  test(
    'fair cache trim fills unused rounds without exceeding global limit',
    () {
      const a = 'https://a.test/rss';
      const b = 'https://b.test/rss';
      const c = 'https://c.test/rss';
      final base = DateTime.utc(2026, 8, 26, 12);
      final selected = FeedCachePolicy.fairTrim(
        items: [
          _item(b, 'b4', date: base.subtract(const Duration(minutes: 4))),
          _item(c, 'c2', date: base.subtract(const Duration(minutes: 2))),
          _item(a, 'a1', date: base),
          _item(b, 'b2', date: base.subtract(const Duration(minutes: 2))),
          _item(c, 'c1', date: base),
          _item(b, 'b1', date: base),
          _item(b, 'b3', date: base.subtract(const Duration(minutes: 3))),
        ],
        subscribedFeedUrls: const [a, b, c],
        limit: 6,
      );

      expect(selected.map((item) => item.id), [
        'a1',
        'b1',
        'c1',
        'b2',
        'c2',
        'b3',
      ]);
      expect(selected, hasLength(6));
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
        () => _persistedItems()
            .singleWhere((item) => item.feedUrl == ftUrl)
            .prefetchedFullText != null,
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
}
