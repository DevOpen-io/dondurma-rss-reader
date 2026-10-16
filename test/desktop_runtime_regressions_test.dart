import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_article_list.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_reader_pane.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_sidebar.dart';
import 'package:ice_cream_rss_reader/utils/platform_caps.dart';

/// Runtime regressions for the two debug-console failures:
///
/// 1. "The Scrollbar's ScrollController has no ScrollPosition attached" —
///    every desktop Scrollbar now shares an explicit controller with its
///    ScrollView instead of falling back to PrimaryScrollController.
/// 2. "Multiple widgets used the same GlobalKey" — article tiles were keyed
///    by FeedItem.id, but ids are `guid ?? link` and collide legitimately
///    across feeds. Tiles are now index-keyed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('runtime_regressions');
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

  List<SingleChildWidget> providers(FeedItem item) => [
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
    ChangeNotifierProvider(create: (_) => ArticlePageProvider(item: item)),
  ];

  FeedItem makeItem(String id, String title) => FeedItem(
    id: id,
    siteName: 'Example',
    title: title,
    description: 'd',
    timeAgo: '1h',
    siteIcon: Icons.web,
    iconColor: Colors.blue,
    iconBackgroundColor: Colors.grey,
    link: 'https://example.com/$id',
    content: '<p>body</p>',
    pubDate: DateTime(2026),
  );

  Widget app(Widget child) => MultiProvider(
    providers: providers(makeItem('seed', 'Seed')),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  void surface(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  group('GlobalKey collisions', () {
    testWidgets('duplicate item ids no longer duplicate tile keys', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      surface(tester, const Size(1600, 900));

      // Two articles sharing an id — legal per `guid ?? link` identity and
      // the exact trigger for "Multiple widgets used the same GlobalKey".
      final items = [
        for (var i = 0; i < 8; i++) makeItem('dup-id', 'Duplicate $i'),
        makeItem('other', 'Unique'),
      ];

      await tester.pumpWidget(
        app(
          DesktopArticleListPane(
            items: items,
            selectedId: null,
            onSelect: (_) {},
            searchFocusNode: FocusNode(),
            listFocusNode: FocusNode(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Duplicate 0'), findsOneWidget);
      expect(find.text('Unique'), findsOneWidget);
    });
  });

  group('Scrollbar ownership', () {
    testWidgets('sidebar scrollbar tracks its own ListView', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      surface(tester, const Size(1600, 900));

      await tester.pumpWidget(
        app(
          DesktopSidebar(
            section: DesktopSection.articles,
            onSectionChanged: (_) {},
            onAddFeed: () {},
            onAddCategory: () {},
            onOpenDiscover: () {},
            onOpenSettings: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Dragging the nav list must not raise a detached-position error.
      await tester.fling(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.byType(ListView),
        ),
        const Offset(0, -300),
        800,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('article list scrollbar tracks its own ListView', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      surface(tester, const Size(1600, 900));

      final items = [for (var i = 0; i < 40; i++) makeItem('it$i', 'Row $i')];
      await tester.pumpWidget(
        app(
          DesktopArticleListPane(
            items: items,
            selectedId: null,
            onSelect: (_) {},
            searchFocusNode: FocusNode(),
            listFocusNode: FocusNode(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.descendant(
          of: find.byType(DesktopArticleListPane),
          matching: find.byType(ListView),
        ),
        const Offset(0, -400),
        800,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // List actually scrolled — later rows are now visible.
      expect(find.text('Row 30'), findsWidgets);
    });

    testWidgets('reader scrollbar tracks the article scroll view', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      surface(tester, const Size(1600, 900));

      final item = FeedItem(
        id: 'long',
        siteName: 'Example',
        title: 'Long article',
        description: 'd',
        timeAgo: '1h',
        siteIcon: Icons.web,
        iconColor: Colors.blue,
        iconBackgroundColor: Colors.grey,
        link: 'https://example.com/long',
        content: '<p>${'word ' * 800}</p>',
        pubDate: DateTime(2026),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: providers(item),
          child: MaterialApp(
            localizationsDelegates:
                AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: DesktopReaderPane(
                item: item,
                currentIndex: 0,
                totalCount: 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -400),
        800,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
