import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/widgets/home/add_category_dialog.dart';
import 'package:ice_cream_rss_reader/widgets/home/add_destination.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/home_screen.dart';
import 'package:ice_cream_rss_reader/services/shared_links.dart';
import 'package:ice_cream_rss_reader/widgets/add_feed_dialog.dart';
import 'package:ice_cream_rss_reader/widgets/constrained_width.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wide_screen_test');
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

  Widget wrapHome() => MultiProvider(
    providers: [
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
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    ),
  );

  group('ConstrainedWidth', () {
    testWidgets('caps width at 680dp at tablet size', (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConstrainedWidth(
              child: Container(height: 100, color: Colors.red),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final constrainedBox = tester.widget<ConstrainedBox>(
        find
            .descendant(
              of: find.byType(ConstrainedWidth),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(constrainedBox.constraints.maxWidth, 680);
    });

    testWidgets('heightFactor prevents vertical expansion', (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ConstrainedWidth(
                  child: Container(height: 50, color: Colors.green),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(ConstrainedWidth));
      // heightFactor: 1.0 → height = child height = 50 logical px (not expanded).
      expect(size.height, 50);
    });

    testWidgets('does not constrain below 680dp (phone)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConstrainedWidth(
              child: Container(height: 100, color: Colors.blue),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Phone width = 411dp < 680dp → ConstrainedBox maxWidth 680 not enforced.
      final size = tester.getSize(find.byType(ConstrainedWidth));
      // Width should match the phone width (≈411dp), not 680dp.
      expect(size.width, closeTo(1080 / 2.625, 1.0));
    });
  });

  group('HomeScreen wide layout regression', () {
    testWidgets('no overflow at tablet (1280x800dp)', (tester) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at foldable open (841x701dp)', (tester) async {
      tester.view.physicalSize = const Size(2208, 1840);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at phone (411x914dp)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('nav bar sits in bottom quarter of screen at tablet size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      final logicalScreenHeight = 1600 / 2.0; // 800dp

      final feedsFinder = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Feeds'),
      );
      final settingsFinder = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      );

      expect(feedsFinder, findsOneWidget);
      expect(settingsFinder, findsOneWidget);

      final feedsTop = tester.getTopLeft(feedsFinder).dy;
      final settingsBottom = tester.getBottomRight(settingsFinder).dy;

      // The bar should sit in the bottom 25% of the screen.
      expect(feedsTop, greaterThan(logicalScreenHeight * 0.75));
      expect(settingsBottom, closeTo(logicalScreenHeight, 20));
    });

    testWidgets('nav labels fit a phone at 1.4x text scale', (tester) async {
      tester.view.physicalSize = const Size(340, 700);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('the middle of the bottom bar always adds: a folder on the '
        'folder tab, a feed on every other tab', (tester) async {
      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      Finder add(String label) => find.widgetWithText(AddDestination, label);
      expect(add('Add feed'), findsOneWidget);
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('Add new feed'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
        findsNothing,
      );
      await tester.tapAt(Offset.zero); // Dismiss the menu.
      await tester.pumpAndSettle();

      await tester.tap(add('Add feed'));
      await tester.pumpAndSettle();
      expect(find.byType(AddFeedDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(AddFeedDialog))).pop();
      await tester.pumpAndSettle();
      expect(find.text('My Feeds'), findsWidgets, reason: 'still on Feeds');

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(add('Add Category'), findsOneWidget);
      expect(add('Add feed'), findsNothing);
      await tester.tap(add('Add Category'));
      await tester.pumpAndSettle();
      expect(find.byType(AddCategoryDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(AddCategoryDialog))).pop();
      await tester.pumpAndSettle();

      for (final tab in ['Bookmarks', 'Settings']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(add('Add feed'), findsOneWidget, reason: tab);
      }
    });

    group('landscape phone', () {
      /// A landscape phone with its status bar, at [scale] text size.
      void landscape(WidgetTester tester, Size size, {double scale = 1}) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(top: 24);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }

      Finder inRail(Finder f) =>
          find.descendant(of: find.byType(NavigationRail), matching: f);

      for (final size in const [Size(732, 360), Size(915, 412)]) {
        for (final scale in const [1.0, 1.3]) {
          testWidgets(
            '${size.width.toInt()}x${size.height.toInt()} at ${scale}x: '
            'every tab and the add button fit in a side rail',
            (tester) async {
              landscape(tester, size, scale: scale);
              await tester.pumpWidget(wrapHome());
              await tester.pumpAndSettle();

              expect(find.byType(NavigationBar), findsNothing);
              expect(find.byType(NavigationRail), findsOneWidget);
              final appBarBottom = tester
                  .getBottomLeft(find.byType(AppBar))
                  .dy;
              expect(
                size.height - appBarBottom,
                greaterThan(size.height * 0.75),
              );
              for (final target in [
                find.byKey(const ValueKey('add-feed')),
                inRail(find.byIcon(Icons.list)),
                inRail(find.byIcon(Icons.folder_outlined)),
                inRail(find.byIcon(Icons.bookmark_border)),
                inRail(find.byIcon(Icons.settings_outlined)),
              ]) {
                expect(target, findsOneWidget);
                expect(
                  tester.getRect(target).bottom,
                  lessThanOrEqualTo(size.height),
                  reason: '$target is cut off',
                );
              }
              expect(tester.takeException(), isNull);

              // The add action leads the rail and still adds.
              await tester.tap(find.byKey(const ValueKey('add-feed')));
              await tester.pumpAndSettle();
              expect(find.byType(AddFeedDialog), findsOneWidget);
              Navigator.of(tester.element(find.byType(AddFeedDialog))).pop();
              await tester.pumpAndSettle();

              await tester.tap(inRail(find.byIcon(Icons.folder_outlined)));
              await tester.pumpAndSettle();
              expect(find.byKey(const ValueKey('add-folder')), findsOneWidget);
              await tester.tap(inRail(find.byIcon(Icons.settings_outlined)));
              await tester.pumpAndSettle();
              expect(inRail(find.byIcon(Icons.settings)), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }

      testWidgets('640x320: the rail scrolls instead of overflowing', (
        tester,
      ) async {
        landscape(tester, const Size(640, 320), scale: 1.3);
        await tester.pumpWidget(wrapHome());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final settings = inRail(find.byIcon(Icons.settings_outlined));
        await tester.ensureVisible(settings);
        await tester.pumpAndSettle();
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(inRail(find.byIcon(Icons.settings)), findsOneWidget);
        // The empty categories screen fits too.
        final folders = inRail(find.byIcon(Icons.folder_outlined));
        await tester.ensureVisible(folders);
        await tester.pumpAndSettle();
        await tester.tap(folders);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the rail names the add button and counts four tabs', (
        tester,
      ) async {
        landscape(tester, const Size(732, 360));
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(wrapHome());
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp(r'of 5')), findsNothing);
        expect(find.bySemanticsLabel(RegExp(r'Tab 4 of 4')), findsOneWidget);
        // Named once: the tooltip adds no second "Add feed".
        expect(find.bySemanticsLabel('Add feed'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Add feed'))
              .flagsCollection
              .isButton,
          isTrue,
        );
        semantics.dispose();
      });

      testWidgets('portrait phones keep the bottom bar, split screen too', (
        tester,
      ) async {
        for (final size in const [Size(360, 732), Size(360, 380)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(wrapHome());
          await tester.pumpAndSettle();
          expect(find.byType(NavigationBar), findsOneWidget, reason: '$size');
          expect(find.byType(NavigationRail), findsNothing, reason: '$size');
        }
      });
    });

    testWidgets('screen readers count four tabs; the add button is not one', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp(r'of 5')), findsNothing);
      for (final (i, tab) in [
        'Feeds',
        'Categories',
        'Bookmarks',
        'Settings',
      ].indexed) {
        expect(
          find.bySemanticsLabel(RegExp('^$tab\\nTab ${i + 1} of 4\$')),
          findsOneWidget,
          reason: tab,
        );
      }
      final addNode = tester.getSemantics(
        find.byKey(const ValueKey('add-feed')),
      );
      expect(addNode.label, 'Add feed');
      expect(addNode.flagsCollection.isButton, isTrue);
      expect(addNode.flagsCollection.isSelected, isNot(Tristate.isTrue));

      // The selected tab still reads as selected, and moves on tap.
      Finder barText(String text) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(text),
      );
      expect(
        tester.getSemantics(barText('Feeds')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      await tester.tap(barText('Bookmarks'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(barText('Bookmarks')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      semantics.dispose();
    });

    testWidgets('a link shared to the app opens add feed with it', (
      tester,
    ) async {
      SharedLinks.pending.value = 'A headline https://site.test/post';
      addTearDown(() => SharedLinks.pending.value = null);
      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      expect(find.byType(AddFeedDialog), findsOneWidget);
      expect(find.text('https://site.test/post'), findsOneWidget);
      expect(SharedLinks.pending.value, isNull, reason: 'handled once');
    });

    testWidgets('feed tab title fits a 360dp phone', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      // The test font draws every glyph 1em wide, so measure the room the
      // actions leave: "My Feeds" in bold 20sp needs about 95dp.
      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('My Feeds'),
      );
      expect(tester.getSize(title).width, greaterThanOrEqualTo(110));
    });

    testWidgets('feed list body capped at 680dp at tablet size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      // Two ConstrainedWidths in Scaffold: body (680) + bottom nav (480).
      // Find the one with maxWidth: 680 (the body).
      final cwFinders = find.descendant(
        of: find.byType(Scaffold),
        matching: find.byType(ConstrainedWidth),
      );
      expect(cwFinders, findsNWidgets(2));

      final box = find.descendant(
        of: cwFinders.first,
        matching: find.byType(ConstrainedBox),
      );
      final constraints = tester.widget<ConstrainedBox>(box.first).constraints;
      expect(constraints.maxWidth, 680);
    });
  });
}
