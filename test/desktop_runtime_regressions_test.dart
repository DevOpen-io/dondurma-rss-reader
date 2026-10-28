import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
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
///    across feeds. Tiles use source/GUID/occurrence keys scoped to the pane.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('runtime_regressions');
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

  void desktopTest(String description, WidgetTesterCallback callback) {
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

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

  Widget listPane(
    List<FeedItem> items, {
    String? selectedId,
    ValueChanged<FeedItem>? onSelect,
    VoidCallback? onAddFeed,
  }) => app(
    DesktopArticleListPane(
      items: items,
      selectedId: selectedId,
      onSelect: onSelect ?? (_) {},
      onAddFeed: onAddFeed ?? () {},
      searchFocusNode: FocusNode(),
      listFocusNode: FocusNode(),
    ),
  );

  desktopTest('keyboard navigation distinguishes sources sharing a GUID', (
    tester,
  ) async {
    surface(tester, const Size(1000, 800));
    final searchFocus = FocusNode();
    final listFocus = FocusNode();
    addTearDown(searchFocus.dispose);
    addTearDown(listFocus.dispose);
    final items = [
      makeItem('shared', 'Source A').copyWith(feedUrl: 'a'),
      makeItem('shared', 'Source B').copyWith(feedUrl: 'b'),
      makeItem('last', 'Last').copyWith(feedUrl: 'b'),
    ];
    FeedItem selected = items[1];
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, update) {
            return DesktopArticleListPane(
              items: items,
              selectedId: selected.id,
              selectedFeedUrl: selected.feedUrl,
              onSelect: (item) => update(() => selected = item),
              onAddFeed: () {},
              searchFocusNode: searchFocus,
              listFocusNode: listFocus,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    listFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(selected.title, 'Last');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(selected.title, 'Source B');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('GlobalKey collisions', () {
    desktopTest('duplicate item ids no longer duplicate tile keys', (
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

      await tester.pumpWidget(listPane(items));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Duplicate 0'), findsOneWidget);
      expect(find.text('Unique'), findsOneWidget);
    });

    desktopTest('large list survives rapid rebuilds and selection', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      surface(tester, const Size(1600, 900));

      var items = [for (var i = 0; i < 150; i++) makeItem('a$i', 'Article $i')];
      var selected = 0;
      await tester.pumpWidget(
        listPane(items, selectedId: items[selected].id, onSelect: (_) {}),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Repeated rebuilds: prepend items (reorders every index), then
      // re-select — this used to re-reserve tile keys across wrappers.
      for (var round = 0; round < 5; round++) {
        items = [makeItem('new$round', 'Prepended $round'), ...items];
        selected = round;
        await tester.pumpWidget(
          listPane(items, selectedId: items[selected].id),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'round=$round');
      }

      // Rapid scroll through the rebuilt list.
      await tester.fling(
        find.descendant(
          of: find.byType(DesktopArticleListPane),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -2000),
        1500,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    desktopTest('incoming source articles preserve the visible desktop row', (
      tester,
    ) async {
      surface(tester, const Size(400, 800));
      var items = [
        for (var i = 0; i < 80; i++) makeItem('anchor$i', 'Anchor article $i'),
      ];
      await tester.pumpWidget(listPane(items));
      await tester.pumpAndSettle();
      final viewport = find.byType(CustomScrollView);
      await tester.drag(viewport, const Offset(0, -900));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(viewport);
      final visible = items.where((item) {
        final text = find.text(item.title);
        return text.evaluate().isNotEmpty &&
            tester.getRect(text).overlaps(bounds);
      }).toList();
      final anchor = visible.first;
      final before = tester.getTopLeft(find.text(anchor.title)).dy;
      items = [makeItem('incoming', 'Just fetched'), ...items];
      await tester.pumpWidget(listPane(items, selectedId: anchor.id));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text(anchor.title)).dy,
        closeTo(before, 0.1),
      );
    });

    desktopTest(
      'rapid scrolling during refresh keeps the desktop widget tree valid',
      (tester) async {
        surface(tester, const Size(380, 800));
        var items = [
          for (var i = 0; i < 300; i++) makeItem('race$i', 'Race article $i'),
        ];
        late StateSetter update;
        final searchFocus = FocusNode();
        final listFocus = FocusNode();
        addTearDown(searchFocus.dispose);
        addTearDown(listFocus.dispose);
        await tester.pumpWidget(
          app(
            StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return DesktopArticleListPane(
                  items: items,
                  selectedId: null,
                  onSelect: (_) {},
                  onAddFeed: () {},
                  searchFocusNode: searchFocus,
                  listFocusNode: listFocus,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(180, 300));
        addTearDown(mouse.removePointer);
        final random = Random(42);
        // Hover/splash highlights retain offscreen InkWell rows. Before the
        // fix, batch 26 poisoned the offset and batch 31 hit the user's exact
        // framework assertion: _elements.contains(element).
        for (var round = 0; round < 40; round++) {
          if (find.byType(CustomScrollView).evaluate().isNotEmpty) {
            if (round % 10 == 0) {
              await tester.fling(
                find.byType(CustomScrollView),
                const Offset(0, -1200),
                5000,
              );
            }
            final scrollable = find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            );
            final position = tester.state<ScrollableState>(scrollable).position;
            position.jumpTo(
              (position.pixels + (round % 10 < 5 ? 1500 : -1500)).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
          }
          update(() {
            items = [makeItem('new-race$round', 'New race $round'), ...items];
            if (round % 4 == 0) items = [...items.skip(20), ...items.take(20)];
            if (round % 5 == 0) {
              final pool = List.generate(300, (i) => i)..shuffle(random);
              items = [
                for (final i in pool.take(50 + random.nextInt(200)))
                  makeItem('race$i', 'Race article $i ${'text ' * (i % 15)}'),
              ];
            }
          });
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.takeException(),
            isNull,
            reason: 'refresh batch $round',
          );
          expect(find.byType(CustomScrollView), findsOneWidget);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    desktopTest('same key never appears twice while resizing', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      surface(tester, const Size(1600, 900));

      final items = [for (var i = 0; i < 60; i++) makeItem('s$i', 'Sized $i')];
      await tester.pumpWidget(listPane(items));
      await tester.pumpAndSettle();

      for (final s in const [
        Size(1024, 768),
        Size(1920, 1080),
        Size(900, 600),
        Size(1600, 900),
      ]) {
        tester.view.physicalSize = s;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'size=$s');
      }
    });
  });

  group('Scrollbar ownership', () {
    desktopTest('sidebar scrollbar tracks its own ListView', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      surface(tester, const Size(1600, 900));

      await tester.pumpWidget(
        app(
          DesktopSidebar(
            section: DesktopSection.articles,
            onSectionChanged: (_) {},
            onAddFeed: () {},
            onAddCategory: () {},
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

    desktopTest('article list scrollbar tracks its own viewport', (
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
            onAddFeed: () {},
            searchFocusNode: FocusNode(),
            listFocusNode: FocusNode(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.descendant(
          of: find.byType(DesktopArticleListPane),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -400),
        800,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );
      await tester.scrollUntilVisible(
        find.text('Row 30'),
        400,
        scrollable: scrollable,
      );
      expect(find.text('Row 30'), findsOneWidget);
    });

    desktopTest('reader scrollbar tracks the article scroll view', (
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
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

  desktopTest('clear filters also empties the search field', (tester) async {
    surface(tester, const Size(1000, 800));
    const feedUrl = 'https://example.com/feed';
    // Earlier tests leave Hive file writes queued in their fake-async
    // zones, so awaiting one here never returns. The box's in-memory view
    // updates synchronously, which is all the provider reads. The refresh
    // on first update keeps cached items of subscribed feeds only.
    final box = Hive.box('feeds');
    unawaited(
      box.put(
        'subscriptions',
        jsonEncode([
          FeedSubscription(
            url: feedUrl,
            name: 'Example',
            category: 'News',
          ).toJson(),
        ]),
      ),
    );
    unawaited(
      box.put(
        'cachedItemsJson',
        jsonEncode([
          makeItem('a1', 'Article One').copyWith(feedUrl: feedUrl).toJson(),
        ]),
      ),
    );
    addTearDown(
      () => unawaited(box.deleteAll(['cachedItemsJson', 'subscriptions'])),
    );
    // The cache decodes via compute(), which only completes when the
    // provider is created outside the fake-async zone.
    await tester.runAsync(() => tester.pumpWidget(listPane(const [])));
    final pane = tester.element(find.byType(DesktopArticleListPane));
    final l10n = AppLocalizations.of(pane);
    final feed = pane.read<FeedProvider>();
    for (var i = 0; i < 100 && feed.items.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(feed.items, isNotEmpty);

    await tester.enterText(find.byType(TextField), 'no-such-article');
    await tester.pump();
    await tester.tap(find.text(l10n.clearFilters));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  desktopTest('empty pane without any articles offers to add a feed', (
    tester,
  ) async {
    surface(tester, const Size(1000, 800));
    var addTaps = 0;
    await tester.pumpWidget(listPane(const [], onAddFeed: () => addTaps++));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(DesktopArticleListPane)),
    );

    expect(find.text(l10n.noFeedsFound), findsOneWidget);
    await tester.tap(find.text(l10n.semanticAddFeed));
    expect(addTaps, 1);
  });
}
