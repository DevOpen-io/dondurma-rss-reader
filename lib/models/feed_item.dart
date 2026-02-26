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

// Dummy data remains for now
final List<FeedItem> dummyTodayFeeds = [
  FeedItem(
    id: '1',
    siteName: 'TechCrunch',
    title: 'New AI Model Released: Promises 99% Accuracy',
    description:
        'The latest model promises to revolutionize code generation with unprecedented precision...',
    timeAgo: '2m ago',
    siteIcon: Icons.rss_feed,
    iconColor: const Color(0xFFFF9800),
    iconBackgroundColor: const Color(0x33FF9800),
  ),
  FeedItem(
    id: '2',
    siteName: 'The Verge',
    title: 'VR Headset Review: A Deep Dive into Ergonomics',
    description:
        'Is this the breakthrough we\'ve been waiting for? We spent 200 hours testing...',
    timeAgo: '15m ago',
    siteIcon: Icons.view_in_ar,
    iconColor: const Color(0xFF00E5FF),
    iconBackgroundColor: const Color(0x3300E5FF),
  ),
  FeedItem(
    id: '3',
    siteName: 'Hacker News',
    title: 'Rust 1.75 Released: Async traits are stable',
    description:
        'Async traits in traits are finally stable. Check out the full changelog for all the details...',
    timeAgo: '1h ago',
    siteIcon: Icons.developer_mode,
    iconColor: const Color(0xFFB0BEC5),
    iconBackgroundColor: const Color(0x33B0BEC5),
    isBookmarked: true,
  ),
];

final List<FeedItem> dummyYesterdayFeeds = [
  FeedItem(
    id: '4',
    siteName: 'Smashing Mag',
    title: 'CSS Container Queries: A Primer',
    description:
        'Moving beyond media queries. How container queries allow components to adapt...',
    timeAgo: 'Yesterday',
    siteIcon: Icons.design_services,
    iconColor: const Color(0xFF00E676),
    iconBackgroundColor: const Color(0x3300E676),
  ),
  FeedItem(
    id: '5',
    siteName: 'Ars Technica',
    title: 'SpaceX Starship Launch Scheduled',
    description:
        'The FAA has finally granted approval for the next orbital flight test. Here is...',
    timeAgo: 'Yesterday',
    siteIcon: Icons.rocket_launch,
    iconColor: const Color(0xFF2196F3),
    iconBackgroundColor: const Color(0x332196F3),
  ),
  FeedItem(
    id: '6',
    siteName: 'Syntax.fm',
    title: 'Ep 720: Web Components are Back?',
    description:
        'Wes and Scott discuss the resurgence of web components, the new APIs, and...',
    timeAgo: 'Yesterday',
    siteIcon: Icons.podcasts,
    iconColor: const Color(0xFFE040FB),
    iconBackgroundColor: const Color(0x33E040FB),
  ),
];
