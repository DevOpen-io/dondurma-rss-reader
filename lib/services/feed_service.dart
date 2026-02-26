import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:html/parser.dart' show parse;
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
      return [];
    }
  }

  List<FeedItem> _mapRssItems(RssFeed feed, String category, String sourceUrl) {
    final siteName = feed.title ?? 'Unknown Site';

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
        title: item.title ?? 'No Title',
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
    final siteName = feed.title ?? 'Unknown Site';

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
        title: item.title ?? 'No Title',
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

  // Helper to parse dates simply
  DateTime? _parseRssDate(String? dateStr) {
    if (dateStr == null) return null;

    // By default, dart_rss doesn't return DateTime objects directly.
    // Let's try to pass the string back or do a best-effort parse for Atom feeds
    return DateTime.tryParse(dateStr);
  }
}
