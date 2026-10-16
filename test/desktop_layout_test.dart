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
import 'package:ice_cream_rss_reader/utils/platform_caps.dart';

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

    testWidgets('collapses sidebar to icon rail at medium width', (
      tester,
    ) async {
      if (!PlatformCaps.isDesktop) return;
      setSurface(tester, const Size(1000, 800));

      await tester.pumpWidget(wrapApp());
      await tester.pumpAndSettle();

      // Full sidebar gone; panes 2 and 3 remain.
      expect(find.byType(DesktopSidebar), findsNothing);
      expect(find.byType(DesktopArticleListPane), findsOneWidget);
      expect(find.byType(DesktopReaderPane), findsOneWidget);
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
  });
}
