import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/widgets/bookmark_tags.dart';
import 'package:ice_cream_rss_reader/widgets/saved_searches.dart';

FeedItem _item(String id) => FeedItem(
  id: id,
  siteName: 'A',
  title: 'Title $id',
  description: '',
  feedUrl: 'https://a.test/feed',
  link: 'https://a.test/$id',
);

void main() {
  late Directory root;
  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('bookmark-tags-sheet');
    Hive.init(root.path);
    for (final name in ['bookmarks', 'feeds', 'settings']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget app(Widget home, {required List<ChangeNotifierProvider> providers}) =>
      MultiProvider(
        providers: providers,
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: home,
        ),
      );

  for (final (tags, keyboard) in [(12, 0.0), (2, 260.0)]) {
    testWidgets('the tag sheet fits a 320dp phone at 1.3x in Turkish '
        '($tags tags, keyboard $keyboard)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      final bookmarks = BookmarkProvider()..toggleBookmark(_item('a'));
      for (var i = 0; i < tags; i++) {
        bookmarks.toggleBookmark(_item('t$i'));
        // Not awaited: the in-memory state updates at once.
        bookmarks.setTags(_item('t$i'), ['araştırma-etiketi-$i']);
      }
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => BookmarkTagsSheet.show(context, _item('a')),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          providers: [
            ChangeNotifierProvider<BookmarkProvider>.value(value: bookmarks),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(BookmarkTagsSheet), findsOneWidget);
    });
  }

  testWidgets('saving a search names it without a disposed controller', (
    tester,
  ) async {
    final settings = SettingsProvider();
    late FeedProvider feed;
    await tester.runAsync(() async {
      feed = FeedProvider();
    });
    feed.setSearchQuery('flutter');
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => saveCurrentSearch(context),
              child: const Text('save'),
            ),
          ),
        ),
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<FeedProvider>.value(value: feed),
        ],
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Flutter haberleri');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(settings.savedSearches.single.name, 'Flutter haberleri');
    expect(settings.savedSearches.single.query, 'flutter');
    await tester.runAsync(() async => feed.dispose());
  });
}
