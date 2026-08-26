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
      await Future<void>.delayed(const Duration(milliseconds: 100));

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
        'lib/widgets/explore_feeds_dialog.dart',
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
}
