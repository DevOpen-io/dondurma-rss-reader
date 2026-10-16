import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/feed_date_groups.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';

/// Deterministic timestamp-pipeline regressions. All tests inject explicit
/// `now` values — nothing depends on the real-world clock.
void main() {
  FeedItem item(String id, DateTime? pubDate) => FeedItem(
    id: id,
    siteName: 'Feed',
    title: id,
    description: '',
    timeAgo: '',
    siteIcon: Icons.web,
    iconColor: Colors.blue,
    iconBackgroundColor: Colors.grey,
    link: 'https://example.com/$id',
    pubDate: pubDate,
    feedUrl: 'https://example.com/rss',
  );

  group('RFC 822 / ISO 8601 parsing', () {
    // parseFeedBody is the production entry point — build minimal feeds.
    List<FeedItem> parseRss(String pubDate) => FeedService.parseFeedBody((
      bodyBytes: utf8.encode('''
<rss version="2.0"><channel><title>t</title>
<item><title>i</title><link>https://x/1</link><pubDate>$pubDate</pubDate></item>
</channel></rss>'''),
      category: 'Test',
      url: 'https://x/feed',
      contentType: 'application/rss+xml',
    ));

    test('numeric +0300 offset normalizes to UTC', () {
      final items = parseRss('Sat, 17 Oct 2026 00:10:00 +0300');
      expect(
        items.single.pubDate,
        DateTime.utc(2026, 10, 16, 21, 10),
      );
    });

    test('numeric -0500 offset normalizes to UTC', () {
      final items = parseRss('Fri, 16 Oct 2026 18:30:00 -0500');
      expect(
        items.single.pubDate,
        DateTime.utc(2026, 10, 16, 23, 30),
      );
    });

    test('GMT abbreviation parses as UTC', () {
      final items = parseRss('Sat, 17 Oct 2026 00:39:34 GMT');
      expect(
        items.single.pubDate,
        DateTime.utc(2026, 10, 17, 0, 39, 34),
      );
    });

    test('numeric +0530 (non-hour offset) is applied', () {
      final items = parseRss('Sat, 17 Oct 2026 04:00:00 +0530');
      expect(items.single.pubDate, DateTime.utc(2026, 10, 16, 22, 30));
    });

    test('ISO 8601 Z parses to UTC instant', () {
      final items = parseRss('2026-10-16T21:10:00Z');
      expect(items.single.pubDate, DateTime.utc(2026, 10, 16, 21, 10));
    });

    test('ISO 8601 with +03:00 offset parses correctly', () {
      final items = parseRss('2026-10-17T00:10:00+03:00');
      expect(
        items.single.pubDate,
        DateTime.utc(2026, 10, 16, 21, 10),
      );
    });

    test('date-only pubDate parses', () {
      final items = parseRss('Sat, 17 Oct 2026');
      expect(items.single.pubDate, isNotNull);
    });

    test('invalid date yields null pubDate, item kept', () {
      final items = parseRss('not-a-date');
      expect(items.single.pubDate, isNull);
    });
  });

  group('groupFeedItemsByDate — local calendar boundary', () {
    test('UTC instant lands in local-day bucket, not UTC-day bucket', () {
      // 22:00 UTC Oct 16 = 01:00 Oct 17 in +03:00 → "today" for a +03 user.
      final now = DateTime.utc(2026, 10, 16, 22, 30); // 01:30 +03 Oct 17
      final groups = groupFeedItemsByDate([
        item('a', DateTime.utc(2026, 10, 16, 22, 0)),
      ], now);
      // The correct bucket depends on the test host's zone — assert the
      // invariant instead: same local calendar day as `now`.
      final localPub = DateTime.utc(2026, 10, 16, 22, 0).toLocal();
      final localNow = now.toLocal();
      final sameDay = localPub.year == localNow.year &&
          localPub.month == localNow.month &&
          localPub.day == localNow.day;
      if (sameDay) {
        expect(groups.today.single.id, 'a');
      } else {
        expect(groups.today, isEmpty);
      }
    });

    test('midnight crossing: UTC late-night is next local day', () {
      final now = DateTime(2026, 10, 17, 1, 0); // local
      final justAfterMidnight = DateTime(2026, 10, 17, 0, 30); // local
      final beforeMidnight = DateTime(2026, 10, 16, 23, 45); // local
      final groups = groupFeedItemsByDate([
        item('today', justAfterMidnight),
        item('yday', beforeMidnight),
      ], now);
      expect(groups.today.single.id, 'today');
      expect(groups.yesterday.single.id, 'yday');
    });

    test('null pubDate lands in older', () {
      final groups = groupFeedItemsByDate(
        [item('x', null)],
        DateTime(2026, 10, 17),
      );
      expect(groups.older.single.id, 'x');
    });
  });

  group('future-dated timestamps', () {
    final now = DateTime(2026, 10, 17, 1, 0);

    test('within skew allowance is not clamped', () {
      final d = now.add(const Duration(minutes: 10));
      expect(effectivePublicationDate(d, now), d);
    });

    test('implausibly future date is clamped to now', () {
      final d = now.add(const Duration(hours: 3));
      expect(effectivePublicationDate(d, now), now);
    });

    test('clamped future item groups as today, not older', () {
      final groups = groupFeedItemsByDate([
        item('future', now.add(const Duration(hours: 5))),
        item('real', now.subtract(const Duration(hours: 1))),
      ], now);
      expect(groups.today.map((i) => i.id), containsAll(['future', 'real']));
    });

    test('original pubDate is preserved (identity/cache untouched)', () {
      final future = now.add(const Duration(hours: 4));
      final i = item('f', future);
      groupFeedItemsByDate([i], now);
      expect(i.pubDate, future);
    });
  });

  group('JSON round-trip', () {
    test('pubDate survives serialization', () {
      final d = DateTime.utc(2026, 10, 16, 21, 10, 5);
      final i = item('j', d);
      final restored = FeedItem.fromJson(i.toJson());
      expect(restored.pubDate, d);
      expect(restored.pubDate!.isUtc, isTrue);
    });
  });
}
