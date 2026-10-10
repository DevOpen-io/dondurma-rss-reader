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
}
