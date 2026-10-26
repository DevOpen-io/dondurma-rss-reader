import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/feed_cache_policy.dart';

FeedItem _item(
  String feedUrl,
  String id, {
  String? prefetchedFullText,
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
  prefetchedFullText: prefetchedFullText,
  pubDate: pubDate,
);

void main() {
  test(
    'visible merge replaces only settled feeds and preserves local data',
    () {
      final now = DateTime.utc(2026, 10, 24, 12);
      final merged = FeedCachePolicy.mergeVisibleFeeds(
        existingItems: [
          _item('a', 'keep', prefetchedFullText: 'body'),
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
      expect(
        merged.singleWhere((i) => i.id == 'keep').prefetchedFullText,
        'body',
      );
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
        bookmarkedItems: [
          _item('removed', id, prefetchedFullText: 'saved body'),
        ],
        now: DateTime.utc(2026),
      );
      expect(merged.map((i) => (i.feedUrl, i.id)).toSet(), {
        ('active', id),
        ('removed', id),
      });
      expect(merged.length, 2);
      expect(
        merged.singleWhere((i) => i.feedUrl == 'removed').prefetchedFullText,
        'saved body',
      );
    });
  }

  test('full text composite identity cannot collide on spaces', () {
    final merged = FeedCachePolicy.carryOverPrefetchedText(
      existingItems: [_item('feed a', 'b', prefetchedFullText: 'wrong body')],
      freshItems: [_item('feed', 'a b')],
    );
    expect(merged.single.prefetchedFullText, isNull);
  });

  test(
    'fresh body retains full text from bookmark even without a cached copy',
    () {
      final merged = FeedCachePolicy.mergeVisibleFeeds(
        existingItems: const [],
        freshItemsByFeed: {
          'a': [_item('a', 'x')],
        },
        subscribedFeedUrls: ['a'],
        bookmarkedItems: [_item('a', 'x', prefetchedFullText: 'saved body')],
        now: DateTime.utc(2026),
      );
      expect(merged.single.prefetchedFullText, 'saved body');
    },
  );

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

  group('FeedCachePolicy.carryOverPrefetchedText', () {
    test('re-attaches prefetched bodies onto freshly parsed items', () {
      final existing = [_item('a', 'x', prefetchedFullText: '<p>body</p>')];
      final fresh = [_item('a', 'x')];

      final merged = FeedCachePolicy.carryOverPrefetchedText(
        existingItems: existing,
        freshItems: fresh,
      );

      expect(merged.single.prefetchedFullText, '<p>body</p>');
    });

    test('matches by (feedUrl, id) — same id on another feed is untouched', () {
      final existing = [_item('a', 'x', prefetchedFullText: '<p>body</p>')];
      final fresh = [_item('b', 'x')];

      final merged = FeedCachePolicy.carryOverPrefetchedText(
        existingItems: existing,
        freshItems: fresh,
      );

      expect(merged.single.prefetchedFullText, isNull);
    });

    test('does not overwrite a body the fresh parse already carries', () {
      final existing = [_item('a', 'x', prefetchedFullText: 'old')];
      final fresh = [_item('a', 'x', prefetchedFullText: 'new')];

      final merged = FeedCachePolicy.carryOverPrefetchedText(
        existingItems: existing,
        freshItems: fresh,
      );

      expect(merged.single.prefetchedFullText, 'new');
    });
  });

  group('FeedCachePolicy.mergeFreshFeeds', () {
    test(
      'fresh 200 replaces items but keeps prefetched bodies (issue #20)',
      () {
        const url = 'feed-a';
        final existing = [
          _item(url, 'keep', prefetchedFullText: '<p>body</p>'),
          _item(url, 'gone'),
        ];
        final fresh = [_item(url, 'keep'), _item(url, 'new')];

        final merged = FeedCachePolicy.mergeFreshFeeds(
          existingItems: existing,
          freshItemsByFeed: {url: fresh},
          subscribedFeedUrls: [url],
        );

        expect(merged.map((i) => i.id), ['keep', 'new']);
        expect(
          merged.singleWhere((i) => i.id == 'keep').prefetchedFullText,
          '<p>body</p>',
        );
      },
    );
  });
}
