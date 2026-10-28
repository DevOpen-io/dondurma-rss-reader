import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/feed_cache_policy.dart';

FeedItem _item(
  String feedUrl,
  String id, {
  DateTime? pubDate,
}) => FeedItem(
  id: id,
  siteName: 'Site',
  title: id,
  description: '',
  timeAgo: '',
  siteIcon: Icons.rss_feed,
  iconColor: const Color(0xFF000000),
  iconBackgroundColor: const Color(0x00000000),
  feedUrl: feedUrl,
  pubDate: pubDate,
);

void main() {
  test(
    'visible merge replaces only settled feeds and preserves local data',
    () {
      final now = DateTime.utc(2026, 10, 24, 12);
      final merged = FeedCachePolicy.mergeVisibleFeeds(
        existingItems: [
          _item('a', 'keep'),
          _item('a', 'gone'),
          _item('b', 'waiting'),
          _item('removed', 'stale'),
        ],
        freshItemsByFeed: {
          'a': [
            _item('a', 'new', pubDate: now),
            _item('a', 'keep'),
            _item('a', 'keep'),
          ],
        },
        subscribedFeedUrls: ['a', 'b'],
        bookmarkedItems: [_item('removed', 'saved')],
        now: now,
      );
      expect(merged.map((i) => i.id), ['new', 'keep', 'saved', 'waiting']);
    },
  );

  for (final id in ['shared-guid', 'https://example.test/shared']) {
    test('bookmark from removed feed survives colliding identity $id', () {
      final merged = FeedCachePolicy.mergeVisibleFeeds(
        existingItems: [_item('active', id)],
        freshItemsByFeed: {
          'active': [_item('active', id), _item('active', id)],
        },
        subscribedFeedUrls: ['active', 'active'],
        bookmarkedItems: [_item('removed', id)],
        now: DateTime.utc(2026),
      );
      expect(merged.map((i) => (i.feedUrl, i.id)).toSet(), {
        ('active', id),
        ('removed', id),
      });
      expect(merged.length, 2);
    });
  }

  test(
    'background merge deduplicates within feeds, never across GUID namespaces',
    () {
      final merged = FeedCachePolicy.mergeFreshFeeds(
        existingItems: [_item('b', 'x')],
        freshItemsByFeed: {
          'a': [_item('a', 'x'), _item('a', 'x')],
        },
        subscribedFeedUrls: ['a', 'a', 'b'],
      );
      expect(merged.map((i) => (i.feedUrl, i.id)), [('a', 'x'), ('b', 'x')]);
    },
  );

  group('FeedCachePolicy.mergeFreshFeeds', () {
    test(
      'fresh 200 replaces the feed\'s items',
      () {
        const url = 'feed-a';
        final existing = [_item(url, 'keep'), _item(url, 'gone')];
        final fresh = [_item(url, 'keep'), _item(url, 'new')];

        final merged = FeedCachePolicy.mergeFreshFeeds(
          existingItems: existing,
          freshItemsByFeed: {url: fresh},
          subscribedFeedUrls: [url],
        );

        expect(merged.map((i) => i.id), ['keep', 'new']);
      },
    );
  });
}
