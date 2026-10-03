import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/suggested_feed.dart';

/// Fetches the curated suggested-feed lists (Global + Turkish) hosted in the
/// project's `remote_data/` GitHub directory.
class SuggestedFeedsService {
  static const _base =
      'https://raw.githubusercontent.com/DevOpen-io/dondurma-rss-reader/'
      'refs/heads/main/remote_data';

  Future<List<SuggestedFeed>> fetchGlobal() =>
      _fetch('$_base/suggested_feeds.json');

  Future<List<SuggestedFeed>> fetchTurkish() =>
      _fetch('$_base/suggested_feed_tr.json');

  Future<List<SuggestedFeed>> _fetch(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to load feeds: ${response.statusCode}');
    }
    final List<dynamic> jsonData = json.decode(response.body);
    return jsonData
        .map((item) => SuggestedFeed.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
