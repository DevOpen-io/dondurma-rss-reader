import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart' show parse;
import 'package:xml/xml.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../models/feed_item.dart';
import 'article_identity.dart';

/// Why a feed fetch failed — lets health reporting tell a dead feed apart
/// from a dead network.
enum FeedFetchErrorKind { connectivity, httpStatus, parse, other }

class FeedFetchException implements Exception {
  FeedFetchException(this.kind, this.message);

  final FeedFetchErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Fetches and parses RSS and Atom feeds over HTTP.
///
/// Uses browser-like User-Agent headers to avoid Cloudflare 403 challenges.
/// Attempts RSS parsing first; falls back to Atom if RSS fails.
class FeedService {
  // ---------------------------------------------------------------------------
  // Shared HTTP client — reuses connections (TCP keep-alive) across all feeds.
  // One instance per FeedService lifetime; closed in FeedProvider.dispose().
  // ---------------------------------------------------------------------------

  final http.Client _client;

  FeedService() : _client = http.Client();

  void dispose() => _client.close();

  /// Max items kept per feed. Some feeds expose large archives (hundreds of
  /// entries); keeping only the most recent slice bounds memory, the unread
  /// counts, and the size of the merged in-memory list.
  static const int maxItemsPerFeed = 50;

  /// Returns at most [maxItemsPerFeed] most-recent items. Sorts by descending
  /// publication date only when the cap is exceeded — feeds are conventionally
  /// reverse-chronological, but that is not guaranteed.
  static List<FeedItem> capItems(List<FeedItem> items) {
    if (items.length <= maxItemsPerFeed) return items;
    final sorted = items.toList()
      ..sort((a, b) {
        if (a.pubDate == null && b.pubDate == null) return 0;
        if (a.pubDate == null) return 1;
        if (b.pubDate == null) return -1;
        return b.pubDate!.compareTo(a.pubDate!);
      });
    return sorted.take(maxItemsPerFeed).toList();
  }

  /// Stable synthetic ID for feed items exposing neither a guid nor a link.
  /// Derived from feed URL + title + raw date so the same article keeps the same
  /// ID across fetches. Using `DateTime.now()` here would mint a fresh ID every
  /// refresh, breaking read-state tracking and re-triggering notifications.
  static String fallbackId(String feedUrl, String? title, String? rawDate) =>
      ArticleIdentity.fallbackId(feedUrl, title, rawDate);

  // ---------------------------------------------------------------------------
  // HTTP header constants
  // ---------------------------------------------------------------------------

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36';

  static const _acceptHeader =
      'application/rss+xml, application/rdf+xml, '
      'application/atom+xml, application/xml, '
      'text/xml, text/html;q=0.9';

  // ---------------------------------------------------------------------------
  // Pre-compiled RFC 822 date format patterns (avoids re-creating per call)
  // ---------------------------------------------------------------------------

  // Patterns WITHOUT timezone — tz offset is stripped and applied manually
  // because intl's DateFormat parses but does NOT apply +HHMM offsets.
  static final List<DateFormat> _rfc822Patterns = [
    DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US'),
    DateFormat('dd MMM yyyy HH:mm:ss', 'en_US'),
    DateFormat('EEE, dd MMM yyyy', 'en_US'),
    DateFormat('dd MMM yyyy', 'en_US'),
  ];

  static final _tzOffsetRegex = RegExp(r'\s*([+-])(\d{2})(\d{2})\s*$');

  // ---------------------------------------------------------------------------
  // Timezone abbreviation → offset mapping for RFC 822 normalization
  // ---------------------------------------------------------------------------

  static final _timezoneReplacements = <RegExp, String>{
    RegExp(r'\s+GMT$', caseSensitive: false): ' +0000',
    RegExp(r'\s+UTC$', caseSensitive: false): ' +0000',
    RegExp(r'\s+EST$', caseSensitive: false): ' -0500',
    RegExp(r'\s+EDT$', caseSensitive: false): ' -0400',
    RegExp(r'\s+CST$', caseSensitive: false): ' -0600',
    RegExp(r'\s+CDT$', caseSensitive: false): ' -0500',
    RegExp(r'\s+MST$', caseSensitive: false): ' -0700',
    RegExp(r'\s+MDT$', caseSensitive: false): ' -0600',
    RegExp(r'\s+PST$', caseSensitive: false): ' -0800',
    RegExp(r'\s+PDT$', caseSensitive: false): ' -0700',
  };

