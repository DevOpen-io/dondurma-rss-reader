class FeedSubscription {
  final String url;
  final String name;
  final String category;
  final bool notificationsEnabled;

  FeedSubscription({
    required this.url,
    required this.name,
    required this.category,
    this.notificationsEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'category': category,
    'notificationsEnabled': notificationsEnabled,
  };

  factory FeedSubscription.fromJson(Map<String, dynamic> json) =>
      FeedSubscription(
        url: json['url'],
        name: json['name'],
        category: json['category'],
        notificationsEnabled: json['notificationsEnabled'] ?? true,
      );

  FeedSubscription copyWith({
    String? url,
    String? name,
    String? category,
    bool? notificationsEnabled,
  }) {
    return FeedSubscription(
      url: url ?? this.url,
      name: name ?? this.name,
      category: category ?? this.category,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }
}
