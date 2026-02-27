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

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'category': category,
    'notificationsEnabled': notificationsEnabled,
    'excludedKeywords': excludedKeywords,
  };

  factory FeedSubscription.fromJson(Map<String, dynamic> json) =>
      FeedSubscription(
        url: json['url'],
        name: json['name'],
        category: json['category'],
        notificationsEnabled: json['notificationsEnabled'] ?? true,
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
}
