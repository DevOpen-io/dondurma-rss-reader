import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/models/refresh_progress.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_home_screen.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_sidebar.dart';
import 'package:ice_cream_rss_reader/screens/home_screen.dart';
import 'package:ice_cream_rss_reader/utils/platform_caps.dart';
import 'package:ice_cream_rss_reader/widgets/feed_list_item.dart';

/// Navigation hierarchy regressions:
/// - a selected feed's parent category gets the ancestor-active indicator
///   (slim left accent, no primary selection fill) while the feed itself
///   keeps the primary selected look;
/// - the ancestor state follows feed moves/renames and updates on switching;
/// - "All Articles" clears both scopes;
/// - a collapsed ancestor auto-expands to reveal its selected feed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('nav_selection');
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<SingleChildWidget> providers() => [
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
    ChangeNotifierProvider(create: (_) => BookmarkProvider()),
    ChangeNotifierProxyProvider3<
      SubscriptionProvider,
      SettingsProvider,
      BookmarkProvider,
      FeedProvider
    >(
      create: (_) => FeedProvider(),
      update: (_, sub, settings, bm, feed) =>
          (feed ?? FeedProvider())..update(sub, settings, bm),
    ),
  ];

  Widget sidebarApp() => MultiProvider(
    providers: providers(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: DesktopSidebar(
            section: DesktopSection.articles,
            onSectionChanged: (_) {},
            onAddFeed: () {},
            onAddCategory: () {},
          ),
        ),
      ),
    ),
  );

  Future<void> seed(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(sidebarApp());
    final ctx = tester.element(find.byType(DesktopSidebar));
    final subs = ctx.read<SubscriptionProvider>();
    await subs.addFeedsBatch([
      (url: 'https://a.example/feed', name: 'Feed A1', category: 'Tech'),
      (url: 'https://a2.example/feed', name: 'Feed A2', category: 'Tech'),
      (url: 'https://b.example/feed', name: 'Feed B1', category: 'Science'),
    ]);
    await tester.pumpAndSettle();
  }

  FeedProvider feedOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopSidebar)).read<FeedProvider>();

  /// The ancestor accent is the 3px primary bar positioned at the node's
  /// left edge — count them to verify exactly one ancestor is marked.
  int ancestorBars(WidgetTester tester) => tester
      .widgetList<Positioned>(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.byType(Positioned),
        ),
      )
      .where((p) => p.left == 0 && p.top == 10 && p.bottom == 10)
      .length;

  testWidgets('feed selection marks its parent as ancestor, not selected', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    await seed(tester);

    feedOf(tester).selectFeed('https://a.example/feed');
    await tester.pumpAndSettle();

    expect(feedOf(tester).selectedFeedParentCategory, 'Tech');
    expect(ancestorBars(tester), 1);
    // Selected feed is visible: the collapsed parent auto-expanded.
    expect(find.text('Feed A1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching feed to another category moves the indicator', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    await seed(tester);

    feedOf(tester).selectFeed('https://a.example/feed');
    await tester.pumpAndSettle();
    expect(ancestorBars(tester), 1);

    feedOf(tester).selectFeed('https://b.example/feed');
    await tester.pumpAndSettle();

    expect(feedOf(tester).selectedFeedParentCategory, 'Science');
    expect(ancestorBars(tester), 1);
    expect(find.text('Feed B1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct category selection uses primary state, no ancestor', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    await seed(tester);

    feedOf(tester).selectCategory('Tech');
    await tester.pumpAndSettle();

    expect(feedOf(tester).selectedFeedParentCategory, isNull);
    expect(ancestorBars(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('All Articles clears feed and category scope', (tester) async {
    if (!PlatformCaps.isDesktop) return;
    await seed(tester);

    feedOf(tester).selectFeed('https://a.example/feed');
    await tester.pumpAndSettle();
    expect(ancestorBars(tester), 1);

    // The rail's All Articles entry calls selectCategory(null).
    feedOf(tester).selectCategory(null);
    await tester.pumpAndSettle();

    expect(feedOf(tester).selectedCategory, isNull);
    expect(feedOf(tester).selectedFeedUrl, isNull);
    expect(feedOf(tester).selectedFeedParentCategory, isNull);
    expect(ancestorBars(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving the selected feed reparents the ancestor', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    await seed(tester);
    final ctx = tester.element(find.byType(DesktopSidebar));

    feedOf(tester).selectFeed('https://a.example/feed');
    await tester.pumpAndSettle();
    expect(feedOf(tester).selectedFeedParentCategory, 'Tech');

    await ctx.read<SubscriptionProvider>().moveFeedToCategory(
      'https://a.example/feed',
      'Science',
    );
    await tester.pumpAndSettle();

    expect(feedOf(tester).selectedFeedParentCategory, 'Science');
    expect(tester.takeException(), isNull);
  });

  testWidgets('All Articles tile is pinned above the scrollable tree', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    await seed(tester);

    // Not a descendant of the scrollable ListView — it lives in the fixed
    // section header column, so it can't scroll away.
    expect(find.text('All Articles'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('All Articles'),
      ),
      findsNothing,
    );

    // Deep-scroll the tree; the tile must stay put and visible.
    await tester.fling(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.byType(ListView),
      ),
      const Offset(0, -400),
      800,
    );
    await tester.pumpAndSettle();
    expect(find.text('All Articles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('All Articles tap clears scope and shows selected state', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    await seed(tester);

    feedOf(tester).selectFeed('https://a.example/feed');
    await tester.pumpAndSettle();

    await tester.tap(find.text('All Articles'));
    await tester.pumpAndSettle();

    expect(feedOf(tester).selectedCategory, isNull);
    expect(feedOf(tester).selectedFeedUrl, isNull);
    expect(ancestorBars(tester), 0);

    final tile = tester.widget<Semantics>(
      find.ancestor(
        of: find.text('All Articles'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
      ),
    );
    expect(tile.properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status-only notifications do not rebuild the mobile list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    // The refresh on first update keeps cached items of subscribed feeds
    // only; Hive's in-memory view updates synchronously.
    final box = Hive.box('feeds');
    box.put(
      'subscriptions',
      jsonEncode([
        FeedSubscription(
          url: 'https://x/feed',
          name: 'Feed',
          category: 'News',
        ).toJson(),
      ]),
    );
    box.put(
      'cachedItemsJson',
      jsonEncode([
        FeedItem(
          id: 'row-1',
          siteName: 'Feed',
          title: 'Stable row',
          description: 'body',
          link: 'https://x/row-1',
          feedUrl: 'https://x/feed',
          pubDate: DateTime.now().toUtc(),
        ).toJson(),
      ]),
    );
    addTearDown(() {
      // Not awaited: file I/O cannot complete inside the fake-async zone.
      box.deleteAll(['cachedItemsJson', 'subscriptions']);
    });

    // The cache decodes via compute(), which completes only when the
    // provider is created outside the fake-async zone.
    await tester.runAsync(
      () => tester.pumpWidget(
        MultiProvider(
          providers: providers(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 100 && find.byType(FeedListItem).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    final row = find.byType(FeedListItem);
    expect(row, findsOneWidget);
    final before = tester.widget(row);

    // Sync stamps and offline-status reloads notify without touching any
    // list input; the rows must not be rebuilt from scratch for them.
    // ignore: invalid_use_of_protected_member
    tester.element(row).read<FeedProvider>().notifyListeners();
    await tester.pump();

    expect(identical(tester.widget(row), before), isTrue);
  });

  testWidgets('mobile home exposes a single global refresh indicator', (
    tester,
  ) async {
    // Phone-sized surface; platform gate irrelevant — this is the shared
    // mobile shell.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: providers(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pull-to-refresh gesture stays, but the indicator widget itself is
    // transparent — the pill is the only visible global spinner.
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    expect(indicator.color, Colors.transparent);
    expect(indicator.backgroundColor, Colors.transparent);

    final ctx = tester.element(find.byType(HomeScreen));
    ctx.read<FeedProvider>().refreshProgress.value = RefreshProgress(
      phase: RefreshPhase.refreshing,
      total: 10,
      completed: 3,
    );
    await tester.pump();

    expect(find.text('3 / 10'), findsOneWidget);
    // Exactly one spinner: the pill's — no competing refresh circles.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Escape navigation', () {
    Widget homeApp() => MultiProvider(
      providers: providers(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AdaptiveHomeScreen(),
      ),
    );

    Future<void> pumpDesktop(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(homeApp());
      await tester.pumpAndSettle();
    }

    testWidgets('dashboard Escape is a no-op (no pop, no exception)', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      await pumpDesktop(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(DesktopHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Escape pops the pushed Settings route', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      await pumpDesktop(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(DesktopHomeScreen),
          matching: find.byTooltip('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(DesktopHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Focus Read Mode toggles and Escape exits it', (tester) async {
      if (!PlatformCaps.isDesktop) return;

      Hive.box('feeds').put(
        'cachedItemsJson',
        jsonEncode([
          FeedItem(
            id: 'a1',
            siteName: 'Feed',
            title: 'Article One',
            description: 'body',
            link: 'https://x/a1',
            feedUrl: 'https://x/feed',
            pubDate: DateTime.utc(2026, 10, 17),
          ).toJson(),
        ]),
      );
      await pumpDesktop(tester);

      await tester.tap(find.text('Article One').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Focus Read Mode'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Exit Focus Mode'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Focus Read Mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('consecutive Escape presses stay safe', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      await pumpDesktop(tester);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }

      expect(find.byType(DesktopHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a category literally named All News stays a normal node', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(sidebarApp());
    final ctx = tester.element(find.byType(DesktopSidebar));
    await ctx.read<SubscriptionProvider>().addFeedsBatch([
      (url: 'https://n.example/feed', name: 'News Feed', category: 'All News'),
    ]);
    await tester.pumpAndSettle();

    // Selecting the user category must not resolve to the global scope.
    ctx.read<FeedProvider>().selectCategory('All News');
    await tester.pumpAndSettle();
    expect(ctx.read<FeedProvider>().selectedCategory, 'All News');
    expect(tester.takeException(), isNull);
  });
}