  /// Fetches and parses the feed at [url], tagging each item with [category].
  ///
  /// When [etag] or [lastModified] from a previous fetch are supplied, the
  /// request is made conditional (`If-None-Match` / `If-Modified-Since`). A
  /// `304 Not Modified` returns a [FeedFetchResult.notModified] with no body to
  /// parse, so unchanged feeds cost almost nothing on every refresh cycle.
  ///
  /// Throws if the HTTP request fails or the response cannot be parsed as either
  /// RSS or Atom.
  Future<FeedFetchResult> fetchFeed(
    String url,
    String category, {
    String? etag,
    String? lastModified,
  }) async {
    try {
      final headers = <String, String>{
        'User-Agent': _userAgent,
        'Accept': _acceptHeader,
        'Accept-Language': 'en-US,en;q=0.9',
      };
      if (etag != null) headers['If-None-Match'] = etag;
      if (lastModified != null) headers['If-Modified-Since'] = lastModified;

      // Follow redirects manually (max 5 hops) — package:http's auto-follow
      // hides the final URL, but learning it lets callers skip the hop.
      var currentUrl = url;
      http.StreamedResponse? streamed;
      for (var hops = 0; hops < 5; hops++) {
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers.addAll(headers);
        final next = await _client
            .send(request)
            .timeout(const Duration(seconds: 10));
        final location = next.headers['location'];
        if (next.isRedirect && location != null) {
          await next.stream.drain();
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
          continue;
        }
        streamed = next;
        break;
      }
      if (streamed == null) {
        throw FeedFetchException(
          FeedFetchErrorKind.httpStatus,
          'Failed to load RSS feed (redirect limit exceeded)',
        );
      }
      final statusCode = streamed.statusCode;
      final responseHeaders = streamed.headers;
      final bodyBytes = await streamed.stream.toBytes();

      // A differing final URL means the feed moved — callers learn it and
      // skip the redirect round-trip on the next cycle.
      final finalUrl = currentUrl != url ? currentUrl : null;

      // Content unchanged since the validators we sent — no body returned.
      if (statusCode == 304) {
        return FeedFetchResult.notModified(
          etag: etag,
          lastModified: lastModified,
          finalUrl: finalUrl,
        );
      }
      if (statusCode != 200) {
        throw FeedFetchException(
          FeedFetchErrorKind.httpStatus,
          'Failed to load RSS feed (Status: $statusCode)',
        );
      }

      final newEtag = responseHeaders['etag'];
      final newLastModified = responseHeaders['last-modified'];

      // Decode + XML parse + per-item HTML parse in a background isolate —
      // with many feeds this work caused jank on the main thread during sync.
      final items = await compute(parseFeedBody, (
        bodyBytes: bodyBytes,
        category: category,
        url: url,
      ));
      return FeedFetchResult(
        items: items,
        etag: newEtag,
        lastModified: newLastModified,
        finalUrl: finalUrl,
      );
    } catch (e) {
      debugPrint('Error fetching feed $url: $e');
      if (e is FeedFetchException) rethrow;
      if (e is SocketException ||
          e is http.ClientException ||
          e is TimeoutException ||
          e is HandshakeException ||
          e is TlsException) {
        throw FeedFetchException(
          FeedFetchErrorKind.connectivity,
          'Network error: $e',
        );
      }
      throw FeedFetchException(
        FeedFetchErrorKind.other,
        'Could not fetch or parse feed: $e',
      );
    }
  }

