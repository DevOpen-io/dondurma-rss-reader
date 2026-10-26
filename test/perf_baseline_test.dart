// Performance baseline measurements — pure-Dart micro-benchmarks run as
// tests so results are reproducible (`flutter test test/perf_baseline_test.dart`).
// Numbers are printed to stdout; they are NOT assertions — the suite must not
// fail on a slow CI machine.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/feed_date_groups.dart';
import 'package:ice_cream_rss_reader/services/feed_cache_policy.dart';
import 'package:ice_cream_rss_reader/services/feed_list_filter.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';

FeedItem _item(int i) {
  return FeedItem(
    id: 'item-$i',
    siteName: 'Feed ${i % 50}',
    title: 'Article $i — a reasonably long headline for layout work',
    description: 'Description $i ' * 8,
    timeAgo: 'now',
    siteIcon: Icons.article,
    iconColor: Colors.blue,
    iconBackgroundColor: Colors.white,
    link: 'https://example.com/a/$i',
    feedUrl: 'https://example.com/feed/${i % 50}',
    pubDate: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
  );
}

Duration _time(void Function() fn, {int warmups = 1, int runs = 5}) {
  for (var i = 0; i < warmups; i++) {
    fn();
  }
  final times = <int>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    times.add(sw.elapsedMicroseconds);
  }
  times.sort();
  return Duration(microseconds: times[times.length ~/ 2]);
}

void main() {
  final items = List.generate(10000, _item);

  test('incremental merge measurement at 30, 100 and 200 feeds', () {
    final now = DateTime.utc(2026, 10, 24);
    for (final feedCount in [30, 100, 200]) {
      final sample = [
        for (var f = 0; f < feedCount; f++)
          for (var i = 0; i < 50; i++)
            _item(f * 50 + i).copyWith(feedUrl: 'https://feed-$f.test/rss'),
      ];
      final fresh = <String, List<FeedItem>>{};
      for (final item in sample.take(250)) {
        (fresh[item.feedUrl] ??= []).add(item);
      }
      final median = _time(
        () {
          final merged = FeedCachePolicy.mergeVisibleFeeds(
            existingItems: sample,
            freshItemsByFeed: fresh,
            subscribedFeedUrls: [
              for (var f = 0; f < feedCount; f++) 'https://feed-$f.test/rss',
            ],
            bookmarkedItems: const [],
            now: now,
          );
          expect(merged.length, sample.length);
        },
        warmups: 3,
        runs: 15,
      );
      // Debug/JIT host measurement, not a device frame-time benchmark.
      // ignore: avoid_print
      print(
        'PERF|merge|feeds=$feedCount|items=${sample.length}|median=${median.inMicroseconds}us',
      );
    }
  });

  test('perf baseline: filter / group / sort / json / parse', () {
    final filterMedian = _time(
      () => applyFeedFilters(
        items: items,
        isRead: (_) => false,
        selectedCategory: null,
        selectedFeedUrl: null,
        searchQuery: '',
        readFilter: 'all',
        filterCategories: const {},
        globalKeywords: const [],
        feedKeywordsMap: const {},
      ).toList(),
    );

    final groupMedian = _time(
      () => groupFeedItemsByDate(items, DateTime.now()),
    );

    final now = DateTime.now();
    final sortMedian = _time(() {
      final copy = List<FeedItem>.of(items)..shuffle();
      sortByEffectivePubDateDesc(copy, now);
    });

    final encodeMedian = _time(
      () => jsonEncode(items.map((i) => i.toJson()).toList()),
    );

    final encoded = jsonEncode(items.map((i) => i.toJson()).toList());
    final decodeMedian = _time(
      () => (jsonDecode(encoded) as List).cast<Map<String, dynamic>>(),
    );
    final fromJsonMedian = _time(() {
      final maps = (jsonDecode(encoded) as List).cast<Map<String, dynamic>>();
      maps.map(FeedItem.fromJson).toList();
    });

    // Feed parsing: a synthetic RSS body of 100 items, parsed 20×.
    final rssItem = '''
<item><title>T</title><link>https://x/i</link>
<pubDate>Mon, 12 Oct 2026 12:00:00 GMT</pubDate>
<description>d</description></item>''';
    final rssBody =
        '<rss><channel><title>t</title>${rssItem * 100}</channel></rss>';
    final bodyBytes = utf8.encode(rssBody);
    final parseMedian = _time(
      () => FeedService.parseFeedBody((
        bodyBytes: bodyBytes,
        category: 'Test',
        url: 'https://x/feed',
        contentType: null,
      )),
      runs: 20,
    );

    // ignore: avoid_print
    print(
      'PERF|10k items|filter=${filterMedian.inMicroseconds}us'
      '|group=${groupMedian.inMicroseconds}us'
      '|sort=${sortMedian.inMicroseconds}us'
      '|encode=${encodeMedian.inMicroseconds}us'
      '|decode=${decodeMedian.inMicroseconds}us'
      '|decode+fromJson=${fromJsonMedian.inMicroseconds}us'
      '|parse100RssItems=${parseMedian.inMicroseconds}us',
    );
  });
}
