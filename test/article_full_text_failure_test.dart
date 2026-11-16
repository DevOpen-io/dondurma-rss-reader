import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/article_screen.dart';
import 'package:ice_cream_rss_reader/services/full_text_extraction_service.dart';
import 'package:ice_cream_rss_reader/utils/app_toast.dart';

/// A full-text attempt the reader asked for and that failed is reported
/// once, in the article: the inline notice with its retry button. A toast
/// on top of it said the same thing twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('full_text_failure_ui');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a manual failure shows the inline notice and no toast', (
    tester,
  ) async {
    FullTextExtractionService.debugClearSession();
    appToastController.dismiss();
    final item = FeedItem(
      id: 'a1',
      siteName: 'Example News',
      title: 'Title',
      description: 'desc',
      link: 'https://manual-failure.test/a1',
      feedUrl: 'https://manual-failure.test/feed',
      content: '<p>Excerpt</p>',
      pubDate: DateTime(2026, 1, 1),
    );
    final page = ArticlePageProvider(item: item);

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
          ChangeNotifierProvider.value(value: page),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ArticlePage(
              item: item,
              currentIndex: 0,
              totalCount: 1,
              isActive: true,
            ),
          ),
        ),
      ),
    );
    // Lets the page attach its listener and settle its entry transition.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.runAsync(
      () => http.runWithClient(
        page.activateFullText,
        () => MockClient((_) async => http.Response('', 404)),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(page.fullTextFailed, isTrue);
    expect(
      find.text('Could not load full content. Showing feed excerpt.'),
      findsOneWidget,
    );
    expect(find.text('Try Again'), findsOneWidget);
    expect(appToastController.current, isNull);
  });
}