  /// Decodes and parses a raw feed body into capped [FeedItem]s.
  ///
  /// Static and side-effect free so it can run in a background isolate via
  /// [compute]. Attempts RSS first, then falls back to Atom.
  static List<FeedItem> parseFeedBody(
    ({Uint8List bodyBytes, String category, String url}) request,
  ) {
    final bodyString = _decodeBody(request.bodyBytes);

    // JSON Feed (jsonfeed.org v1/v1.1) — a JSON document, not XML.
    if (bodyString.trimLeft().startsWith('{')) {
      return capItems(
        _mapJsonFeedItems(bodyString, request.category, request.url),
      );
    }

    // RSS 1.0/RDF parses as an "empty" RSS 2.0 feed — detect the root element
    // and route it to the dedicated parser instead of returning zero items.
    final isRdf = bodyString.contains('<rdf:RDF');

    try {
      final rssFeed = RssFeed.parse(bodyString);
      if (isRdf && rssFeed.items.isEmpty) {
        return capItems(
          _mapRss1Items(
            Rss1Feed.parse(bodyString),
            request.category,
            request.url,
          ),
        );
      }
      return capItems(_mapRssItems(rssFeed, request.category, request.url));
    } catch (e) {
      if (isRdf) {
        try {
          return capItems(
            _mapRss1Items(
              Rss1Feed.parse(bodyString),
              request.category,
              request.url,
            ),
          );
        } catch (_) {
          // Fall through to Atom for a consistent parse error below.
        }
      }
      // Try parsing as Atom if RSS parsing fails
      try {
        final atomFeed = AtomFeed.parse(bodyString);
        return capItems(
          _mapAtomItems(
            atomFeed,
            request.category,
            request.url,
            xhtmlContents: _xhtmlContents(bodyString),
          ),
        );
      } catch (e2) {
        // Namespace-prefixed Atom (<atom:feed>) — strip the atom: tag prefix
        // and retry once before declaring the feed unparseable.
        if (bodyString.contains('<atom:feed')) {
          try {
            final stripped = bodyString
                .replaceAll('<atom:', '<')
                .replaceAll('</atom:', '</');
            final atomFeed = AtomFeed.parse(stripped);
            return capItems(
              _mapAtomItems(
                atomFeed,
                request.category,
                request.url,
                xhtmlContents: _xhtmlContents(stripped),
              ),
            );
          } catch (_) {
            // Fall through to the parse error below.
          }
        }
        throw FeedFetchException(
          FeedFetchErrorKind.parse,
          'Failed to parse RSS/Atom feed: $e2',
        );
      }
    }
  }

  /// Decodes a feed body with a BOM/charset sniff: UTF-16 (via BOM), strict
  /// UTF-8, then ISO-8859-1 for legacy feeds that declare a non-UTF encoding.
  static String _decodeBody(Uint8List bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return String.fromCharCodes(_utf16Units(bytes, bigEndian: false));
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return String.fromCharCodes(_utf16Units(bytes, bigEndian: true));
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static Iterable<int> _utf16Units(Uint8List b, {required bool bigEndian}) {
    return Iterable.generate((b.length - 2) ~/ 2, (i) {
      final lo = b[2 + i * 2];
      final hi = b[2 + i * 2 + 1];
      return bigEndian ? (lo << 8) | hi : lo | (hi << 8);
    });
  }

  /// Maps RSS feed items to the universal [FeedItem] model.
  static List<FeedItem> _mapRssItems(
    RssFeed feed,
    String category,
    String sourceUrl,
  ) {
    final siteName = ArticleIdentity.sanitizeSiteTitle(
      _decodeHtmlEntities(feed.title ?? 'Unknown Site'),
    );

    return feed.items.map((item) {
      final content = item.content?.value ?? item.description ?? '';
      // Parse HTML once; reuse the document for both description and images.
      final parsed = _parseContent(content);

      // Try to get image from enclosure if not found in content
      String? topImage = parsed.images.isNotEmpty ? parsed.images.first : null;
      if (topImage == null &&
          item.enclosure != null &&
          item.enclosure!.url != null) {
        if (item.enclosure!.type?.startsWith('image') ?? false) {
          topImage = item.enclosure!.url;
        }
      }
      // MediaRSS in RSS 2.0 items (Flickr, NASA, many news feeds).
      if (topImage == null &&
          item.media != null &&
          item.media!.thumbnails.isNotEmpty) {
        topImage = item.media!.thumbnails.first.url;
      }

      final guid = ArticleIdentity.nonEmpty(item.guid);
      final rawLink = _resolveFeedRelativeUrl(item.link, sourceUrl);
      final link = ArticleIdentity.normalizeArticleUrl(rawLink);
      return FeedItem(
        id: guid ?? link ?? fallbackId(sourceUrl, item.title, item.pubDate),
        siteName: siteName,
        title: _decodeHtmlEntities(item.title ?? 'No Title'),
        description: parsed.text,
        timeAgo: '',
        siteIcon: Icons.rss_feed,
        iconColor: const Color(0xFF00A3FF),
        iconBackgroundColor: const Color(0x3300A3FF),
        link: rawLink ?? '',
        imageUrl: topImage,
        content: content,
        // Dublin Core dc:date covers feeds without <pubDate> (WordPress
        // /feed/rdf, Mastodon, older Movable Type exports).
        pubDate: _parseRssDate(item.pubDate ?? item.dc?.date),
        category: category,
        feedUrl: sourceUrl,
      );
    }).toList();
  }

  /// Maps RSS 1.0/RDF items — `<item>` is a sibling of `<channel>` in RDF, so
  /// RssFeed finds the channel but zero items; Rss1Feed reads the real set.
  static List<FeedItem> _mapRss1Items(
    Rss1Feed feed,
    String category,
    String sourceUrl,
  ) {
    final siteName = ArticleIdentity.sanitizeSiteTitle(
      _decodeHtmlEntities(feed.title ?? 'Unknown Site'),
    );

    return feed.items.map((item) {
      final content = item.content?.value ?? item.description ?? '';
      final parsed = _parseContent(content);
      final rawLink = _resolveFeedRelativeUrl(item.link, sourceUrl);
      final link = ArticleIdentity.normalizeArticleUrl(rawLink);
      return FeedItem(
        id: link ?? fallbackId(sourceUrl, item.title, item.dc?.date),
        siteName: siteName,
        title: _decodeHtmlEntities(item.title ?? 'No Title'),
        description: parsed.text,
        timeAgo: '',
        siteIcon: Icons.rss_feed,
        iconColor: const Color(0xFF00A3FF),
        iconBackgroundColor: const Color(0x3300A3FF),
        link: rawLink ?? '',
        imageUrl: parsed.images.isNotEmpty ? parsed.images.first : null,
        content: content,
        pubDate: _parseRssDate(item.dc?.date),
        category: category,
        feedUrl: sourceUrl,
      );
    }).toList();
  }

  /// Resolves a possibly-relative feed URL against the feed's own URL.
  /// Relative `<link>` values would otherwise be stored verbatim and produce
  /// broken article links and unstable item ids.
  static String? _resolveFeedRelativeUrl(String? url, String sourceUrl) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final resolved = Uri.tryParse(sourceUrl)?.resolve(url);
    return resolved?.toString() ?? url;
  }

