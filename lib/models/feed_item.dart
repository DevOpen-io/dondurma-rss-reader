import 'package:html/parser.dart' show parse;

import '../services/article_identity.dart';

/// Represents a single article/entry from an RSS or Atom feed.
///
/// Immutable value object that carries display state (read/bookmark) and
/// content fields (link, HTML body, publication date). Serializable to/from
/// JSON for Hive caching; keys of removed fields in older caches are ignored.
class FeedItem {
  final String id;
  final String siteName;
  final String title;
  final String description;
  final bool isBookmarked;
  final bool isRead;

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
    this.isBookmarked = false,
    this.isRead = false,
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
    bool? isBookmarked,
    bool? isRead,
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
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isRead: isRead ?? this.isRead,
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
      'isBookmarked': isBookmarked,
      'isRead': isRead,
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
      siteName: ArticleIdentity.sanitizeSiteTitle(
        _decodeHtml(json['siteName'] as String? ?? 'Unknown'),
      ),
      title: _decodeHtml(json['title'] as String? ?? 'No Title'),
      description: json['description'] as String? ?? '',
      isBookmarked: json['isBookmarked'] as bool? ?? false,
      isRead: json['isRead'] as bool? ?? false,
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

  /// One article instance per source: equal exactly when [ArticleRef]s are.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedItem && ArticleRef.of(other) == ArticleRef.of(this);

  @override
  int get hashCode => ArticleRef.of(this).hashCode;

  static final _entity = RegExp(
    r'&(?:#\d+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);',
  );

  /// Decodes HTML entities (e.g. `&#8216;`) left in older caches. Stored
  /// text is normally decoded already, so the HTML parse runs only when an
  /// entity remains, and `<` is escaped first so literal angle brackets
  /// stay text instead of being dropped as tags.
  static String _decodeHtml(String text) {
    if (!_entity.hasMatch(text)) return text;
    try {
      return parse(text.replaceAll('<', '&lt;')).documentElement?.text ?? text;
    } catch (_) {
      return text;
    }
  }
}
