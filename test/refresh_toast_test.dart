import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/utils/app_toast.dart';
import 'package:ice_cream_rss_reader/widgets/refresh_completion_listener.dart';

typedef _RequestHandler = FutureOr<void> Function(HttpRequest request);

class _FeedServer {
  _FeedServer._(this._server) {
    _server.listen((request) async {
      final handler = handlers[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      counts.update(request.uri.path, (v) => v + 1, ifAbsent: () => 1);
      await handler(request);
    });
  }

  final HttpServer _server;
  final Map<String, _RequestHandler> handlers = {};
  final Map<String, int> counts = {};

  static Future<_FeedServer> start() async =>
      _FeedServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  String url(String path) =>
      'http://${_server.address.host}:${_server.port}$path';

  Future<void> close() => _server.close(force: true);
}

String _rss(String title, Iterable<String> ids) {
  final items = ids
      .map(
        (id) =>
            '<item><guid>$id</guid><title>$title $id</title>'
            '<link>http://x/$id</link></item>',
      )
      .join();
  return '<?xml version="1.0"?><rss version="2.0"><channel>'
      '<title>$title</title>$items</channel></rss>';
}

Future<void> _ok(HttpRequest req, String body) async {
  req.response.headers.contentType = ContentType('application', 'rss+xml');
  req.response.write(body);
  await req.response.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FeedServer server;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    // Real loopback server — the widget-test binding would block sockets.
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('refresh-toast-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('home_widget'),
          (_) async => true,
        );
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
  });

  setUp(() async {
    await Hive.box('settings').clear();
    await Hive.box('feeds').clear();
    await Hive.box('bookmarks').clear();
    await ArticleRecordStore.forBox(Hive.box('feeds')).wipeAll();
    appToastController.dismiss();
    server = await _FeedServer.start();
  });

  tearDown(() async {
    appToastController.dismiss();
    await server.close();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  FeedProvider makeProvider() {
    final subscriptions = SubscriptionProvider();
    final settings = SettingsProvider();
    final bookmarks = BookmarkProvider();
    return FeedProvider()..update(subscriptions, settings, bookmarks);
  }

  Future<void> seedSubs(List<FeedSubscription> subs) => Hive.box('feeds').put(
    'subscriptions',
    jsonEncode(subs.map((s) => s.toJson()).toList()),
  );

  /// Wires the announcer exactly like [RefreshCompletionListener] does, minus
  /// the widget tree — toast assertions then stay in the real event loop.
  RefreshToastAnnouncer attachAnnouncer(FeedProvider feed) {
    final announcer = RefreshToastAnnouncer();
    feed.refreshProgress.addListener(
      () => announcer.onProgress(feed.refreshProgress.value, l10n),
    );
    return announcer;
  }

  test('user refresh shows one success toast', () async {
    server.handlers['/ok.xml'] = (r) => _ok(r, _rss('A', ['a1']));
    await seedSubs([
      FeedSubscription(url: server.url('/ok.xml'), name: 'A', category: 'T'),
    ]);
    final feed = makeProvider();
    addTearDown(feed.dispose);
    attachAnnouncer(feed);

    await feed.refreshAll(userInitiated: true);

    final toast = appToastController.current;
    expect(toast, isNotNull);
    expect(toast!.type, AppToastType.success);
    expect(toast.message, contains('1'));
  });

  test('automatic refresh produces no toast', () async {
    server.handlers['/ok.xml'] = (r) => _ok(r, _rss('A', ['a1']));
    await seedSubs([
      FeedSubscription(url: server.url('/ok.xml'), name: 'A', category: 'T'),
    ]);
    final feed = makeProvider();
    addTearDown(feed.dispose);
    attachAnnouncer(feed);

    await feed.refreshAll();

    expect(appToastController.current, isNull);
  });

  test('partial failure shows summary toast with counts', () async {
    server.handlers['/ok.xml'] = (r) => _ok(r, _rss('A', ['a1']));
    await seedSubs([
      FeedSubscription(url: server.url('/ok.xml'), name: 'A', category: 'T'),
      FeedSubscription(url: server.url('/gone.xml'), name: 'G', category: 'T'),
    ]);
    final feed = makeProvider();
    addTearDown(feed.dispose);
    attachAnnouncer(feed);

    await feed.refreshAll(userInitiated: true);

    final toast = appToastController.current;
    expect(toast, isNotNull);
    expect(toast!.type, AppToastType.info);
    expect(toast.message, contains('1'));
  });

  test('empty subscription list shows friendly message', () async {
    final feed = makeProvider();
    addTearDown(feed.dispose);
    attachAnnouncer(feed);

    await feed.refreshAll(userInitiated: true);

    expect(appToastController.current, isNotNull);
    expect(appToastController.current!.type, AppToastType.info);
  });

  test('manual attach to running pass produces exactly one toast', () async {
    final gate = Completer<void>();
    server.handlers['/slow.xml'] = (r) async {
      await gate.future.timeout(const Duration(seconds: 5));
      return _ok(r, _rss('A', ['a1']));
    };
    await seedSubs([
      FeedSubscription(url: server.url('/slow.xml'), name: 'A', category: 'T'),
    ]);
    final feed = makeProvider();
    addTearDown(feed.dispose);
    attachAnnouncer(feed);

    // Automatic pass starts; two manual taps attach mid-flight — one pass,
    // one toast, one server hit.
    final autoPass = feed.refreshAll();
    final manualA = feed.refreshAll(userInitiated: true);
    final manualB = feed.refreshAll(userInitiated: true);
    gate.complete();
    await Future.wait([autoPass, manualA, manualB]);

    expect(appToastController.current, isNotNull);
    expect(appToastController.current!.type, AppToastType.success);
    expect(server.counts['/slow.xml'], 1);
  });

  test('all feeds failing shows the all-failed message', () async {
    await seedSubs([
      FeedSubscription(url: server.url('/gone.xml'), name: 'G', category: 'T'),
    ]);
    final feed = makeProvider();
    addTearDown(feed.dispose);
    attachAnnouncer(feed);

    await feed.refreshAll(userInitiated: true);

    final toast = appToastController.current;
    expect(toast, isNotNull);
    expect(toast!.type, AppToastType.error);
  });
}