  /// Maps Atom feed entries to the universal [FeedItem] model.
  static List<FeedItem> _mapAtomItems(
    AtomFeed feed,
    String category,
    String sourceUrl, {
    Map<int, String>? xhtmlContents,
  }) {
    final siteName = ArticleIdentity.sanitizeSiteTitle(
      _decodeHtmlEntities(feed.title ?? 'Unknown Site'),
    );

    return feed.items.indexed.map((entry) {
      final (index, item) = entry;
      // dart_rss reads <content> via innerText — for type="xhtml" that strips
      // the real markup (and every <img>). The parallel-parse map restores it.
      final content =
          xhtmlContents?[index] ?? item.content ?? item.summary ?? '';
      // Parse HTML once; reuse the document for both description and images.
      final parsed = _parseContent(content);

      // YouTube uses <media:group><media:thumbnail url="..."> — dart_rss
      // only surfaces entry-level media:thumbnail (Group drops thumbnails),
      // so group thumbnails are derived from the video URL below.
      List<String> images = parsed.images;
      if (images.isEmpty &&
          item.media != null &&
          item.media!.thumbnails.isNotEmpty) {
        final url = item.media!.thumbnails.first.url;
        if (url != null && url.isNotEmpty) {
          images = [url];
        }
      }

      String? topImage = images.isNotEmpty ? images.first : null;

      String link = '';
      if (item.links.isNotEmpty) {
        // Entries may carry several links (self, alternate, enclosure…);
        // the article link is the alternate (or unrel'd) one, not first.
        final articleLink = item.links.firstWhere(
          (l) => l.rel == 'alternate' || l.rel == null,
          orElse: () => item.links.first,
        );
        link = articleLink.href ?? '';
      }
      link = _resolveFeedRelativeUrl(link, sourceUrl) ?? '';

      // YouTube feeds carry no usable image — derive the thumbnail from the
      // canonical video URL pattern instead of leaving articles imageless.
      if (topImage == null) {
        final videoId = _youtubeVideoId(link);
        if (videoId != null) {
          topImage = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        }
      }

      final atomId = ArticleIdentity.nonEmpty(item.id);
      final normalizedLink = ArticleIdentity.normalizeArticleUrl(link);
      return FeedItem(
        id:
            atomId ??
            normalizedLink ??
            fallbackId(sourceUrl, item.title, item.updated ?? item.published),
        siteName: siteName,
        title: _decodeHtmlEntities(item.title ?? 'No Title'),
        description: parsed.text,
        timeAgo: '',
        siteIcon: Icons.rss_feed,
        iconColor: const Color(0xFF00A3FF),
        iconBackgroundColor: const Color(0x3300A3FF),
        link: link,
        imageUrl: topImage,
        content: content.isEmpty ? (item.title ?? '') : content,
        pubDate: _parseRssDate(item.updated ?? item.published),
        category: category,
        feedUrl: sourceUrl,
      );
    }).toList();
  }

