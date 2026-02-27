import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/feed_item.dart';

class FeedService {
  Future<List<FeedItem>> fetchFeed(String url, String category) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept':
              'application/rss+xml, application/rdf+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.9',
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
        timeAgo: '', // Will be calculated by UI based on pubDate
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

  // Helper to strip HTML tags for the short description
  String _parseHtmlString(String htmlString) {
    final document = parse(htmlString);
    final String parsedString =
        parse(document.body?.text ?? '').documentElement?.text ?? '';
    return parsedString.replaceAll('\n', ' ').trim();
  }

  // Helper to decode HTML entities like &#8216;
  String _decodeHtmlEntities(String text) {
    if (text.isEmpty) return text;
    final document = parse(text);
    return document.documentElement?.text ?? text;
  }

  // Helper to extract all <img> src attributes from HTML content
  List<String> _extractImages(String htmlString) {
    List<String> imageUrls = [];
    final document = parse(htmlString);
    final images = document.getElementsByTagName('img');
    for (var img in images) {
      if (img.attributes.containsKey('src')) {
        imageUrls.add(img.attributes['src']!);
      }
    }
    return imageUrls;
  }

  // Helper to parse dates from RSS/Atom feeds.
  //
  // Supports:
  //  - ISO 8601 (e.g. "2026-02-27T12:00:00Z")
  //  - RFC 822 / RFC 2822 (e.g. "Thu, 27 Feb 2026 12:00:00 GMT")
  //  - Common variants with/without day-of-week or timezone abbreviations
  DateTime? _parseRssDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;

    final trimmed = dateStr.trim();

    // 1. Try ISO 8601 first (Atom feeds typically use this)
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    // 2. Strip common timezone abbreviations and replace with offset
    String normalized = trimmed
        .replaceAll(RegExp(r'\s+GMT$', caseSensitive: false), ' +0000')
        .replaceAll(RegExp(r'\s+UTC$', caseSensitive: false), ' +0000')
        .replaceAll(RegExp(r'\s+EST$', caseSensitive: false), ' -0500')
        .replaceAll(RegExp(r'\s+EDT$', caseSensitive: false), ' -0400')
        .replaceAll(RegExp(r'\s+CST$', caseSensitive: false), ' -0600')
        .replaceAll(RegExp(r'\s+CDT$', caseSensitive: false), ' -0500')
        .replaceAll(RegExp(r'\s+MST$', caseSensitive: false), ' -0700')
        .replaceAll(RegExp(r'\s+MDT$', caseSensitive: false), ' -0600')
        .replaceAll(RegExp(r'\s+PST$', caseSensitive: false), ' -0800')
        .replaceAll(RegExp(r'\s+PDT$', caseSensitive: false), ' -0700');

    // 3. Try RFC 822 / RFC 2822 patterns
    final rfc822Patterns = [
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

    for (final format in rfc822Patterns) {
      try {
        return format.parse(normalized, true); // true = UTC
      } catch (_) {
        // Try next pattern
      }
    }

    return null;
  }
}
