import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/feed_discovery.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/widgets/adaptive_dialog.dart';
import 'package:ice_cream_rss_reader/widgets/add_feed_dialog.dart';

final FeedPage _page = (
  bodyBytes: Uint8List.fromList(utf8.encode('<html></html>')),
  url: 'https://site.test/',
  contentType: 'text/html',
);

/// Records the add/discover calls the dialog makes; adds succeed unless the
/// address is in [pages] (a web page) or [broken] (a feed that fails).
class _FakeFeeds extends FeedProvider {
  final added = <String>[];
  final discovered = <FeedPage>[];
  Set<String> pages = {};
  Set<String> broken = {};
  List<DiscoveredFeed> found = const [];

  @override
  Future<bool> addSubscriptionAndRefresh(
    String url,
    String name,
    String category,
  ) async {
    added.add(url);
    if (pages.contains(url)) {
      throw FeedFetchException(FeedFetchErrorKind.parse, 'page', page: _page);
    }
    if (broken.contains(url)) {
      throw FeedFetchException(FeedFetchErrorKind.parse, 'broken');
    }
    return true;
  }

  @override
  Future<List<DiscoveredFeed>> discoverFeeds(FeedPage page) async {
    discovered.add(page);
    return found;
  }

  @override
  Future<void> refreshAll({
    bool queueIfRunning = false,
    bool userInitiated = false,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late SubscriptionProvider subs;
  late _FakeFeeds feeds;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('add_feed_discovery');
    Hive.init(tempDir.path);
    for (final name in ['settings', 'feeds', 'bookmarks']) {
      await Hive.openBox(name);
    }
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    // Not awaited: see the Hive notes in folder_actions_test.dart.
    final box = Hive.box('feeds');
    box.deleteAll(box.keys.toList());
    box.put(
      'subscriptions',
      jsonEncode([
        FeedSubscription(
          url: 'https://site.test/atom.xml',
          name: 'Existing',
          category: 'Tech',
        ).toJson(),
      ]),
    );
    subs = SubscriptionProvider();
    feeds = _FakeFeeds();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> submit(
    WidgetTester tester,
    String url, {
    String? name = 'Site',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SubscriptionProvider>.value(value: subs),
          ChangeNotifierProvider<FeedProvider>.value(value: feeds),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: Builder(
                    builder: (ctx) => TextButton(
                      onPressed: () =>
                          showAdaptiveSheet<void>(ctx, const AddFeedDialog()),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. https://techcrunch.com/feed/'),
      url,
    );
    if (name != null) {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'TechCrunch, BBC News…'),
        name,
      );
    }
    await tester.tap(find.text('Save Feed'));
    await settle(tester);
  }

  bool dialogOpen() => find.byType(AddFeedDialog).evaluate().isNotEmpty;

  // Toasts and provider timers outlive the assertions; let them run out.
  void dialogTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        await tester.pump(const Duration(seconds: 10));
      });

  dialogTest('an address typed without https:// and without a name is '
      'added, named after the site', (tester) async {
    await submit(tester, 'site.test/news', name: null);

    expect(feeds.added, ['https://site.test/news']);
    expect(dialogOpen(), isFalse);
  });

  dialogTest('a subreddit is added as its feed without discovery', (
    tester,
  ) async {
    await submit(tester, 'https://www.reddit.com/r/FlutterDev/');

    expect(feeds.added, ['https://www.reddit.com/r/flutterdev/.rss']);
    expect(feeds.discovered, isEmpty);
    expect(dialogOpen(), isFalse);
  });

  dialogTest('a page with one feed adds that feed', (tester) async {
    feeds
      ..pages = {'https://site.test/'}
      ..found = const [DiscoveredFeed('https://site.test/rss.xml')];

    await submit(tester, 'https://site.test/');

    expect(feeds.discovered, [_page]);
    expect(feeds.added, ['https://site.test/', 'https://site.test/rss.xml']);
    expect(dialogOpen(), isFalse);
  });

  dialogTest('a page with several feeds lets the user choose', (tester) async {
    feeds
      ..pages = {'https://site.test/'}
      ..found = const [
        DiscoveredFeed('https://site.test/rss.xml', title: 'Posts'),
        DiscoveredFeed('https://site.test/atom.xml', title: 'Comments'),
      ];

    await submit(tester, 'https://site.test/');
    expect(find.text('Choose a feed'), findsOneWidget);
    // Already subscribed: shown, not pickable.
    await tester.tap(find.text('Comments'));
    await settle(tester);
    expect(find.text('Choose a feed'), findsOneWidget);

    await tester.tap(find.text('Posts'));
    await settle(tester);

    expect(feeds.added.last, 'https://site.test/rss.xml');
    expect(dialogOpen(), isFalse);
  });

  dialogTest('cancelling the choice adds nothing and re-enables saving', (
    tester,
  ) async {
    feeds
      ..pages = {'https://site.test/'}
      ..found = const [
        DiscoveredFeed('https://site.test/a.xml'),
        DiscoveredFeed('https://site.test/b.xml'),
      ];

    await submit(tester, 'https://site.test/');
    await tester.tap(find.text('Cancel').last);
    await settle(tester);

    expect(feeds.added, ['https://site.test/']);
    expect(dialogOpen(), isTrue);
    expect(find.text('Save Feed'), findsOneWidget, reason: 'not loading');
  });

  dialogTest('a broken feed keeps its error and starts no discovery', (
    tester,
  ) async {
    feeds.broken = {'https://site.test/feed'};

    await submit(tester, 'https://site.test/feed');

    expect(feeds.discovered, isEmpty);
    expect(feeds.added, ['https://site.test/feed']);
    expect(dialogOpen(), isTrue);
    expect(find.textContaining("Couldn't find a feed"), findsWidgets);
  });

  dialogTest('a page without feeds shows the error', (tester) async {
    feeds.pages = {'https://site.test/'};

    await submit(tester, 'https://site.test/');

    expect(feeds.discovered, hasLength(1));
    expect(feeds.added, ['https://site.test/']);
    expect(dialogOpen(), isTrue);
    expect(find.textContaining("Couldn't find a feed"), findsWidgets);
  });
}
