/// Represents a user's subscription to an RSS/Atom feed source.
///
/// Immutable value object that stores the feed URL, display name, category
/// folder, notification preference, and per-feed keyword exclusion list.
/// Serializable to/from JSON for Hive persistence.
class FeedSubscription {
  final String url;
  final String name;
  final String category;
  final bool notificationsEnabled;
  final List<String> excludedKeywords;

  FeedSubscription({
    required this.url,
    required this.name,
    required this.category,
    this.notificationsEnabled = true,
    this.excludedKeywords = const [],
  });

  /// Serializes this subscription to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'category': category,
    'notificationsEnabled': notificationsEnabled,
    'excludedKeywords': excludedKeywords,
  };

  /// Deserializes a [FeedSubscription] from a JSON map.
  ///
  /// All fields fall back to sensible defaults for backward compatibility.
  factory FeedSubscription.fromJson(Map<String, dynamic> json) =>
      FeedSubscription(
        url: json['url'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'Uncategorized',
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        excludedKeywords:
            (json['excludedKeywords'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  FeedSubscription copyWith({
    String? url,
    String? name,
    String? category,
    bool? notificationsEnabled,
    List<String>? excludedKeywords,
  }) {
    return FeedSubscription(
      url: url ?? this.url,
      name: name ?? this.name,
      category: category ?? this.category,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      excludedKeywords: excludedKeywords ?? this.excludedKeywords,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FeedSubscription && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
