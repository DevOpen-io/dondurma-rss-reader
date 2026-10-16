import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_reader_pane.dart';
import 'package:ice_cream_rss_reader/utils/platform_caps.dart';

/// Regression test for the desktop reader collapse bug: article content used
/// `MediaQuery.size.width` (the whole window) to compute padding, so inside a
/// ~960px reader pane at 1600px window the content was squeezed to ~40px.
/// The reader must size content from the actual pane constraints.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('reader_width_test');
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

  FeedItem makeItem() => FeedItem(
    id: 'a1',
    siteName: 'Example News',
    title: 'A reasonably long article title that should wrap by words',
    description: 'desc',
    timeAgo: '1h',
    siteIcon: Icons.web,
    iconColor: Colors.blue,
    iconBackgroundColor: Colors.blueGrey,
    link: 'https://example.com/a1',
    content:
        '<p>${'This is a long paragraph of article body text. ' * 30}</p>',
    pubDate: DateTime(2026, 1, 1),
  );

  Widget wrap(FeedItem item) => MultiProvider(
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
      ChangeNotifierProvider(
        create: (_) => ArticlePageProvider(item: item),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Row(
          children: [
            const SizedBox(width: 620), // sidebar + list
            Expanded(
              child: DesktopReaderPane(
                item: item,
                currentIndex: 0,
                totalCount: 5,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('reader content fills pane, not a sliver of the window', (
    tester,
  ) async {
    if (!PlatformCaps.isDesktop) return;
    // 1600px window → reader pane is 1600-620 = 980px wide.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(makeItem()));
    // Let the delayed setContentReady timer fire so Html body renders.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final htmlFinder = find.byType(Html);
    expect(htmlFinder, findsOneWidget);
    final width = tester.getSize(htmlFinder).width;
    // Pane is ~980px; content must be a comfortable column (~680-720),
    // never the ~60px strip the MediaQuery padding bug produced.
    expect(width, greaterThan(500));
    expect(width, lessThanOrEqualTo(980));
  });

  testWidgets('reader shrinks gracefully in a narrow pane', (tester) async {
    if (!PlatformCaps.isDesktop) return;
    // 900px window → reader pane is 900-620 = 280px wide.
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(makeItem()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final htmlFinder = find.byType(Html);
    expect(htmlFinder, findsOneWidget);
    final width = tester.getSize(htmlFinder).width;
    expect(width, greaterThan(150));
    expect(width, lessThanOrEqualTo(280));
    expect(tester.takeException(), isNull);
  });
}
