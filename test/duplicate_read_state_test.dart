import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';

const _shared = 'https://outlet.test/story';

FeedItem _item(String feed, String category, {String? link, String id = 'x'}) =>
    FeedItem(
      id: id,
      siteName: feed,
      title: 'Title $id',
      description: '',
      category: category,
      feedUrl: 'https://$feed.test/feed',
      link: link ?? 'https://$feed.test/$id',
      pubDate: DateTime.now(),
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
    root = await Directory.systemTemp.createTemp('duplicate-read-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
    await Hive.box('feeds').put(
      'cachedItemsJson',
      jsonEncode([
        _item('a', 'News', link: _shared).toJson(),
        _item('b', 'World', link: _shared).toJson(),
        _item('b', 'World', id: 'w').toJson(),
      ]),
    );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<FeedProvider> load() async {
    final feed = FeedProvider();
    await feed.refreshAll(); // Startup only; no subscriptions, no fetch.
    return feed;
  }

  bool readIn(FeedProvider feed, String feedName) =>
      feed.isRead(_item(feedName, '', link: _shared));

  test('badges count an article carried by two feeds once', () async {
    final feed = await load();
    expect(feed.unreadCount(), 2, reason: 'the shared story and w');
    expect(feed.unreadCount(category: 'News'), 1);
    expect(feed.unreadCount(category: 'World'), 2);
    feed.dispose();
  });

  test('opening the shown copy reads the copy the view hides; unread '
      'brings both back', () async {
    final feed = await load();
    final shown = feed.filteredItems.firstWhere((i) => i.link == _shared);

    await feed.markAsRead(shown);
    expect(readIn(feed, 'a'), isTrue);
    expect(readIn(feed, 'b'), isTrue);
    expect(feed.unreadCount(), 1);
    feed.applySheetFilter(readFilter: 'unread', categories: {});
    expect([for (final i in feed.filteredItems) i.id], ['w']);

    feed.applySheetFilter(readFilter: 'all', categories: {});
    await feed.toggleReadStatus(
      feed.filteredItems.firstWhere((i) => i.link == _shared),
    );
    expect(readIn(feed, 'a'), isFalse);
    expect(readIn(feed, 'b'), isFalse);
    feed.dispose();
  });

  test('read inside one folder, the other folder keeps its copy, and the '
      'list shows that unread copy where the badge counts it', () async {
    final feed = await load();
    feed.selectCategory('News');
    await feed.markAsRead(feed.filteredItems.single);
    expect(readIn(feed, 'a'), isTrue);
    expect(readIn(feed, 'b'), isFalse);
    expect(feed.unreadCount(category: 'World'), 2);

    feed.selectCategory(null);
    final row = feed.filteredItems.firstWhere((i) => i.link == _shared);
    expect(row.isRead, isFalse, reason: 'the unread copy is the one shown');
    expect(row.feedUrl, 'https://b.test/feed');
    expect(feed.unreadCount(), 2);
    feed.dispose();
  });
}
