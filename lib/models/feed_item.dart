import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;

/// Represents a single article/entry from an RSS or Atom feed.
///
/// Immutable value object that carries both display metadata (icon, colors,
/// read/bookmark state) and content fields (link, HTML body, publication date).
/// Serializable to/from JSON for Hive caching.
class FeedItem {
  final String id;
  final String siteName;
  final String title;
  final String description;
  final String timeAgo;
  final bool isBookmarked;
  final bool isRead;
  final IconData siteIcon;
  final Color iconColor;
  final Color iconBackgroundColor;

  // Feed content fields
  final String link;
  final String? imageUrl;
  final String? content;
  final DateTime? pubDate;
  final String category;
  final String feedUrl;

  FeedItem({
    required this.id,
    required this.siteName,
    required this.title,
    required this.description,
    required this.timeAgo,
    this.isBookmarked = false,
    this.isRead = false,
    required this.siteIcon,
    required this.iconColor,
    required this.iconBackgroundColor,
    this.link = '',
    this.imageUrl,
    this.content,
    this.pubDate,
    this.category = 'Uncategorized',
    this.feedUrl = '',
  });

  FeedItem copyWith({
    String? id,
    String? siteName,
    String? title,
    String? description,
    String? timeAgo,
    bool? isBookmarked,
    bool? isRead,
    IconData? siteIcon,
    Color? iconColor,
    Color? iconBackgroundColor,
    String? link,
    String? imageUrl,
    String? content,
    DateTime? pubDate,
    String? category,
    String? feedUrl,
  }) {
    return FeedItem(
      id: id ?? this.id,
      siteName: siteName ?? this.siteName,
      title: title ?? this.title,
      description: description ?? this.description,
      timeAgo: timeAgo ?? this.timeAgo,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isRead: isRead ?? this.isRead,
      siteIcon: siteIcon ?? this.siteIcon,
      iconColor: iconColor ?? this.iconColor,
      iconBackgroundColor: iconBackgroundColor ?? this.iconBackgroundColor,
      link: link ?? this.link,
      imageUrl: imageUrl ?? this.imageUrl,
      content: content ?? this.content,
      pubDate: pubDate ?? this.pubDate,
      category: category ?? this.category,
      feedUrl: feedUrl ?? this.feedUrl,
    );
  }

  /// Serializes this item to a JSON-compatible map for Hive persistence.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'siteName': siteName,
      'title': title,
      'description': description,
      'timeAgo': timeAgo,
      'isBookmarked': isBookmarked,
      'isRead': isRead,
      'siteIconCodePoint': siteIcon.codePoint,
      'siteIconFontFamily': siteIcon.fontFamily,
      'siteIconFontPackage': siteIcon.fontPackage,
      'iconColor': iconColor.toARGB32(),
      'iconBackgroundColor': iconBackgroundColor.toARGB32(),
      'link': link,
      'imageUrl': imageUrl,
      'content': content,
      'pubDate': pubDate?.toIso8601String(),
      'category': category,
      'feedUrl': feedUrl,
    };
  }

  /// Deserializes a [FeedItem] from a JSON map.
  ///
  /// All fields are null-safe with sensible defaults so that partially saved
  /// or legacy cache entries don't crash the app.
  factory FeedItem.fromJson(Map<String, dynamic> json) {
    return FeedItem(
      id: json['id'] as String? ?? '',
      siteName: _decodeHtml(json['siteName'] as String? ?? 'Unknown'),
      title: _decodeHtml(json['title'] as String? ?? 'No Title'),
      description: json['description'] as String? ?? '',
      timeAgo: json['timeAgo'] as String? ?? '',
      isBookmarked: json['isBookmarked'] as bool? ?? false,
      isRead: json['isRead'] as bool? ?? false,
      siteIcon: _decodeIconData(json['siteIconCodePoint'] as int?),
      iconColor: Color(json['iconColor'] as int? ?? 0xFF12A8FF),
      iconBackgroundColor: Color(
        json['iconBackgroundColor'] as int? ?? 0xFF12A8FF,
      ),
      link: json['link'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      content: json['content'] as String?,
      pubDate: json['pubDate'] != null
          ? DateTime.tryParse(json['pubDate'] as String)
          : null,
      category: json['category'] as String? ?? 'Uncategorized',
      feedUrl: json['feedUrl'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FeedItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Decodes HTML entities (e.g. `&#8216;`) in [text].
  static String _decodeHtml(String text) {
    if (text.isEmpty) return text;
    try {
      return parse(text).documentElement?.text ?? text;
    } catch (_) {
      return text;
    }
  }

  /// Maps a saved codepoint back to a `const IconData`.
  /// This prevents tree-shaking errors in release builds.
  static IconData _decodeIconData(int? codePoint) {
    if (codePoint == Icons.rss_feed.codePoint) return Icons.rss_feed;
    // Fallback icon
    return Icons.rss_feed;
  }
}
