import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' show parse;

/// A feed address found for a page the user entered.
class DiscoveredFeed {
  const DiscoveredFeed(this.url, {this.title});

  final String url;

  /// The page's own label for the feed (`<link title>`), when it has one.
  final String? title;
}

/// Whether a response body is a web page rather than a feed: an HTML root
/// near the top and no feed root. Judged by the body alone — feeds served
/// as `text/html` with a long prolog are still feeds. Only such pages go to
/// discovery; a broken feed keeps its parse error.
bool looksLikeHtmlPage(Uint8List body) {
  final hasBom =
      body.length >= 3 && body[0] == 0xEF && body[1] == 0xBB && body[2] == 0xBF;
  final head = latin1
      .decode(body.sublist(hasBom ? 3 : 0, body.length.clamp(0, 1024)))
      .trimLeft()
      .toLowerCase();
  if (head.startsWith('{') || _feedRoot.hasMatch(head)) return false;
  return head.contains('<html') || head.contains('<!doctype html');
}

// <rss, <feed and <rdf:RDF roots, also namespace-prefixed (<atom:feed).
final _feedRoot = RegExp(r'<([\w.-]+:)?(rss|feed|rdf)[\s>/]');

/// Paths tried on a site whose page advertises no feed, in order.
const commonFeedPaths = [
  '/feed',
  '/rss',
  '/rss.xml',
  '/atom.xml',
  '/feed.xml',
  '/index.xml',
];

/// Feed address of a well-known page that needs no request: subreddits and
/// Reddit users (whose pages advertise no feed), YouTube channel ids and
/// playlists. Null for everything else — YouTube handles, Mastodon and
/// Bluesky profiles advertise their feed in the page and go through
/// discovery.
String? knownFeedUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last.endsWith('.rss')) return null;

  if (host == 'reddit.com' || host.endsWith('.reddit.com')) {
    if (segments.length < 2) return null;
    final kind = switch (segments[0].toLowerCase()) {
      'r' => 'r',
      'u' || 'user' => 'user',
      _ => null,
    };
    if (kind == null) return null;
    // A user's multireddit has its own feed.
    if (kind == 'user' && segments.length >= 4 && segments[2] == 'm') {
      return 'https://www.reddit.com/user/${segments[1]}/m/${segments[3]}/.rss';
    }
    return 'https://www.reddit.com/$kind/${segments[1]}/.rss';
  }

  if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
    final playlist = uri.queryParameters['list'];
    if (segments.firstOrNull == 'playlist' && playlist != null) {
      return 'https://www.youtube.com/feeds/videos.xml?playlist_id=$playlist';
    }
    if (segments.length >= 2 && segments[0] == 'channel') {
      return 'https://www.youtube.com/feeds/videos.xml?channel_id=${segments[1]}';
    }
  }
  return null;
}

const _feedTypes = {
  'application/rss+xml',
  'application/atom+xml',
  'application/rdf+xml',
  'application/feed+json',
};

/// The feeds a page advertises with `<link rel="alternate">`, in page
/// order without duplicates. Relative links resolve against `<base href>`
/// or [pageUrl] (the final URL after redirects); only http(s) is kept.
List<DiscoveredFeed> feedLinksInHtml(String html, Uri pageUrl) {
  final doc = parse(html);
  final baseHref = doc.querySelector('base[href]')?.attributes['href'];
  var base = pageUrl;
  if (baseHref != null) {
    try {
      base = pageUrl.resolve(baseHref.trim());
    } on FormatException {
      // A malformed <base> is ignored, as browsers do.
    }
  }
  final seen = <String>{};
  final feeds = <DiscoveredFeed>[];
  for (final link in doc.querySelectorAll('link[rel][href]')) {
    final rel = link.attributes['rel']!.toLowerCase().split(RegExp(r'\s+'));
    final type = link.attributes['type']?.split(';').first.toLowerCase().trim();
    if (!rel.contains('alternate') || !_feedTypes.contains(type)) continue;
    final Uri url;
    try {
      url = base.resolve(link.attributes['href']!.trim());
    } on FormatException {
      continue;
    }
    if (url.scheme != 'http' && url.scheme != 'https') continue;
    if (!seen.add(url.toString())) continue;
    final title = link.attributes['title']?.trim();
    feeds.add(
      DiscoveredFeed(
        url.toString(),
        title: title == null || title.isEmpty ? null : title,
      ),
    );
  }
  return feeds;
}
