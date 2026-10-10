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
        groups[entry.key] = carryOverPrefetchedText(
          existingItems: groups[entry.key] ?? const <FeedItem>[],
          freshItems: List<FeedItem>.of(entry.value),
        );
      }
    }
    return [for (final url in subscribed) ...groups[url] ?? const <FeedItem>[]];
  }

  /// Re-attaches prefetched full-text bodies onto freshly parsed items,
  /// matched by (feedUrl, id). Fresh parses always carry null, so without
  /// this every 200 merge erases offline content — both the foreground
  /// refresher and the Workmanager merge must call it.
  static List<FeedItem> carryOverPrefetchedText({
    required Iterable<FeedItem> existingItems,
    required List<FeedItem> freshItems,
  }) {
    final prefetched = <String, String>{
      for (final i in existingItems)
        if (i.prefetchedFullText != null)
          '${i.feedUrl} ${i.id}': i.prefetchedFullText!,
    };
    if (prefetched.isEmpty) return freshItems;
    for (var i = 0; i < freshItems.length; i++) {
      final item = freshItems[i];
      final body = prefetched['${item.feedUrl} ${item.id}'];
      if (item.prefetchedFullText == null && body != null) {
        freshItems[i] = item.copyWith(prefetchedFullText: body);
      }
    }
    return freshItems;
  }
}
