/// A curated feed suggestion from the remote `suggested_feeds*.json` lists.
class SuggestedFeed {
  final String name;
  final String url;
  final String category;
  final int popularity;

  const SuggestedFeed({
    required this.name,
    required this.url,
    required this.category,
    required this.popularity,
  });

  factory SuggestedFeed.fromJson(Map<String, dynamic> json) {
    return SuggestedFeed(
      name: json['name'].toString(),
      url: json['url'].toString(),
      category: json['category'].toString(),
      popularity: (json['popularity'] as num?)?.toInt() ?? 0,
    );
  }

  /// Bare host for favicon lookups — unwraps `google.com/search?q=` links
  /// and strips a leading `www.`.
  String get domain {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    String host = uri.host;
    if (host.contains('google.com') && uri.queryParameters.containsKey('q')) {
      try {
        host = Uri.parse(uri.queryParameters['q']!).host;
      } catch (_) {}
    }
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
