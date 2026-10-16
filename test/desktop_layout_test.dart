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
import 'package:ice_cream_rss_reader/screens/desktop/desktop_article_list.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_home_screen.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_reader_pane.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_sidebar.dart';
import 'package:ice_cream_rss_reader/screens/home_screen.dart';
import 'package:ice_cream_rss_reader/screens/settings_screen.dart';
import 'package:ice_cream_rss_reader/utils/platform_caps.dart';
import 'package:ice_cream_rss_reader/widgets/constrained_width.dart';

/// On non-desktop test hosts the adaptive shell must render the mobile
/// [HomeScreen] regardless of size; on Linux/macOS/Windows hosts wide windows
/// get the three-pane desktop layout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('desktop_layout_test');
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

  Widget wrapApp() => MultiProvider(
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
      home: const AdaptiveHomeScreen(),
    ),
  );

  void setSurface(WidgetTester tester, Size logical) {
    tester.view.physicalSize = logical;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  group('AdaptiveHomeScreen', () {
    testWidgets('renders three desktop panes at wide size', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(1600, 900));

      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();

      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(DesktopArticleListPane), findsOneWidget);
      expect(find.byType(DesktopReaderPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows reader empty state when nothing selected', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(1600, 900));

      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();

      expect(find.text('Select an article to read'), findsOneWidget);
    });

    testWidgets('explorer demotes to a drawer below the pin breakpoint', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(1200, 800));

      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();

      // Explorer not pinned inline; list + reader remain.
      expect(find.byType(DesktopSidebar), findsNothing);
      expect(find.byType(DesktopArticleListPane), findsOneWidget);
      expect(find.byType(DesktopReaderPane), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Rail's Feeds button opens the explorer drawer.
      await tester.tap(find.byIcon(Icons.view_sidebar_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to mobile HomeScreen below narrow breakpoint', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(700, 900));

      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(DesktopArticleListPane), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at minimum window size', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(900, 600));

      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives continuous resize across all breakpoints', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      const sizes = [
        Size(1920, 1080),
        Size(1600, 900),
        Size(1440, 900),
        Size(1280, 720),
        Size(1024, 768),
        Size(900, 600),
        Size(700, 900),
        Size(1600, 900),
      ];
      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();
      for (final size in sizes) {
        tester.view.physicalSize = size;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'size=$size');
      }
      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('respects increased text scaling', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(1600, 900));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(
        () => tester.platformDispatcher.clearTextScaleFactorTestValue(),
      );

      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();
      expect(find.byType(DesktopArticleListPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Desktop settings', () {
    testWidgets('settings uses a wide column on desktop', (tester) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(1600, 900));

      await tester.pumpWidget(
        MultiProvider(
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
            localizationsDelegates:
                AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Content column must be wider than the mobile 680 cap on desktop.
      final box = tester.widget<ConstrainedBox>(
        find
            .descendant(
              of: find.byType(ConstrainedWidth),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(box.constraints.maxWidth, greaterThan(680));
    });
  });
}
