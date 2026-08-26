import '../models/feed_item.dart';

/// Pure helpers for merging and bounding the durable article cache.
class FeedCachePolicy {
  /// Replaces only feeds present in [freshItemsByFeed]. Failed and 304 feeds
  /// are omitted by callers, so their existing articles survive unchanged.
  static List<FeedItem> mergeFreshFeeds({
    required Iterable<FeedItem> existingItems,
    required Map<String, List<FeedItem>> freshItemsByFeed,
    required Iterable<String> subscribedFeedUrls,
  }) {
    final subscribed = subscribedFeedUrls.toList(growable: false);
    final groups = <String, List<FeedItem>>{
      for (final url in subscribed) url: <FeedItem>[],
    };
    for (final item in existingItems) {
      groups[item.feedUrl]?.add(item);
    }
    for (final entry in freshItemsByFeed.entries) {
      if (groups.containsKey(entry.key)) {
        groups[entry.key] = List<FeedItem>.of(entry.value);
      }
    }
    return [for (final url in subscribed) ...groups[url] ?? const <FeedItem>[]];
  }

  /// Applies a global hard limit while sharing capacity across subscriptions.
  /// Feed order follows persisted subscription order. When subscriptions
  /// outnumber [limit], later feeds cannot receive an item by definition.
  static List<FeedItem> fairTrim({
    required Iterable<FeedItem> items,
    required Iterable<String> subscribedFeedUrls,
    required int limit,
  }) {
    if (limit <= 0) return const [];

    final feedOrder = subscribedFeedUrls.toList(growable: false);
    final groups = <String, List<FeedItem>>{
      for (final url in feedOrder) url: <FeedItem>[],
    };
    final seen = <String>{};
    for (final item in items) {
      final group = groups[item.feedUrl];
      if (group == null) continue;
      final identity = '${item.feedUrl}\u0000${item.id}';
      if (seen.add(identity)) group.add(item);
    }

    for (final group in groups.values) {
      group.sort(_newestFirst);
    }

    final selected = <FeedItem>[];
    for (var round = 0; selected.length < limit; round++) {
      var added = false;
      for (final url in feedOrder) {
        final group = groups[url]!;
        if (round >= group.length) continue;
        selected.add(group[round]);
        added = true;
        if (selected.length == limit) break;
      }
      if (!added) break;
    }
    return selected;
  }

  static int _newestFirst(FeedItem a, FeedItem b) {
    final aDate = a.pubDate;
    final bDate = b.pubDate;
    if (aDate == null && bDate != null) return 1;
    if (aDate != null && bDate == null) return -1;
    if (aDate != null && bDate != null) {
      final dateOrder = bDate.compareTo(aDate);
      if (dateOrder != 0) return dateOrder;
    }
    return a.id.compareTo(b.id);
  }
}
