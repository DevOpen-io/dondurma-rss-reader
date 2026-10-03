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
      group.sort(_protectedThenNewest);
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

  /// Items carrying a downloaded body sort before unprotected ones, then by
  /// date — eviction drops a fetched full text last (decision #17).
  static int _protectedThenNewest(FeedItem a, FeedItem b) {
    final aProt = a.prefetchedFullText != null;
    final bProt = b.prefetchedFullText != null;
    if (aProt != bProt) return aProt ? -1 : 1;
    return _newestFirst(a, b);
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
