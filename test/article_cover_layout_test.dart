import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/article_screen.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

import 'support/real_fonts.dart';
import 'support/snapshot.dart';

const _snapDir = String.fromEnvironment('SNAP');

/// The article cover: sized so a landscape phone still shows the title,
/// and gone when its image cannot load.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    await loadRealFonts();
    tempDir = Directory.systemTemp.createTempSync('article_cover_layout');
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

  FeedItem article({String? imageUrl}) => FeedItem(
    id: 'cover',
    siteName: 'Example News',
    title:
        'Hollow-knit sweaters and the quiet comeback of the cardigan '
        'everyone swore they would never wear again',
    description: 'desc',
    link: 'https://cover.test/a',
    feedUrl: 'https://cover.test/feed',
    content: '<p>First paragraph of the article body.</p>',
    imageUrl: imageUrl,
    pubDate: DateTime(2026, 1, 1),
  );

  const imageUrl = 'https://cover.test/i.jpg';

  // 4x4 terracotta PNG.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGM4EWUDRwzEcQBB'
    '0hXhQfaA/wAAAABJRU5ErkJggg==',
  );

  /// A cover prepared on disk, so it shows without the network.
  Future<void> prepareCover(WidgetTester tester, ArticlePageProvider page) =>
      tester.runAsync(() async {
        final dir = tempDir.createTempSync('copy');
        final records = ArticleRecordStore(
          FileObservedArticlePersistence(stateFile: File('${dir.path}/r.json')),
        );
        final media = ArticleMediaStore(root: Directory('${dir.path}/media'));
        final name = ArticleMediaStore.fileNameFor(imageUrl);
        File('${dir.path}/media/$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png);
        final item = page.item;
        await records.write(
          ArticleRecord(
            id: item.id,
            feedUrl: item.feedUrl,
            link: item.link,
            body: item.content,
            bodyState: MediaState.ready,
            bodySource: 'rss',
            owners: const {'tempCache'},
            generation: 1,
            media: {
              imageUrl: MediaEntry(
                file: name,
                byteSize: png.length,
                state: MediaState.ready,
              ),
            },
          ),
        );
        await page.loadSavedCopy(records: records, media: media);
      });

  Future<ArticlePageProvider> pumpArticle(
    WidgetTester tester,
    FeedItem item, {
    bool preparedCover = false,
  }) async {
    final page = ArticlePageProvider(item: item);
    if (preparedCover) await prepareCover(tester, page);
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
              // An active page reloads its saved copy from the app's own
              // stores, which a test cannot reach; the prepared copy
              // loaded above would be dropped.
              isActive: !preparedCover,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return page;
  }

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  double coverHeight(WidgetTester tester) =>
      tester.getSize(find.byType(FlexibleSpaceBar)).height;

  /// Lets image loads (real async I/O) finish or fail.
  Future<void> settleImages(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  /// The cover drawn from the prepared file, not the network.
  final preparedHero = find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is ResizeImage &&
        (w.image as ResizeImage).imageProvider is FileImage,
  );

  Rect titleRect(WidgetTester tester) =>
      tester.getRect(find.text(article().title));

  Future<void> snap(WidgetTester tester, String name) async {
    if (_snapDir.isNotEmpty) await snapshot(tester, '$_snapDir/$name.png');
  }

  // Device test 2026-11-16: on an 800x360 landscape phone the cover took
  // ~75% of the height and pushed the title off-screen.
  for (final size in const [Size(732, 360), Size(915, 412)]) {
    testWidgets('a landscape phone shows the whole title under the cover '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      setSize(tester, size);
      await pumpArticle(
        tester,
        article(imageUrl: imageUrl),
        preparedCover: true,
      );
      await snap(tester, 'cover_${size.width.toInt()}x${size.height.toInt()}');

      expect(preparedHero, findsOneWidget);
      expect(coverHeight(tester), lessThanOrEqualTo(size.height * 0.4));
      expect(titleRect(tester).bottom, lessThanOrEqualTo(size.height));
    });
  }

  for (final size in const [Size(412, 915), Size(360, 640)]) {
    testWidgets('a portrait cover keeps its height '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      setSize(tester, size);
      await pumpArticle(
        tester,
        article(imageUrl: imageUrl),
        preparedCover: true,
      );
      // A cover that loads stays.
      await settleImages(tester);
      await snap(tester, 'cover_${size.width.toInt()}x${size.height.toInt()}');
      expect(preparedHero, findsOneWidget);
      expect(coverHeight(tester), 280);
    });
  }

  // Device test 2026-11-16: an article opened offline with an uncached
  // cover kept a large empty grey block above the title.
  testWidgets('a cover that cannot load collapses to the no-image header', (
    tester,
  ) async {
    setSize(tester, const Size(412, 915));
    // Not prepared: the network load fails (no network in tests).
    await pumpArticle(tester, article(imageUrl: imageUrl));
    await settleImages(tester);
    await snap(tester, 'cover_failed');

    expect(find.byType(FlexibleSpaceBar), findsNothing);
    // Same header as an article without an image.
    final failedTitleTop = titleRect(tester).top;
    await pumpArticle(tester, article());
    expect(titleRect(tester).top, failedTitleTop);
  });
}
