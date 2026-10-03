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

  group('FeedCachePolicy.fairTrim', () {
    test('prefetched items survive the trim before unprotected ones', () {
      const url = 'a';
      final old = DateTime.utc(2026, 1, 1);
      final recent = DateTime.utc(2026, 8, 1);
      // Old-but-prefetched item + two newer unprotected items, limit 2:
      // the prefetched item must be kept despite being oldest (issue #33).
      final result = FeedCachePolicy.fairTrim(
        items: [
          _item(
            url,
            'old-protected',
            prefetchedFullText: '<p>x</p>',
            pubDate: old,
          ),
          _item(url, 'new-1', pubDate: recent),
          _item(url, 'new-2', pubDate: recent.add(const Duration(days: 1))),
        ],
        subscribedFeedUrls: [url],
        limit: 2,
      );

      expect(result.map((i) => i.id), containsAll(['old-protected', 'new-2']));
      expect(result.map((i) => i.id), isNot(contains('new-1')));
    });

    test('protected items still count toward the limit (no extra quota)', () {
      const url = 'a';
      final result = FeedCachePolicy.fairTrim(
        items: [
          for (var i = 0; i < 4; i++)
            _item(url, 'p$i', prefetchedFullText: '<p>x</p>'),
          _item(url, 'plain'),
        ],
        subscribedFeedUrls: [url],
        limit: 3,
      );

      expect(result, hasLength(3));
      expect(result.every((i) => i.prefetchedFullText != null), isTrue);
    });

    test('an all-protected feed still gets only its round-robin share', () {
      // Protection changes eviction ORDER, never capacity: a feed whose
      // items are all protected cannot starve a sibling feed (issue #33).
      final result = FeedCachePolicy.fairTrim(
        items: [
          _item('a', 'p1', prefetchedFullText: '<p>x</p>'),
          _item('a', 'p2', prefetchedFullText: '<p>x</p>'),
          _item('a', 'p3', prefetchedFullText: '<p>x</p>'),
          _item('b', 'u1'),
          _item('b', 'u2'),
        ],
        subscribedFeedUrls: ['a', 'b'],
        limit: 4,
      );

      // Round-robin: a gets rounds 0,2 (p1,p2 protected-first) — b keeps both.
      expect(result.map((i) => i.id), containsAll(['p1', 'p2', 'u1', 'u2']));
    });
  });
}