  /// Maps a JSON Feed (jsonfeed.org v1/v1.1) document to [FeedItem]s.
  /// Throws a parse-kind [FeedFetchException] when the document is not a
  /// JSON Feed at all — keeps the "JSON body is a parse error" contract.
  static List<FeedItem> _mapJsonFeedItems(
    String body,
    String category,
    String sourceUrl,
  ) {
    final dynamic doc;
    try {
      doc = jsonDecode(body);
    } catch (_) {
      throw FeedFetchException(
        FeedFetchErrorKind.parse,
        'Failed to parse feed: body looks like JSON but is not valid JSON',
      );
    }
    if (doc is! Map ||
        !(doc['version'] as String? ?? '').contains('jsonfeed.org') ||
        doc['items'] is! List) {
      throw FeedFetchException(
        FeedFetchErrorKind.parse,
        'Failed to parse feed: JSON is not a JSON Feed document',
      );
    }
    final siteName = ArticleIdentity.sanitizeSiteTitle(
      _decodeHtmlEntities(doc['title'] as String? ?? 'Unknown Site'),
    );

    return (doc['items'] as List).whereType<Map>().map((raw) {
      final item = raw.cast<String, dynamic>();
      final content =
          (item['content_html'] as String?) ??
          (item['content_text'] as String?) ??
          '';
      final parsed = _parseContent(content);

      String? image =
          ArticleIdentity.nonEmpty(item['image'] as String?) ??
          ArticleIdentity.nonEmpty(item['banner_image'] as String?);
      if (image == null && item['attachments'] is List) {
        for (final att in (item['attachments'] as List).whereType<Map>()) {
          if ((att['mime_type'] as String? ?? '').startsWith('image/') &&
              att['url'] is String) {
            image = att['url'] as String;
            break;
          }
        }
      }
      image ??= parsed.images.isNotEmpty ? parsed.images.first : null;
      image = _resolveFeedRelativeUrl(image, sourceUrl);

      final link =
          _resolveFeedRelativeUrl(
            item['url'] as String? ?? item['external_url'] as String?,
            sourceUrl,
          ) ??
          '';
      final id =
          ArticleIdentity.nonEmpty(item['id'] as String?) ??
          ArticleIdentity.normalizeArticleUrl(link) ??
          fallbackId(
            sourceUrl,
            item['title'] as String?,
            item['date_published'] as String?,
          );
      final pubDate = DateTime.tryParse(
        item['date_published'] as String? ??
            item['date_modified'] as String? ??
            '',
      );
      final title = ArticleIdentity.nonEmpty(item['title'] as String?);
      return FeedItem(
        id: id,
        siteName: siteName,
        title: _decodeHtmlEntities(title ?? 'No Title'),
        description:
            ArticleIdentity.nonEmpty(item['summary'] as String?) ?? parsed.text,
        timeAgo: '',
        siteIcon: Icons.rss_feed,
        iconColor: const Color(0xFF00A3FF),
        iconBackgroundColor: const Color(0x3300A3FF),
        link: link,
        imageUrl: image,
        content: content.isEmpty ? (title ?? '') : content,
        pubDate: pubDate,
        category: category,
        feedUrl: sourceUrl,
      );
    }).toList();
  }

