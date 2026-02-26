class FeedSubscription {
  final String url;
  final String name;
  final String category;

  FeedSubscription({
    required this.url,
    required this.name,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'category': category,
  };

  factory FeedSubscription.fromJson(Map<String, dynamic> json) =>
      FeedSubscription(
        url: json['url'],
        name: json['name'],
        category: json['category'],
      );
}
