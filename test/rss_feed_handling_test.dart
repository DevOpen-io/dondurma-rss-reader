import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';

/// Exercises real-world RSS/Atom variants through [FeedService] — both the
/// pure [FeedService.parseFeedBody] path and full HTTP [fetchFeed] round-trips
/// against a loopback server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FeedFetchException? parseError(String body) {
    try {
      FeedService.parseFeedBody((
        bodyBytes: utf8.encode(body),
        category: 'T',
        url: 'https://x/f.xml',
      ));
      return null;
    } on FeedFetchException catch (e) {
      return e;
    }
  }

  List<FeedItem> parse(String body, {String url = 'https://x/f.xml'}) =>
      FeedService.parseFeedBody((
        bodyBytes: utf8.encode(body),
        category: 'T',
        url: url,
      ));

  group('RSS 2.0 variants', () {
    test('standard RSS parses items with guid/pubDate/description', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>Site</title>
<item><title>A</title><guid>g1</guid><link>https://x/1</link>
<pubDate>Wed, 26 Aug 2026 10:00:00 +0000</pubDate>
<description>Body one</description></item>
</channel></rss>''');
      expect(items.single.id, 'g1');
      expect(items.single.title, 'A');
      expect(items.single.link, 'https://x/1');
      expect(items.single.pubDate, isNotNull);
    });

    test('content:encoded is preferred over description as content', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
<channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link>
<description>Short</description>
<content:encoded><![CDATA[<p>Full <b>html</b> body</p>]]></content:encoded>
</item></channel></rss>''');
      expect(items.single.content, contains('Full'));
    });

    test('CDATA sections in title/description parse cleanly', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title><![CDATA[CData Site]]></title>
<item><title><![CDATA[<script>alert(1)</script> CData Title]]></title>
<guid>g</guid><link>https://x/1</link>
<description><![CDATA[<p>desc & more</p>]]></description></item>
</channel></rss>''');
      expect(items.single.title, contains('CData Title'));
      expect(items.single.description, contains('desc'));
    });

    test('HTML entities are decoded in titles', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>Fish &amp; Chips &quot;today&#39;s&quot; special</title>
<guid>g</guid><link>https://x/1</link></item>
</channel></rss>''');
      expect(items.single.title, 'Fish & Chips "today\'s" special');
    });

    test('item without guid falls back to link as id', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>A</title><link>https://x/article</link></item>
</channel></rss>''');
      expect(items.single.id, 'https://x/article');
    });

    test('item with neither guid nor link gets a stable fallback id', () {
      const body = '''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>Title A</title><pubDate>Wed, 26 Aug 2026 10:00:00 +0000</pubDate></item>
</channel></rss>''';
      final first = parse(body).single.id;
      final second = parse(body).single.id;
      expect(first, isNotEmpty);
      expect(first, second); // deterministic — read state depends on it
    });

    test('image enclosure populates imageUrl', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link>
<enclosure url="https://img/x.png" type="image/png"/></item>
</channel></rss>''');
      expect(items.single.imageUrl, 'https://img/x.png');
    });

    test('non-image enclosure does not populate imageUrl', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link>
<enclosure url="https://x/ep.mp3" type="audio/mpeg"/></item>
</channel></rss>''');
      expect(items.single.imageUrl, isNull);
    });

    test('img in description html becomes imageUrl', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link>
<description><![CDATA[<p>t</p><img src="https://img/d.png"/>]]></description></item>
</channel></rss>''');
      expect(items.single.imageUrl, 'https://img/d.png');
    });

    test('ISO-8601 pubDate parses to the correct instant', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link>
<pubDate>2026-08-26T10:00:00Z</pubDate></item>
</channel></rss>''');
      expect(items.single.pubDate, DateTime.utc(2026, 8, 26, 10));
    });

    test('dc:date (Dublin Core) is used when pubDate is absent', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link>
<dc:date>2026-08-26T12:30:00Z</dc:date></item>
</channel></rss>''');
      expect(items.single.pubDate, DateTime.utc(2026, 8, 26, 12, 30));
    });

    test('media:thumbnail in RSS 2.0 item populates imageUrl', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
<channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link>
<media:thumbnail url="https://img/rss.jpg"/></item>
</channel></rss>''');
      expect(items.single.imageUrl, 'https://img/rss.jpg');
    });

    test('relative item link resolves against the feed URL', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>A</title><guid>g</guid><link>/posts/1</link></item>
</channel></rss>''', url: 'https://blog.example.com/feeds/rss.xml');
      expect(items.single.link, 'https://blog.example.com/posts/1');
    });

    test('RSS 1.0 / RDF feed parses items (sibling <item> elements)', () {
      final items = parse('''<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
 xmlns="http://purl.org/rss/1.0/"
 xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel rdf:about="https://x"><title>RDF Site</title></channel>
<item rdf:about="https://x/1"><title>R1</title><link>https://x/1</link>
<dc:date>2026-08-26T10:00:00Z</dc:date>
<description>RDF body</description></item>
</rdf:RDF>''');
      expect(items.single.title, 'R1');
      expect(items.single.link, 'https://x/1');
      expect(items.single.pubDate, DateTime.utc(2026, 8, 26, 10));
      expect(items.single.siteName, 'RDF Site');
    });

    test('missing pubDate yields null pubDate, item still kept', () {
      final items = parse('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>S</title>
<item><title>A</title><guid>g</guid><link>https://x/1</link></item>
</channel></rss>''');
      expect(items.single.pubDate, isNull);
    });
  });

  group('Atom variants', () {
    test('standard Atom feed parses entries', () {
      final items = parse('''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<title>Atom Site</title>
<entry><title>E1</title><id>tag:x,2026:1</id>
<link href="https://x/e1"/>
<updated>2026-08-26T10:00:00Z</updated>
<summary>Entry body</summary></entry>
</feed>''');
      expect(items.single.id, 'tag:x,2026:1');
      expect(items.single.title, 'E1');
      expect(items.single.siteName, 'Atom Site');
      expect(items.single.pubDate, isNotNull);
    });

    test('entry-level media:thumbnail populates imageUrl', () {
      final items = parse('''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"
 xmlns:media="http://search.yahoo.com/mrss/">
<title>S</title>
<entry><title>V</title><id>e1</id><link href="https://x/a"/>
<updated>2026-08-26T10:00:00Z</updated>
<media:thumbnail url="https://img/t.jpg"/>
</entry></feed>''');
      expect(items.single.imageUrl, 'https://img/t.jpg');
    });

    test('YouTube entry derives thumbnail from the video link', () {
      // dart_rss drops media:group thumbnails — the service derives them.
      final items = parse('''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"
 xmlns:media="http://search.yahoo.com/mrss/">
<title>YT</title>
<entry><title>V</title><id>yt:v:1</id><link href="https://youtu.be/abc123"/>
<updated>2026-08-26T10:00:00Z</updated>
<media:group><media:thumbnail url="https://i.ytimg.com/vi/abc123/hq.jpg"/></media:group>
</entry></feed>''');
      expect(
        items.single.imageUrl,
        'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );
    });

    test('YouTube thumbnail derives from music/nocookie/embed/live URLs', () {
      for (final (link, id) in [
        ('https://music.youtube.com/watch?v=xyz789', 'xyz789'),
        ('https://www.youtube-nocookie.com/embed/em42', 'em42'),
        ('https://youtube.com/embed/em42', 'em42'),
        ('https://m.youtube.com/live/lv99', 'lv99'),
        ('https://youtube.com/live/lv99', 'lv99'),
      ]) {
        final items = parse('''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<title>YT</title>
<entry><title>V</title><id>e1</id><link href="$link"/>
<updated>2026-08-26T10:00:00Z</updated>
</entry></feed>''');
        expect(
          items.single.imageUrl,
          'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          reason: 'link $link should derive thumbnail',
        );
      }
    });

    test('link rel=alternate is used for the article link', () {
      final items = parse('''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<title>S</title>
<entry><title>E</title><id>e1</id>
<link rel="self" href="https://x/feed"/>
<link rel="alternate" href="https://x/article"/>
<updated>2026-08-26T10:00:00Z</updated></entry>
</feed>''');
      expect(items.single.link, 'https://x/article');
    });

    test('namespace-prefixed <atom:feed> parses (issue #21)', () {
      final items = parse('''<?xml version="1.0" encoding="utf-8"?>
<atom:feed xmlns:atom="http://www.w3.org/2005/Atom">
<atom:title>Prefixed</atom:title>
<atom:entry><atom:title>P1</atom:title><atom:id>tag:x,2026:p1</atom:id>
<atom:link rel="alternate" href="https://x/p1"/>
<atom:updated>2026-08-26T10:00:00Z</atom:updated>
<atom:summary>Body</atom:summary></atom:entry>
</atom:feed>''');
      expect(items.single.id, 'tag:x,2026:p1');
      expect(items.single.title, 'P1');
      expect(items.single.link, 'https://x/p1');
      expect(items.single.pubDate, isNotNull);
    });

    test('content type="xhtml" keeps markup and images (issue #22)', () {
      final items = parse('''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<title>S</title>
<entry><title>E</title><id>e1</id><link href="https://x/a"/>
<updated>2026-08-26T10:00:00Z</updated>
<content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">
<p>Rich <b>body</b></p><img src="https://x/inline.jpg"/>
</div></content>
</entry></feed>''');
      expect(items.single.content, contains('<b>body</b>'));
      expect(items.single.content, contains('inline.jpg'));
      expect(items.single.imageUrl, 'https://x/inline.jpg');
      expect(items.single.description, contains('Rich body'));
    });

    test('content type="html" (escaped markup) still works unchanged', () {
      final items = parse('''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<title>S</title>
<entry><title>E</title><id>e1</id><link href="https://x/a"/>
<updated>2026-08-26T10:00:00Z</updated>
<content type="html">&lt;p&gt;Esc &lt;b&gt;body&lt;/b&gt;
&lt;img src="https://x/e.jpg"/&gt;&lt;/p&gt;</content>
</entry></feed>''');
      expect(items.single.imageUrl, 'https://x/e.jpg');
      expect(items.single.description, contains('Esc body'));
    });
  });

  group('error handling', () {
    test('malformed XML throws a parse-kind error', () {
      final e = parseError('<rss><channel><item><title>unclosed');
      expect(e, isNotNull);
      expect(e!.kind, FeedFetchErrorKind.parse);
    });

    test('plain HTML page is a parse error, not an empty feed', () {
      final e = parseError(
        '<!DOCTYPE html><html><body><h1>Not a feed</h1></body></html>',
      );
      expect(e?.kind, FeedFetchErrorKind.parse);
    });

    test('empty body is a parse error', () {
      expect(parseError('')?.kind, FeedFetchErrorKind.parse);
    });

    test('non-feed JSON body is a parse error', () {
      final e = parseError('{"version":"https://jsonfeed.org/version/1"}');
      expect(e?.kind, FeedFetchErrorKind.parse);
    });
  });

  group('JSON Feed (issue #25)', () {
    test('v1.1 feed parses items with html content', () {
      final items = parse('''{
"version": "https://jsonfeed.org/version/1.1",
"title": "JSON Blog",
"items": [
{"id": "https://j/post-1", "url": "https://j/post-1",
 "title": "Post One",
 "content_html": "<p>Hello <b>world</b></p><img src=\\"https://j/i.png\\"/>",
 "date_published": "2026-08-26T10:00:00Z",
 "image": "https://j/cover.png"}
]}''');
      expect(items.single.id, 'https://j/post-1');
      expect(items.single.title, 'Post One');
      expect(items.single.siteName, 'JSON Blog');
      expect(items.single.imageUrl, 'https://j/cover.png');
      expect(items.single.pubDate, isNotNull);
      expect(items.single.description, contains('Hello world'));
    });

    test('content_text, summary fallback and image attachment', () {
      final items = parse('''{
"version": "https://jsonfeed.org/version/1",
"title": "J",
"items": [
{"id": "x1", "external_url": "https://j/ext",
 "content_text": "plain body", "summary": "short",
 "date_modified": "2026-08-20T00:00:00Z",
 "attachments": [{"url": "https://j/att.jpg", "mime_type": "image/jpeg"}]}
]}''');
      final item = items.single;
      expect(item.link, 'https://j/ext');
      expect(item.description, 'short');
      expect(item.content, 'plain body');
      expect(item.imageUrl, 'https://j/att.jpg');
      expect(item.pubDate, isNotNull);
    });

    test('missing id falls back to url, then deterministic id', () {
      final items = parse('''{
"version": "https://jsonfeed.org/version/1",
"title": "J",
"items": [
{"url": "https://j/a", "title": "A"},
{"title": "No id no url"}
]}''');
      expect(items[0].id, 'https://j/a');
      expect(items[1].id, isNotEmpty);
    });
  });

  group('HTTP fetchFeed', () {
    late HttpServer server;

    setUpAll(() async {
      // flutter_test's binding installs a 400-only HttpOverrides client —
      // these tests need the real loopback server.
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest r) async {
        switch (r.uri.path) {
          case '/ok.xml':
            r.response.headers.contentType = ContentType(
              'application',
              'rss+xml',
            );
            r.response.headers.set(HttpHeaders.etagHeader, '"v1"');
            r.response.write('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>OK</title>
<item><title>I</title><guid>i1</guid><link>https://x/i</link></item>
</channel></rss>''');
          case '/notfound.xml':
            r.response.statusCode = HttpStatus.notFound;
          case '/boom.xml':
            r.response.statusCode = HttpStatus.internalServerError;
          case '/redirect.xml':
            r.response.statusCode = HttpStatus.movedPermanently;
            r.response.headers.set(HttpHeaders.locationHeader, '/ok.xml');
          case '/html.xml':
            r.response.headers.contentType = ContentType('text', 'html');
            r.response.write('<html><body>oops</body></html>');
          case '/latin1.xml':
            // Legacy feeds declare ISO-8859-1 — bytes are not valid UTF-8.
            r.response.headers.contentType = ContentType(
              'application',
              'rss+xml',
              charset: 'iso-8859-1',
            );
            r.response.add(
              latin1.encode('''<?xml version="1.0" encoding="ISO-8859-1"?>
<rss version="2.0"><channel><title>Caf\u00e9</title>
<item><title>Caf\u00e9 item</title><guid>l1</guid></item>
</channel></rss>'''),
            );
          case '/bom.xml':
            r.response.add(
              utf8.encode(
                '﻿<?xml version="1.0"?>'
                '<rss version="2.0"><channel><title>BOM</title>'
                '<item><title>B</title><guid>b1</guid></item>'
                '</channel></rss>',
              ),
            );
          case '/utf16.xml':
            // UTF-16LE with BOM — interleave each UTF-8 byte with a NUL.
            final units = utf8.encode('''<?xml version="1.0" encoding="UTF-16"?>
<rss version="2.0"><channel><title>U16</title>
<item><title>W</title><guid>u1</guid></item>
</channel></rss>''');
            r.response.add(<int>[
              0xFF,
              0xFE,
              for (final b in units) ...[b, 0],
            ]);
          case '/cond.xml':
            if (r.headers.value(HttpHeaders.ifNoneMatchHeader) == '"v2"') {
              r.response.statusCode = HttpStatus.notModified;
            } else {
              r.response.headers.set(HttpHeaders.etagHeader, '"v2"');
              r.response.write('''<?xml version="1.0"?>
<rss version="2.0"><channel><title>C</title>
<item><title>C1</title><guid>c1</guid></item>
</channel></rss>''');
            }
        }
        await r.response.close();
      });
    });

    tearDownAll(() => server.close(force: true));

    String url(String p) => 'http://127.0.0.1:${server.port}$p';

    test('200 returns items', () async {
      final service = FeedService();
      final result = await service.fetchFeed(url('/ok.xml'), 'T');
      expect(result.items.single.id, 'i1');
      expect(result.etag, '"v1"');
      service.dispose();
    });

    test('404 throws httpStatus-kind error', () async {
      final service = FeedService();
      try {
        await service.fetchFeed(url('/notfound.xml'), 'T');
        fail('should have thrown');
      } on FeedFetchException catch (e) {
        expect(e.kind, FeedFetchErrorKind.httpStatus);
        expect(e.message, contains('404'));
      }
      service.dispose();
    });

    test('500 throws httpStatus-kind error', () async {
      final service = FeedService();
      try {
        await service.fetchFeed(url('/boom.xml'), 'T');
        fail('should have thrown');
      } on FeedFetchException catch (e) {
        expect(e.kind, FeedFetchErrorKind.httpStatus);
      }
      service.dispose();
    });

    test('301 redirect is followed to the feed', () async {
      final service = FeedService();
      final result = await service.fetchFeed(url('/redirect.xml'), 'T');
      expect(result.items.single.id, 'i1');
      service.dispose();
    });

    test('301 redirect exposes the resolved final URL (issue #31)', () async {
      final service = FeedService();
      final result = await service.fetchFeed(url('/redirect.xml'), 'T');
      expect(result.finalUrl, url('/ok.xml'));
      service.dispose();
    });

    test('no redirect leaves finalUrl null', () async {
      final service = FeedService();
      final result = await service.fetchFeed(url('/ok.xml'), 'T');
      expect(result.finalUrl, isNull);
      service.dispose();
    });

    test('HTML body at a .xml URL is a parse error', () async {
      final service = FeedService();
      try {
        await service.fetchFeed(url('/html.xml'), 'T');
        fail('should have thrown');
      } on FeedFetchException catch (e) {
        expect(e.kind, FeedFetchErrorKind.parse);
      }
      service.dispose();
    });

    test('connection refused is a connectivity error', () async {
      final service = FeedService();
      // Bind then close a port to guarantee a refused connection.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      try {
        await service.fetchFeed('http://127.0.0.1:$deadPort/x.xml', 'T');
        fail('should have thrown');
      } on FeedFetchException catch (e) {
        expect(e.kind, FeedFetchErrorKind.connectivity);
      }
      service.dispose();
    });

    test('ISO-8859-1 declared body decodes accented text', () async {
      final service = FeedService();
      final result = await service.fetchFeed(url('/latin1.xml'), 'T');
      expect(result.items.single.id, 'l1');
      expect(result.items.single.title, 'Café item');
      service.dispose();
    });

    test('UTF-8 BOM-prefixed body parses', () async {
      final service = FeedService();
      final result = await service.fetchFeed(url('/bom.xml'), 'T');
      expect(result.items.single.id, 'b1');
      service.dispose();
    });

    test('UTF-16LE body decodes and parses', () async {
      final service = FeedService();
      final result = await service.fetchFeed(url('/utf16.xml'), 'T');
      expect(result.items.single.id, 'u1');
      service.dispose();
    });

    test('validators are sent and 304 yields notModified', () async {
      final service = FeedService();
      final first = await service.fetchFeed(url('/cond.xml'), 'T');
      expect(first.etag, '"v2"');
      final second = await service.fetchFeed(
        url('/cond.xml'),
        'T',
        etag: first.etag,
      );
      expect(second.notModified, isTrue);
      service.dispose();
    });
  });
}
