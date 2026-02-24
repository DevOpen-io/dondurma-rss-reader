import 'package:flutter/material.dart';

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
