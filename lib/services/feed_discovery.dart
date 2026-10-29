import 'package:html/parser.dart' show parse;

/// A feed address found for a page the user entered.
class DiscoveredFeed {
  const DiscoveredFeed(this.url, {this.title});

  final String url;

  /// The page's own label for the feed (`<link title>`), when it has one.
  final String? title;
}

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
  final base = baseHref == null ? pageUrl : pageUrl.resolve(baseHref);
  final seen = <String>{};
  final feeds = <DiscoveredFeed>[];
  for (final link in doc.querySelectorAll('link[rel][href]')) {
    final rel = link.attributes['rel']!.toLowerCase().split(RegExp(r'\s+'));
    final type = link.attributes['type']?.toLowerCase().trim();
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
