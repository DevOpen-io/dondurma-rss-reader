import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/app_backup.dart';

FeedItem _item(String id) => FeedItem(
  id: id,
  siteName: 'A',
  title: 'Title $id',
  description: '',
  feedUrl: 'https://a.test/feed',
  link: 'https://a.test/$id',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    root = await Directory.systemTemp.createTemp('tags-saved-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('tags filter bookmarks, persist, and leave with the bookmark', () async {
    final bookmarks = BookmarkProvider();
    bookmarks
      ..toggleBookmark(_item('a'))
      ..toggleBookmark(_item('b'));
    await bookmarks.setTags(_item('a'), [' work ', 'later', 'work', '']);
    await bookmarks.setTags(_item('b'), ['later']);
    expect(bookmarks.tagsOf(_item('a')), ['work', 'later']);
    expect(bookmarks.allTags, ['later', 'work']);

    bookmarks.selectTag('work');
    expect([for (final b in bookmarks.visibleBookmarks) b.id], ['a']);

    final reopened = BookmarkProvider();
    expect(reopened.tagsOf(_item('b')), ['later']);

    bookmarks.toggleBookmark(_item('a')); // Removed: its tags go too.
    expect(bookmarks.allTags, ['later']);
    expect(bookmarks.tagFilter, isNull, reason: 'the filtered tag is gone');
    await bookmarks.persistBookmarks(); // The toggle saves in the background.
    bookmarks.dispose();
    reopened.dispose();
  });

  test('saved searches keep a name, rename by query, and go away', () async {
    final settings = SettingsProvider();
    await settings.saveSearch('Flutter news', 'flutter');
    await settings.saveSearch('', 'dart');
    expect(settings.savedSearches, [
      (name: 'Flutter news', query: 'flutter'),
      (name: 'dart', query: 'dart'),
    ]);
    await settings.saveSearch('Dart', 'dart');
    expect(SettingsProvider().savedSearches.last, (
      name: 'Dart',
      query: 'dart',
    ));
    await settings.removeSavedSearch('flutter');
    expect(SettingsProvider().savedSearches, [(name: 'Dart', query: 'dart')]);
  });

  test('a backup carries tags and saved searches', () async {
    final feed = FeedProvider();
    await feed.refreshAll();
    final settings = SettingsProvider();
    final subs = SubscriptionProvider();
    final bookmarks = BookmarkProvider()..toggleBookmark(_item('a'));
    await bookmarks.setTags(_item('a'), ['work']);
    await settings.saveSearch('F', 'flutter');
    await bookmarks.persistBookmarks();
    final json = exportAppBackup(
      settings: settings,
      subscriptions: subs,
      bookmarks: bookmarks,
      feed: feed,
    );
    feed.dispose();
    bookmarks.dispose();
    await feed.idle;
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.box(name).clear();
    }

    final feed2 = FeedProvider();
    await feed2.refreshAll();
    final settings2 = SettingsProvider();
    final bookmarks2 = BookmarkProvider();
    await restoreAppBackup(
      json,
      settings: settings2,
      subscriptions: SubscriptionProvider(),
      bookmarks: bookmarks2,
      feed: feed2,
    );
    expect(bookmarks2.tagsOf(_item('a')), ['work']);
    expect(settings2.savedSearches, [(name: 'F', query: 'flutter')]);
    await bookmarks2.persistBookmarks();
    feed2.dispose();
    bookmarks2.dispose();
  });
}
