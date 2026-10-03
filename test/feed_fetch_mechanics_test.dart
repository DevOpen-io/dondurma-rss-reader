import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/feed_decisions.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/feed_list_filter.dart';

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

  group('ArticleIdentity', () {
    test('rejects empty publisher IDs', () {
      expect(ArticleIdentity.nonEmpty(null), isNull);
      expect(ArticleIdentity.nonEmpty('   '), isNull);
      expect(ArticleIdentity.nonEmpty(' guid '), 'guid');
    });

    test('normalizes HTTP URLs conservatively', () {
      expect(
        ArticleIdentity.normalizeArticleUrl(
          ' HTTPS://Example.COM:443/path?q=1#section ',
        ),
        'https://example.com/path?q=1',
      );
      expect(
        ArticleIdentity.normalizeArticleUrl('https://example.com/path/'),
        'https://example.com/path/',
      );
    });

    test('normalizeFeedUrl folds scheme/host/trailing-slash variants', () {
      const canonical = 'https://example.com/feed';
      for (final variant in [
        'https://example.com/feed',
        'https://example.com/feed/',
        'HTTPS://EXAMPLE.COM/feed',
        'https://example.com:443/feed/',
      ]) {
        expect(ArticleIdentity.normalizeFeedUrl(variant), canonical);
      }
      expect(
        ArticleIdentity.normalizeFeedUrl('https://example.com/'),
        'https://example.com',
      );
      // Different paths stay different.
      expect(
        ArticleIdentity.normalizeFeedUrl('https://example.com/a'),
        isNot(ArticleIdentity.normalizeFeedUrl('https://example.com/b')),
      );
      // Query strings survive normalization.
      expect(
        ArticleIdentity.normalizeFeedUrl('https://example.com/f?x=1'),
        'https://example.com/f?x=1',
      );
    });

    test('sanitizeSiteTitle strips quoted search-query prefix', () {
      expect(
        ArticleIdentity.sanitizeSiteTitle(
          '"site:ft.com (oil OR gas) when:1d" - Google News',
        ),
        'Google News',
      );
      expect(
        ArticleIdentity.sanitizeSiteTitle('"site:apnews.com" - Google News'),
        'Google News',
      );
    });

    test('sanitizeSiteTitle leaves ordinary titles untouched', () {
      expect(ArticleIdentity.sanitizeSiteTitle('BBC News'), 'BBC News');
      expect(
        ArticleIdentity.sanitizeSiteTitle('The Verge - All Posts'),
        'The Verge - All Posts',
      );
      expect(
        ArticleIdentity.sanitizeSiteTitle('"Quoted Title"'),
        'Quoted Title',
      );
    });
  });

  group('feedShouldRunPeriodicSync', () {
    final now = DateTime(2026, 6, 24, 12, 0, 0);

    test('runs when no sync has ever happened', () {
      expect(
        feedShouldRunPeriodicSync(
          lastSyncTime: null,
          now: now,
          intervalSeconds: 300,
        ),
        isTrue,
      );
    });

    test('skips when a sync completed within the interval', () {
      expect(
        feedShouldRunPeriodicSync(
          lastSyncTime: now.subtract(const Duration(seconds: 30)),
          now: now,
          intervalSeconds: 300,
        ),
        isFalse,
      );
    });

    test('runs when the last sync is older than the interval', () {
      expect(
        feedShouldRunPeriodicSync(
          lastSyncTime: now.subtract(const Duration(seconds: 301)),
          now: now,
          intervalSeconds: 300,
        ),
        isTrue,
      );
    });
  });

  group('deduplicateByLink', () {
    FeedItem linked(String id, String link, {String feed = 'f1'}) =>
        _item(id).copyWith(link: link, feedUrl: feed);

    test('drops the later copy of a cross-feed duplicate', () {
      final items = [
        linked('a', 'https://x.com/story', feed: 'news'),
        linked('b', 'https://x.com/story', feed: 'world'),
        linked('c', 'https://x.com/other', feed: 'world'),
      ];
      final out = deduplicateByLink(items).toList();
      expect(out.map((e) => e.id), ['a', 'c']);
    });

    test('normalizes link variants before comparing', () {
      final items = [
        linked('a', 'HTTPS://x.com:443/story'),
        linked('b', 'https://x.com/story#comments'),
        linked('c', 'https://x.com/story'),
      ];
      // #fragment is already dropped by normalizeArticleUrl; all three are
      // the same article → only the first survives.
      final out = deduplicateByLink(items).toList();
      expect(out.map((e) => e.id), ['a']);
    });

    test('never collapses items without a usable link', () {
      final items = [
        _item('a').copyWith(feedUrl: 'f1'),
        _item('b').copyWith(feedUrl: 'f2'),
      ];
      expect(deduplicateByLink(items).map((e) => e.id), ['a', 'b']);
    });

    test('junk non-URL links fall back to item id instead of merging', () {
      final items = [
        linked('a', '#'),
        linked('b', 'about:blank'),
        linked('c', 'javascript:void(0)'),
        linked('d', '/relative/path'),
      ];
      expect(deduplicateByLink(items).map((e) => e.id), ['a', 'b', 'c', 'd']);
    });
  });
}
