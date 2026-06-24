import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';

FeedItem _item(String id, {DateTime? pubDate}) => FeedItem(
  id: id,
  siteName: 'Site',
  title: id,
  description: '',
  timeAgo: '',
  siteIcon: Icons.rss_feed,
  iconColor: const Color(0xFF000000),
  iconBackgroundColor: const Color(0x00000000),
  pubDate: pubDate,
);

void main() {
  group('FeedService.capItems', () {
    test('returns the list unchanged when at or below the cap', () {
      final items = List.generate(10, (i) => _item('$i'));
      expect(FeedService.capItems(items), same(items));
    });

    test('keeps only the most-recent maxItemsPerFeed when exceeded', () {
      final base = DateTime(2026, 1, 1);
      // 60 items, newest first by index 0 → oldest at the end.
      final items = List.generate(
        FeedService.maxItemsPerFeed + 10,
        (i) => _item('$i', pubDate: base.add(Duration(minutes: -i))),
      );
      // Shuffle order so capItems must sort, not just truncate.
      items.shuffle();

      final capped = FeedService.capItems(items);

      expect(capped.length, FeedService.maxItemsPerFeed);
      // The newest (index 0..maxItemsPerFeed-1) survive; the oldest are dropped.
      final ids = capped.map((e) => e.id).toSet();
      expect(ids.contains('0'), isTrue);
      expect(ids.contains('${FeedService.maxItemsPerFeed + 9}'), isFalse);
    });
  });

  group('FeedService.fallbackId', () {
    test('is stable for the same content across calls', () {
      final a = FeedService.fallbackId('https://f', 'Title', 'Mon, 01 Jan');
      final b = FeedService.fallbackId('https://f', 'Title', 'Mon, 01 Jan');
      expect(a, b);
    });

    test('differs when title or feed differs', () {
      final a = FeedService.fallbackId('https://f', 'Title', 'd');
      expect(a, isNot(FeedService.fallbackId('https://f', 'Other', 'd')));
      expect(a, isNot(FeedService.fallbackId('https://g', 'Title', 'd')));
    });

    test('tolerates null title/date', () {
      expect(FeedService.fallbackId('https://f', null, null), isNotEmpty);
    });
  });

  group('FeedProvider.shouldRunPeriodicSync', () {
    final now = DateTime(2026, 6, 24, 12, 0, 0);

    test('runs when no sync has ever happened', () {
      expect(
        FeedProvider.shouldRunPeriodicSync(
          lastSyncTime: null,
          now: now,
          intervalSeconds: 300,
        ),
        isTrue,
      );
    });

    test('skips when a sync completed within the interval', () {
      expect(
        FeedProvider.shouldRunPeriodicSync(
          lastSyncTime: now.subtract(const Duration(seconds: 30)),
          now: now,
          intervalSeconds: 300,
        ),
        isFalse,
      );
    });

    test('runs when the last sync is older than the interval', () {
      expect(
        FeedProvider.shouldRunPeriodicSync(
          lastSyncTime: now.subtract(const Duration(seconds: 301)),
          now: now,
          intervalSeconds: 300,
        ),
        isTrue,
      );
    });
  });
}
