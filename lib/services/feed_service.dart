import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/feed_item.dart';

/// Fetches and parses RSS and Atom feeds over HTTP.
///
/// Uses browser-like User-Agent headers to avoid Cloudflare 403 challenges.
/// Attempts RSS parsing first; falls back to Atom if RSS fails.
class FeedService {
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

  static final List<DateFormat> _rfc822Patterns = [
    // "Thu, 27 Feb 2026 12:00:00 +0000"
    DateFormat('EEE, dd MMM yyyy HH:mm:ss Z', 'en_US'),
    // "27 Feb 2026 12:00:00 +0000"  (no day-of-week)
    DateFormat('dd MMM yyyy HH:mm:ss Z', 'en_US'),
    // "Thu, 27 Feb 2026 12:00:00"  (no timezone)
    DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US'),
    // "27 Feb 2026 12:00:00"
    DateFormat('dd MMM yyyy HH:mm:ss', 'en_US'),
    // "Thu, 27 Feb 2026" (date only)
    DateFormat('EEE, dd MMM yyyy', 'en_US'),
    // "27 Feb 2026"
    DateFormat('dd MMM yyyy', 'en_US'),
  ];

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
  /// Returns a list of [FeedItem]s. Throws if the HTTP request fails or the
  /// response cannot be parsed as either RSS or Atom.
  Future<List<FeedItem>> fetchFeed(String url, String category) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _userAgent,
          'Accept': _acceptHeader,
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load RSS feed (Status: ${response.statusCode})',
        );
      }

      String bodyString;
      try {
        bodyString = utf8.decode(response.bodyBytes, allowMalformed: true);
      } catch (e) {
        bodyString = response.body;
      }

      try {
        final rssFeed = RssFeed.parse(bodyString);
        return _mapRssItems(rssFeed, category, url);
      } catch (e) {
        // Try parsing as Atom if RSS parsing fails
        try {
          final atomFeed = AtomFeed.parse(bodyString);
          return _mapAtomItems(atomFeed, category, url);
        } catch (e2) {
          throw Exception('Failed to parse RSS/Atom feed: $e2');
        }
      }
    } catch (e) {
      debugPrint('Error fetching feed $url: $e');
      throw Exception('Could not fetch or parse feed.');
    }
  }

  /// Maps RSS feed items to the universal [FeedItem] model.
  List<FeedItem> _mapRssItems(RssFeed feed, String category, String sourceUrl) {
    final siteName = _decodeHtmlEntities(feed.title ?? 'Unknown Site');

    return feed.items.map((item) {
      String content = item.content?.value ?? item.description ?? '';
      String description = _parseHtmlString(content);
      List<String> images = _extractImages(content);

      // Try to get image from enclosure if not found in content
      String? topImage = images.isNotEmpty ? images.first : null;
      if (topImage == null &&
          item.enclosure != null &&
          item.enclosure!.url != null) {
        if (item.enclosure!.type?.startsWith('image') ?? false) {
          topImage = item.enclosure!.url;
        }
      }

      return FeedItem(
        id: item.guid ?? item.link ?? DateTime.now().toIso8601String(),
        siteName: siteName,
        title: _decodeHtmlEntities(item.title ?? 'No Title'),
        description: description,
        timeAgo: '',
        siteIcon: Icons.rss_feed,
        iconColor: const Color(0xFF00A3FF),
        iconBackgroundColor: const Color(0x3300A3FF),
        link: item.link ?? '',
        imageUrl: topImage,
        content: content,
        pubDate: _parseRssDate(item.pubDate),
        category: category,
        feedUrl: sourceUrl,
      );
    }).toList();
  }

  /// Maps Atom feed entries to the universal [FeedItem] model.
  List<FeedItem> _mapAtomItems(
    AtomFeed feed,
    String category,
    String sourceUrl,
  ) {
    final siteName = _decodeHtmlEntities(feed.title ?? 'Unknown Site');

    return feed.items.map((item) {
      String content = item.content ?? item.summary ?? '';
      String description = _parseHtmlString(content);
      List<String> images = _extractImages(content);

      // YouTube uses <media:group><media:thumbnail url="...">
      if (images.isEmpty &&
          item.media != null &&
          item.media!.thumbnails.isNotEmpty) {
        final url = item.media!.thumbnails.first.url;
        if (url != null && url.isNotEmpty) {
          images.add(url);
        }
      }

      String? topImage = images.isNotEmpty ? images.first : null;

      String link = '';
      if (item.links.isNotEmpty) {
        link = item.links.first.href ?? '';
      }

      return FeedItem(
        id:
            item.id ??
            (link.isNotEmpty ? link : DateTime.now().toIso8601String()),
        siteName: siteName,
        title: _decodeHtmlEntities(item.title ?? 'No Title'),
        description: description,
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

  /// Strips HTML tags and returns plain text for the short description.
  String _parseHtmlString(String htmlString) {
    final document = parse(htmlString);
    final String parsedString =
        parse(document.body?.text ?? '').documentElement?.text ?? '';
    return parsedString.replaceAll('\n', ' ').trim();
  }

  /// Decodes HTML entities (e.g. `&#8216;`) in feed titles and site names.
  String _decodeHtmlEntities(String text) {
    if (text.isEmpty) return text;
    final document = parse(text);
    return document.documentElement?.text ?? text;
  }

  /// Extracts all `<img>` `src` attributes from HTML content.
  List<String> _extractImages(String htmlString) {
    final List<String> imageUrls = [];
    final document = parse(htmlString);
    final images = document.getElementsByTagName('img');
    for (final img in images) {
      final src = img.attributes['src'];
      if (src != null) {
        imageUrls.add(src);
      }
    }
    return imageUrls;
  }

  /// Parses dates from RSS/Atom feeds.
  ///
  /// Supports:
  ///  - ISO 8601 (e.g. `2026-02-27T12:00:00Z`)
  ///  - RFC 822 / RFC 2822 (e.g. `Thu, 27 Feb 2026 12:00:00 GMT`)
  ///  - Common variants with/without day-of-week or timezone abbreviations
  DateTime? _parseRssDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;

    final trimmed = dateStr.trim();

    // 1. Try ISO 8601 first (Atom feeds typically use this)
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    // 2. Replace common timezone abbreviations with numeric offsets
    String normalized = trimmed;
    for (final entry in _timezoneReplacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }

    // 3. Try RFC 822 / RFC 2822 patterns (pre-compiled static instances)
    for (final format in _rfc822Patterns) {
      try {
        return format.parse(normalized, true); // true = UTC
      } catch (_) {
        // Try next pattern
      }
    }

    return null;
  }
}
