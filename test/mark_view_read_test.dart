import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';

FeedItem _item(
  String id, {
  String category = 'News',
  String feed = 'a',
  DateTime? pubDate,
  bool undated = false,
  String? link,
}) => FeedItem(
  id: id,
  siteName: feed,
  title: 'Title $id',
  description: '',
  category: category,
  feedUrl: 'https://$feed.test/feed',
  link: link ?? 'https://$feed.test/$id',
  pubDate: undated ? null : pubDate ?? DateTime.now(),
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
    root = await Directory.systemTemp.createTemp('mark-view-read-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<FeedProvider> load(List<FeedItem> items) async {
    await Hive.box(
      'feeds',
    ).put('cachedItemsJson', jsonEncode([for (final i in items) i.toJson()]));
    final feed = FeedProvider();
    await feed.refreshAll(); // Waits for startup; no subscriptions, no fetch.
    return feed;
  }

  Set<String> unreadIds(FeedProvider feed) => {
    for (final i in feed.items)
      if (!feed.isRead(i)) i.id,
  };

  test('marks only the articles in the current folder view', () async {
    final feed = await load([
      _item('n1'),
      _item('n2'),
      _item('s1', category: 'Sport', feed: 'b'),
    ]);
    feed.selectCategory('News');
    expect(feed.unreadInView().length, 2);

    expect(await feed.markItemsAsRead(feed.unreadInView()), 2);

    expect(unreadIds(feed), {'s1'});
    expect(feed.unreadCount(), 1);
    expect(feed.unreadInView().length, 0);
    feed.dispose();
  });

  test('the search query narrows what is marked', () async {
    final feed = await load([_item('alpha'), _item('beta')]);
    feed.setSearchQuery('alpha');

    expect(await feed.markItemsAsRead(feed.unreadInView()), 1);

    expect(unreadIds(feed), {'beta'});
    feed.dispose();
  });

  test('olderThan keeps newer articles unread; undated count as old', () async {
    final now = DateTime.now();
    final feed = await load([
      _item('fresh', pubDate: now.subtract(const Duration(hours: 2))),
      _item('old', pubDate: now.subtract(const Duration(days: 3))),
      _item('ancient', pubDate: now.subtract(const Duration(days: 30))),
      _item('undated', undated: true),
    ]);
    const week = Duration(days: 7);
    const day = Duration(days: 1);
    expect(feed.unreadInView(olderThan: week).length, 2);
    expect(feed.unreadInView(olderThan: day).length, 3);

    expect(await feed.markItemsAsRead(feed.unreadInView(olderThan: day)), 3);

    expect(unreadIds(feed), {'fresh'});
    feed.dispose();
  });

  test('already read articles are not counted or re-marked', () async {
    final feed = await load([_item('a1'), _item('a2')]);
    await feed.markAsRead(feed.items.firstWhere((i) => i.id == 'a1'));
    expect(feed.unreadInView().length, 1);

    var notified = 0;
    feed.addListener(() => notified++);
    expect(await feed.markItemsAsRead(feed.unreadInView()), 1);
    expect(notified, 1);
    expect(await feed.markItemsAsRead(feed.unreadInView()), 0);
    expect(notified, 1, reason: 'nothing changed, no rebuild');
    feed.dispose();
  });

  test('marked articles stay read after a restart', () async {
    final items = [_item('r1'), _item('r2')];
    final first = await load(items);
    await first.markItemsAsRead(first.unreadInView());
    first.dispose();
    await first.idle;
    await Hive.close();
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }

    final restarted = FeedProvider();
    await restarted.refreshAll();
    expect(unreadIds(restarted), isEmpty);
    restarted.dispose();
  });

  test(
    'copies of a link hidden by the cross-feed dedup are marked too',
    () async {
      const shared = 'https://outlet.test/story';
      final feed = await load([
        _item('x', feed: 'a', link: shared),
        _item('x', category: 'World', feed: 'b', link: shared),
        _item('other'),
      ]);
      expect(feed.filteredItems, hasLength(2), reason: 'one copy is shown');
      expect(feed.unreadInView(), hasLength(3), reason: 'as the badge counts');
      expect(feed.unreadCount(), 3);

      await feed.markItemsAsRead(feed.unreadInView());

      expect(feed.unreadCount(), 0);
      expect(feed.unreadCount(category: 'World'), 0);
      feed.applySheetFilter(readFilter: 'unread', categories: {});
      expect(feed.unreadInView(), isEmpty, reason: 'no hidden copy resurfaces');
      expect(feed.hasUnreadInView, isFalse);
      feed.dispose();
    },
  );

  test('a copy in another folder is its own row and stays unread', () async {
    const shared = 'https://outlet.test/story';
    final feed = await load([
      _item('x', feed: 'a', link: shared),
      _item('x', category: 'World', feed: 'b', link: shared),
      _item('w', category: 'World', feed: 'b'),
    ]);
    feed.selectCategory('News');
    expect(feed.unreadInView(), hasLength(1));

    await feed.markItemsAsRead(feed.unreadInView());

    expect(feed.unreadCount(category: 'World'), 2);
    feed.dispose();
  });

  test('a hidden copy whose shown twin was opened still gets marked', () async {
    const shared = 'https://outlet.test/story';
    final feed = await load([
      _item('x', feed: 'a', link: shared),
      _item('x', category: 'World', feed: 'b', link: shared),
    ]);
    await feed.markAsRead(feed.filteredItems.single); // Opened the shown one.
    expect(feed.unreadCount(), 1);
    expect(feed.hasUnreadInView, isTrue);

    await feed.markItemsAsRead(feed.unreadInView());

    expect(feed.unreadCount(), 0);
    expect(feed.hasUnreadInView, isFalse);
    feed.dispose();
  });
}
