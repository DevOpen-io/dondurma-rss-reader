import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/services/feed_discovery.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';

const _rss =
    '<?xml version="1.0"?><rss version="2.0"><channel><title>T</title>'
    '<item><title>A</title><link>https://site.test/a</link></item>'
    '</channel></rss>';

void main() {
  group('knownFeedUrl', () {
    test('rewrites subreddits and Reddit users', () {
      expect(
        knownFeedUrl('https://www.reddit.com/r/FlutterDev/'),
        'https://www.reddit.com/r/flutterdev/.rss',
      );
      expect(
        knownFeedUrl('https://old.reddit.com/r/dartlang/top/?t=week'),
        'https://www.reddit.com/r/dartlang/.rss',
      );
      expect(
        knownFeedUrl('https://reddit.com/user/spez'),
        'https://www.reddit.com/user/spez/.rss',
      );
      expect(
        knownFeedUrl('https://www.reddit.com/u/spez'),
        'https://www.reddit.com/user/spez/.rss',
      );
      expect(
        knownFeedUrl('https://www.reddit.com/user/spez/m/news'),
        'https://www.reddit.com/user/spez/m/news/.rss',
      );
    });

    test('rewrites YouTube channel ids and playlists', () {
      expect(
        knownFeedUrl('https://www.youtube.com/channel/UCabc_123-x/videos'),
        'https://www.youtube.com/feeds/videos.xml?channel_id=UCabc_123-x',
      );
      expect(
        knownFeedUrl('https://m.youtube.com/playlist?list=PLxyz'),
        'https://www.youtube.com/feeds/videos.xml?playlist_id=PLxyz',
      );
    });

    test('leaves everything else to discovery', () {
      expect(knownFeedUrl('https://www.youtube.com/@veritasium'), isNull);
      expect(knownFeedUrl('https://www.reddit.com/r/x/.rss'), isNull);
      expect(knownFeedUrl('https://mastodon.social/@Gargron'), isNull);
      expect(knownFeedUrl('https://example.com/feed'), isNull);
      expect(knownFeedUrl('not a url'), isNull);
    });
  });

  group('feedLinksInHtml', () {
    test('a malformed <base> is ignored; a charset in the type is fine', () {
      const html = '''
<html><head><base href="http://[::1">
<link rel="alternate" type="application/rss+xml; charset=utf-8" href="/rss">
</head></html>''';
      final feeds = feedLinksInHtml(html, Uri.parse('https://site.test/a/'));
      expect([for (final f in feeds) f.url], ['https://site.test/rss']);
    });

    test('reads feed alternates, resolves relative links, skips others', () {
      const html = '''
<html><head>
<link rel="alternate" type="application/rss+xml" title="Main" href="/rss/index.xml">
<link rel="Alternate" type="application/atom+xml" href="https://site.test/atom.xml">
<link rel="alternate" type="application/feed+json" href="feed.json">
<link rel="alternate" type="application/activity+json" href="/users/x">
<link rel="alternate" type="application/json" href="/wp-json/wp/v2/pages/1">
<link rel="alternate" hreflang="tr" href="/tr/">
<link rel="stylesheet" type="application/rss+xml" href="/not-a-feed">
<link rel="alternate" type="application/rss+xml" href="/rss/index.xml">
</head><body></body></html>''';
      final feeds = feedLinksInHtml(html, Uri.parse('https://site.test/blog/'));
      expect(
        [for (final f in feeds) f.url],
        [
          'https://site.test/rss/index.xml',
          'https://site.test/atom.xml',
          'https://site.test/blog/feed.json',
        ],
      );
      expect(feeds.first.title, 'Main');
      expect(feeds[1].title, isNull);
    });

    test('honors <base href> and ignores non-http links', () {
      const html = '''
<html><head><base href="https://cdn.site.test/b/">
<link rel="alternate" type="application/rss+xml" href="rss.xml">
<link rel="alternate" type="application/rss+xml" href="javascript:alert(1)">
</head></html>''';
      final feeds = feedLinksInHtml(html, Uri.parse('https://site.test/'));
      expect(
        [for (final f in feeds) f.url],
        ['https://cdn.site.test/b/rss.xml'],
      );
    });
  });

  group('looksLikeHtmlPage', () {
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
    test('pages are pages, feeds are not', () {
      expect(looksLikeHtmlPage(bytes('<!DOCTYPE html><html>')), isTrue);
      expect(looksLikeHtmlPage(bytes('\ufeff  <html lang="tr">')), isTrue);
      expect(looksLikeHtmlPage(bytes(_rss)), isFalse);
      expect(looksLikeHtmlPage(bytes('<feed xmlns="x">')), isFalse);
      expect(looksLikeHtmlPage(bytes('<atom:feed xmlns:atom="x">')), isFalse);
      expect(looksLikeHtmlPage(bytes('{"version": "x"}')), isFalse);
      expect(
        looksLikeHtmlPage(bytes('<rss version="2.0"><channel><ti')),
        isFalse,
        reason: 'a broken feed is still a feed',
      );
      expect(
        looksLikeHtmlPage(bytes('<div>no root</div>')),
        isFalse,
        reason: 'only an HTML root makes a page',
      );
    });
  });

  group('FeedService.discoverFeeds', () {
    FeedPage page(String url, String html) => (
      bodyBytes: Uint8List.fromList(utf8.encode(html)),
      url: url,
      contentType: 'text/html',
    );

    test('a web page fails fetchFeed with the final page attached', () async {
      final requests = <String>[];
      final service = FeedService(
        client: MockClient((request) async {
          requests.add(request.url.toString());
          if (request.url.host == 'old.test') {
            return http.Response(
              '',
              301,
              headers: {'location': 'https://new.test/blog/'},
              isRedirect: true,
            );
          }
          return http.Response(
            '<html><head><link rel="alternate" '
            'type="application/rss+xml" href="rss.xml"></head></html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );

      FeedFetchException? failure;
      try {
        await service.fetchFeed('https://old.test/', '');
      } on FeedFetchException catch (e) {
        failure = e;
      }
      expect(failure?.kind, FeedFetchErrorKind.parse);
      expect(failure?.page?.url, 'https://new.test/blog/');

      final feeds = await service.discoverFeeds(failure!.page!);
      expect([for (final f in feeds) f.url], ['https://new.test/blog/rss.xml']);
      expect(requests, [
        'https://old.test/',
        'https://new.test/blog/',
      ], reason: 'the page is not downloaded again');
    });

    test(
      'a feed served as text/html after a long prolog still parses',
      () async {
        final prolog = '<!-- ${'x' * 1500} -->';
        final service = FeedService(
          client: MockClient(
            (_) async => http.Response.bytes(
              utf8.encode('<?xml version="1.0"?>$prolog${_rss.substring(21)}'),
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            ),
          ),
        );
        final result = await service.fetchFeed('https://site.test/feed', '');
        expect(result.items, hasLength(1));
      },
    );

    test('a broken feed fails without a page, so no discovery runs', () async {
      final service = FeedService(
        client: MockClient(
          (_) async => http.Response(
            '<rss version="2.0"><channel><title>Cut',
            200,
            headers: {'content-type': 'application/rss+xml'},
          ),
        ),
      );
      await expectLater(
        service.fetchFeed('https://site.test/category/news/feed', ''),
        throwsA(
          isA<FeedFetchException>()
              .having((e) => e.kind, 'kind', FeedFetchErrorKind.parse)
              .having((e) => e.page, 'page', isNull),
        ),
      );
    });

    test('without alternates, tries the usual feed paths in order', () async {
      final requests = <String>[];
      final paced = <String>[];
      final service = FeedService(
        client: MockClient((request) async {
          requests.add(request.url.path);
          return switch (request.url.path) {
            // A soft 404: HTML with status 200 is not a feed.
            '/feed' => http.Response('<html>Not found</html>', 200),
            '/rss' => http.Response('', 404),
            '/rss.xml' => http.Response.bytes(utf8.encode(_rss), 200),
            _ => http.Response('', 404),
          };
        }),
      );

      final feeds = await service.discoverFeeds(
        page('https://site.test/blog/?ref=x', '<html><head></head></html>'),
        pace: (url) async => paced.add(url),
      );

      expect([for (final f in feeds) f.url], ['https://site.test/rss.xml']);
      expect(requests, ['/feed', '/rss', '/rss.xml']);
      expect(paced, hasLength(requests.length), reason: 'every request paced');
    });

    test('finds nothing on a site without feeds', () async {
      final service = FeedService(
        client: MockClient((_) async => http.Response('', 404)),
      );
      expect(
        await service.discoverFeeds(
          page('https://site.test/', '<html></html>'),
        ),
        isEmpty,
      );
    });
  });
}
