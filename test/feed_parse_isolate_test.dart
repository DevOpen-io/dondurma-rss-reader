import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/full_text_extraction_service.dart';

const _rssXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test &amp; Site</title>
    <item>
      <title>Hello &#8216;World&#8217;</title>
      <link>https://example.com/1</link>
      <guid>id-1</guid>
      <description>&lt;p&gt;Some description&lt;/p&gt;&lt;img src="https://img.example.com/1.jpg"/&gt;</description>
      <pubDate>Thu, 02 Jul 2026 12:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';

const _atomXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Site</title>
  <entry>
    <id>atom-1</id>
    <title>Atom Entry</title>
    <link href="https://example.com/a1"/>
    <summary>Plain summary</summary>
    <updated>2026-07-02T09:30:00Z</updated>
  </entry>
</feed>
''';

void main() {
  group('FeedService.parseFeedBody (runs in isolate via compute)', () {
    test('parses RSS body, decodes entities, extracts image and date',
        () async {
      final items = await compute(FeedService.parseFeedBody, (
        bodyBytes: utf8.encode(_rssXml),
        category: 'Tech',
        url: 'https://feed.example.com/rss',
      ));

      expect(items, hasLength(1));
      final item = items.first;
      expect(item.id, 'id-1');
      expect(item.siteName, 'Test & Site');
      expect(item.title, 'Hello ‘World’');
      expect(item.description, 'Some description');
      expect(item.imageUrl, 'https://img.example.com/1.jpg');
      expect(item.pubDate, DateTime.utc(2026, 7, 2, 12));
      expect(item.category, 'Tech');
      expect(item.feedUrl, 'https://feed.example.com/rss');
    });

    test('falls back to Atom parsing when RSS parse fails', () async {
      final items = await compute(FeedService.parseFeedBody, (
        bodyBytes: utf8.encode(_atomXml),
        category: 'News',
        url: 'https://feed.example.com/atom',
      ));

      expect(items, hasLength(1));
      final item = items.first;
      expect(item.id, 'atom-1');
      expect(item.siteName, 'Atom Site');
      expect(item.link, 'https://example.com/a1');
      expect(item.pubDate, DateTime.utc(2026, 7, 2, 9, 30));
    });

    test('throws on a body that is neither RSS nor Atom', () async {
      expect(
        () => compute(FeedService.parseFeedBody, (
          bodyBytes: utf8.encode('<html><body>not a feed</body></html>'),
          category: 'X',
          url: 'https://feed.example.com/x',
        )),
        throwsException,
      );
    });
  });

  group('FullTextExtractionService.extractArticleHtml (isolate-safe)', () {
    test('extracts <article> content from a page', () async {
      final longParagraph =
          'This is a sufficiently long paragraph of article text that should '
          'comfortably exceed the one hundred character minimum required by '
          'the heuristic scoring function used during extraction.';
      final page = '''
<html><body>
  <nav>menu items</nav>
  <article><p>$longParagraph</p><p>$longParagraph</p></article>
  <footer>footer stuff</footer>
</body></html>
''';

      final html = await compute(
        FullTextExtractionService.extractArticleHtml,
        utf8.encode(page),
      );

      expect(html, isNotNull);
      expect(html, contains('sufficiently long paragraph'));
      expect(html, isNot(contains('menu items')));
    });

    test('returns null when no suitable content block exists', () async {
      final html = await compute(
        FullTextExtractionService.extractArticleHtml,
        utf8.encode('<html><body><div>short</div></body></html>'),
      );
      expect(html, isNull);
    });
  });
}
