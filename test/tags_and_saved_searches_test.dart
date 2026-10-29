import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/saved_search.dart';
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

  test('saved searches keep a name; the same search again renames it; a '
      'different filter is a different search', () async {
    final settings = SettingsProvider();
    const flutter = SavedSearch(name: 'Flutter news', query: 'flutter');
    const unread = SavedSearch(
      name: 'Unread flutter',
      query: 'flutter',
      category: 'Tech',
      readFilter: 'unread',
    );
    await settings.saveSearch(flutter);
    await settings.saveSearch(unread);
    expect(settings.savedSearches, [flutter, unread]);
    await settings.saveSearch(unread.rename('Tech, unread'));
    expect(SettingsProvider().savedSearches.last.name, 'Tech, unread');
    await settings.removeSavedSearch(flutter);
    expect(SettingsProvider().savedSearches, [unread.rename('Tech, unread')]);
  });

  test('a saved search brings back its scope and filters', () async {
    final feed = FeedProvider();
    await feed.refreshAll();
    feed
      ..selectCategory('Tech')
      ..applySheetFilter(readFilter: 'unread', categories: {})
      ..setSearchQuery(' flutter ');
    final saved = feed.currentSearch('F');
    expect(saved.query, 'flutter');
    expect(saved.readFilter, 'unread');

    feed
      ..applySheetFilter(readFilter: 'all', categories: {})
      ..selectCategory('Sport')
      ..setSearchQuery('');
    feed.applySavedSearch(saved);
    expect(feed.searchQuery, 'flutter');
    expect(feed.readFilter, 'unread');
    feed.dispose();
  });

  test('a removed bookmark takes its tags and the filter on them', () async {
    final bookmarks = BookmarkProvider()..toggleBookmark(_item('a'));
    await bookmarks.setTags(_item('a'), ['work']);
    bookmarks.selectTag('work');
    var notified = 0;
    bookmarks.addListener(() => notified++);

    await bookmarks.removeBookmark(_item('a'));

    expect(bookmarks.allTags, isEmpty);
    expect(bookmarks.tagFilter, isNull);
    expect(notified, greaterThan(1), reason: 'the stale chip is redrawn');
    // A legacy or missing bookmark takes no tags.
    await bookmarks.setTags(_item('ghost'), ['x']);
    expect(bookmarks.allTags, isEmpty);
    bookmarks.dispose();
  });

  test('a backup carries tags and saved searches', () async {
    final feed = FeedProvider();
    await feed.refreshAll();
    final settings = SettingsProvider();
    final subs = SubscriptionProvider();
    final bookmarks = BookmarkProvider()..toggleBookmark(_item('a'));
    await bookmarks.setTags(_item('a'), ['work']);
    await settings.saveSearch(const SavedSearch(name: 'F', query: 'flutter'));
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
    expect(settings2.savedSearches, [
      const SavedSearch(name: 'F', query: 'flutter'),
    ]);
    await bookmarks2.persistBookmarks();
    feed2.dispose();
    bookmarks2.dispose();
  });
}
