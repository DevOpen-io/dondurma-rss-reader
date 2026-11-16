import '../models/feed_item.dart';
import 'feed_date_groups.dart';

/// Set to true beside `cachedItemsJson` by every writer that persists whole
/// feeds. Before it, the snapshot held only the offline cache members, so a
/// low-frequency feed came back trimmed and an HTTP 304 kept it that way.
const String wholeFeedSnapshotKey = 'cachedItemsWholeFeeds';

/// Pure helpers for merging and bounding the durable article cache.
class FeedCachePolicy {
  /// A snapshot written before [wholeFeedSnapshotKey] may hold a fraction of
  /// a feed: its validators must not turn the next fetch into a 304.
  static bool isTrimmedLegacySnapshot({
    required Object? snapshot,
    required Object? wholeFeedMarker,
  }) => snapshot != null && wholeFeedMarker != true;

  /// Shared foreground preview/final merge. Pending, failed and 304 feeds
  /// retain their snapshot; only fresh bodies replace a feed's articles.
  /// Subscription and bookmark inputs are evaluated by the caller at apply time.
  static List<FeedItem> mergeVisibleFeeds({
    required Iterable<FeedItem> existingItems,
    required Map<String, List<FeedItem>> freshItemsByFeed,
    required Iterable<String> subscribedFeedUrls,
    required Iterable<FeedItem> bookmarkedItems,
    required DateTime now,
  }) {
    final merged = mergeFreshFeeds(
      existingItems: existingItems,
      freshItemsByFeed: freshItemsByFeed,
      subscribedFeedUrls: subscribedFeedUrls,
    );
    final seen = <(String, String)>{};
    final items = [
      for (final item in merged)
        if (seen.add((item.feedUrl, item.id))) item,
    ];
    for (final saved in bookmarkedItems) {
      if (seen.add((saved.feedUrl, saved.id))) items.add(saved);
    }
    sortByEffectivePubDateDesc(items, now);
    return items;
  }

  /// Replaces only feeds present in [freshItemsByFeed]. Failed and 304 feeds
  /// are omitted by callers, so their existing articles survive unchanged.
  static List<FeedItem> mergeFreshFeeds({
    required Iterable<FeedItem> existingItems,
    required Map<String, List<FeedItem>> freshItemsByFeed,
    required Iterable<String> subscribedFeedUrls,
  }) {
    final subscribed = subscribedFeedUrls.toSet();
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
    final seen = <(String, String)>{};
    return [
      for (final url in subscribed)
        for (final item in groups[url] ?? const <FeedItem>[])
          if (seen.add((item.feedUrl, item.id))) item,
    ];
  }
}
