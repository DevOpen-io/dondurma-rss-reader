import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;

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

  // New fields for real data
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

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    String decodeHtml(String text) {
      if (text.isEmpty) return text;
      try {
        return parse(text).documentElement?.text ?? text;
      } catch (_) {
        return text;
      }
    }

    return FeedItem(
      id: json['id'] as String? ?? '',
      siteName: decodeHtml(json['siteName'] as String? ?? 'Unknown'),
      title: decodeHtml(json['title'] as String? ?? 'No Title'),
      description: json['description'] as String? ?? '',
      timeAgo: json['timeAgo'] as String? ?? '',
      isBookmarked: json['isBookmarked'] as bool? ?? false,
      isRead: json['isRead'] as bool? ?? false,
      siteIcon: IconData(
        json['siteIconCodePoint'] as int? ?? Icons.rss_feed.codePoint,
        fontFamily: json['siteIconFontFamily'] as String? ?? 'MaterialIcons',
        fontPackage: json['siteIconFontPackage'] as String?,
      ),
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
}
