import 'dart:convert';

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
        'https://www.reddit.com/r/FlutterDev/.rss',
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

  group('FeedService.discoverFeeds', () {
    test('returns the alternates of the final page after redirects', () async {
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

      final feeds = await service.discoverFeeds('https://old.test/');

      expect([for (final f in feeds) f.url], ['https://new.test/blog/rss.xml']);
      expect(requests, ['https://old.test/', 'https://new.test/blog/']);
    });

    test('without alternates, tries the usual feed paths in order', () async {
      final requests = <String>[];
      final paced = <String>[];
      final service = FeedService(
        client: MockClient((request) async {
          requests.add(request.url.path);
          return switch (request.url.path) {
            '/' => http.Response('<html><head></head></html>', 200),
            // A soft 404: HTML with status 200 is not a feed.
            '/feed' => http.Response('<html>Not found</html>', 200),
            '/rss' => http.Response('', 404),
            '/rss.xml' => http.Response.bytes(utf8.encode(_rss), 200),
            _ => http.Response('', 404),
          };
        }),
      );

      final feeds = await service.discoverFeeds(
        'https://site.test/',
        pace: (url) async => paced.add(url),
      );

      expect([for (final f in feeds) f.url], ['https://site.test/rss.xml']);
      expect(requests, ['/', '/feed', '/rss', '/rss.xml']);
      expect(paced, hasLength(requests.length), reason: 'every request paced');
    });

    test('finds nothing on a page without feeds', () async {
      final service = FeedService(
        client: MockClient(
          (request) async => request.url.path == '/'
              ? http.Response('<html></html>', 200)
              : http.Response('', 404),
        ),
      );
      expect(await service.discoverFeeds('https://site.test/'), isEmpty);
    });
  });
}
