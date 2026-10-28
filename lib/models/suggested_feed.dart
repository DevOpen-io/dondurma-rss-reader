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

  /// Number of suggestions per category.
  static Map<String, int> categoryCounts(Iterable<SuggestedFeed> feeds) {
    final counts = <String, int>{};
    for (final f in feeds) {
      counts[f.category] = (counts[f.category] ?? 0) + 1;
    }
    return counts;
  }

  /// Highest feed popularity per category. A category whose feeds all
  /// have popularity 0 has no entry.
  static Map<String, int> categoryPopularity(Iterable<SuggestedFeed> feeds) {
    final maxPop = <String, int>{};
    for (final f in feeds) {
      if (f.popularity > (maxPop[f.category] ?? 0)) {
        maxPop[f.category] = f.popularity;
      }
    }
    return maxPop;
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
