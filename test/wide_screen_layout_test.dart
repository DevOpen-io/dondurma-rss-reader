import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/home_screen.dart';
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

    testWidgets('nav pill sits in bottom quarter of screen at tablet size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2560, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(wrapHome());
      await tester.pumpAndSettle();

      final logicalScreenHeight = 1600 / 2.0; // 800dp

      final feedsFinder = find.bySemanticsLabel('Feeds');
      final settingsFinder = find.bySemanticsLabel('Settings');

      expect(feedsFinder, findsOneWidget);
      expect(settingsFinder, findsOneWidget);

      final feedsTop = tester.getTopLeft(feedsFinder).dy;
      final settingsBottom = tester.getBottomRight(settingsFinder).dy;

      // Pill should sit in the bottom 25% of the screen.
      expect(feedsTop, greaterThan(logicalScreenHeight * 0.75));
      expect(settingsBottom, closeTo(logicalScreenHeight, 20));
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