  /// Extracts `type="xhtml"` Atom content per entry index — dart_rss flattens
  /// it to innerText, dropping markup and images. Returns null fast when no
  /// xhtml content is present or the re-parse fails.
  static Map<int, String>? _xhtmlContents(String body) {
    if (!body.contains('type="xhtml"')) return null;
    try {
      final doc = XmlDocument.parse(body);
      XmlElement? feed;
      for (final el in doc.findAllElements('feed')) {
        feed = el;
        break;
      }
      if (feed == null) return null;
      final result = <int, String>{};
      var index = 0;
      for (final entry in feed.findElements('entry')) {
        for (final c in entry.findElements('content')) {
          if (c.getAttribute('type') == 'xhtml') {
            final inner = c.innerXml.trim();
            if (inner.isNotEmpty) result[index] = inner;
          }
        }
        index++;
      }
      return result.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  /// Parses [htmlString] once and extracts both plain text and image URLs.
  ///
  /// Avoids re-parsing the same HTML twice (old code called parse() 3-4× per item).
  static _ParsedContent _parseContent(String htmlString) {
    if (htmlString.isEmpty) return const _ParsedContent('', []);
    final document = parse(htmlString);
    final text = (document.body?.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final images = document
        .getElementsByTagName('img')
        .map((img) => img.attributes['src'])
        .whereType<String>()
        .toList();
    return _ParsedContent(text, images);
  }

  /// Extracts the video id from common YouTube URL shapes
  /// (`youtu.be/<id>`, `youtube.com|music.youtube.com|youtube-nocookie.com`
  /// with `watch?v=`, `/shorts/`, `/embed/` or `/live/`).
  static String? _youtubeVideoId(String link) {
    final uri = Uri.tryParse(link);
    final host = uri?.host.replaceFirst('www.', '') ?? '';
    if (host == 'youtu.be') {
      final id = uri!.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      return id.isEmpty ? null : id;
    }
    const youtubeHosts = {
      'youtube.com',
      'm.youtube.com',
      'music.youtube.com',
      'youtube-nocookie.com',
    };
    if (youtubeHosts.contains(host)) {
      final segments = uri!.pathSegments;
      const idPaths = {'shorts', 'embed', 'live', 'v'};
      if (idPaths.contains(segments.firstOrNull) &&
          segments.length > 1 &&
          segments[1].isNotEmpty) {
        return segments[1];
      }
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Decodes HTML entities (e.g. `&#8216;`) in feed titles and site names.
  static String _decodeHtmlEntities(String text) {
    // Fast path: no '&' means no entities — skip the full HTML parse.
    if (text.isEmpty || !text.contains('&')) return text;
    final document = parse(text);
    return document.documentElement?.text ?? text;
  }

  /// Parses dates from RSS/Atom feeds.
  ///
  /// Supports:
  ///  - ISO 8601 (e.g. `2026-02-27T12:00:00Z`)
  ///  - RFC 822 / RFC 2822 (e.g. `Thu, 27 Feb 2026 12:00:00 GMT`)
  static DateTime? _parseRssDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;

    final trimmed = dateStr.trim();

    // 1. ISO 8601 — DateTime.parse handles timezone correctly
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    // 2. Replace timezone abbreviations (GMT, EST…) with numeric offsets
    String normalized = trimmed;
    for (final entry in _timezoneReplacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }

    // 3. Extract numeric tz offset and strip it before parsing.
    //    intl's DateFormat reads but does NOT apply +HHMM offsets.
    int offsetMinutes = 0;
    final tzMatch = _tzOffsetRegex.firstMatch(normalized);
    if (tzMatch != null) {
      final sign = tzMatch.group(1) == '+' ? 1 : -1;
      final h = int.parse(tzMatch.group(2)!);
      final m = int.parse(tzMatch.group(3)!);
      offsetMinutes = sign * (h * 60 + m);
      normalized = normalized.substring(0, tzMatch.start).trim();
    }

    // 4. Parse datetime as UTC, then subtract the offset to get true UTC
    for (final format in _rfc822Patterns) {
      try {
        final dt = format.parse(normalized, true);
        return dt.subtract(Duration(minutes: offsetMinutes));
      } catch (_) {}
    }

    return null;
  }
}

/// Outcome of a single [FeedService.fetchFeed] call.
///
/// Carries HTTP cache validators (ETag / Last-Modified) so the next request can
/// be made conditional and an unchanged feed can short-circuit with [notModified].
class FeedFetchResult {
  /// Parsed items. Empty when [notModified] (the caller reuses its own copy).
  final List<FeedItem> items;

  /// Validators echoed back for persistence. For a 304 these are the same ones
  /// that were sent; for a 200 they come from the fresh response (may be null).
  final String? etag;
  final String? lastModified;

  /// True when the server returned `304 Not Modified`.
  final bool notModified;

  /// The URL the request actually ended at after redirects, when it differs
  /// from the requested URL. Lets callers learn permanent feed moves.
  final String? finalUrl;

  const FeedFetchResult({
    this.items = const [],
    this.etag,
    this.lastModified,
    this.notModified = false,
    this.finalUrl,
  });

  const FeedFetchResult.notModified({
    this.etag,
    this.lastModified,
    this.finalUrl,
  }) : items = const [],
       notModified = true;
}

/// Plain text + image list extracted from a single HTML parse.
class _ParsedContent {
  final String text;
  final List<String> images;
  const _ParsedContent(this.text, this.images);
}
