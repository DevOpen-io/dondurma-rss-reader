import '../models/feed_item.dart';
import 'article_identity.dart';
import 'feed_decisions.dart';

/// Runs the full feed filtering pipeline in the documented order:
/// runtime sheet filter → selected category → selected feed → text search →
/// keyword exclusion → cross-feed link dedup. Pure — the caller applies
/// read/bookmark decoration and caches the result.
Iterable<FeedItem> applyFeedFilters({
  required Iterable<FeedItem> items,
  required Set<String> readItemIds,
  required String? selectedCategory,
  required String? selectedFeedUrl,
  required String searchQuery,
  required String readFilter,
  required Set<String> filterCategories,
  required List<String> globalKeywords,
  required Map<String, List<String>> feedKeywordsMap,
}) {
  Iterable<FeedItem> filtered = items;

  // Runtime sheet filter (read status + multi-category, AND) — replaces the
  // old unread-only step, same position in the documented pipeline order.
  if (readFilter != 'all' || filterCategories.isNotEmpty) {
    filtered = filtered.where(
      (i) => feedPassesRuntimeFilter(
        isRead: readItemIds.contains(i.id),
        category: i.category,
        readFilter: readFilter,
        categories: filterCategories,
      ),
    );
  }

  if (selectedCategory != null) {
    filtered = filtered.where((i) => i.category == selectedCategory);
  }
  if (selectedFeedUrl != null) {
    filtered = filtered.where((i) => i.feedUrl == selectedFeedUrl);
  }
  if (searchQuery.isNotEmpty) {
    final query = searchQuery.toLowerCase();
    filtered = filtered.where(
      (i) =>
          i.title.toLowerCase().contains(query) ||
          i.description.toLowerCase().contains(query) ||
          i.siteName.toLowerCase().contains(query),
    );
  }

  // Keyword filtering — compile regex patterns once for the entire pass
  if (globalKeywords.isNotEmpty || feedKeywordsMap.isNotEmpty) {
    filtered = _applyKeywordFilters(
      filtered,
      globalKeywords: globalKeywords,
      feedKeywordsMap: feedKeywordsMap,
    );
  }

  // Cross-feed dedup: the same article reachable through two subscriptions
  // (e.g. an outlet's "News" vs "World" feed) shows once. Runs last so an
  // excluded duplicate never consumes another copy's dedup slot.
  return deduplicateByLink(filtered);
}

/// Drops later items whose normalized article link was already yielded —
/// the list arrives date-sorted, so the newest copy wins. Items with no
/// usable link dedup on their own id, which can never collide. Junk links
/// (`#`, `about:blank`, relative paths) are not absolute http(s) URLs, so
/// they fall back to the id path rather than collapsing unrelated items.
Iterable<FeedItem> deduplicateByLink(Iterable<FeedItem> items) sync* {
  final seen = <String>{};
  for (final item in items) {
    var key = ArticleIdentity.normalizeArticleUrl(item.link);
    if (key != null) {
      final uri = Uri.tryParse(key);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        key = null;
      }
    }
    if (seen.add(key ?? item.id)) yield item;
  }
}

Iterable<FeedItem> _applyKeywordFilters(
  Iterable<FeedItem> filtered, {
  required List<String> globalKeywords,
  required Map<String, List<String>> feedKeywordsMap,
}) {
  // Pre-compile global keyword patterns once
  final globalPatterns = globalKeywords
      .map(
        (kw) => RegExp(
          r'\b' + RegExp.escape(kw.toLowerCase()) + r'\b',
          caseSensitive: false,
        ),
      )
      .toList();

  // Pre-compile per-feed keyword patterns once
  final Map<String, List<RegExp>> feedPatternsMap = {};
  for (final entry in feedKeywordsMap.entries) {
    feedPatternsMap[entry.key] = entry.value
        .map(
          (kw) => RegExp(
            r'\b' + RegExp.escape(kw.toLowerCase()) + r'\b',
            caseSensitive: false,
          ),
        )
        .toList();
  }

  return filtered.where((item) {
    final feedPatterns = feedPatternsMap[item.feedUrl];
    if (globalPatterns.isEmpty && feedPatterns == null) return true;

    bool matchesAny(List<RegExp> patterns) {
      for (final regex in patterns) {
        if (regex.hasMatch(item.title) || regex.hasMatch(item.description)) {
          return true;
        }
      }
      return false;
    }

    if (globalPatterns.isNotEmpty && matchesAny(globalPatterns)) {
      return false;
    }
    if (feedPatterns != null && matchesAny(feedPatterns)) {
      return false;
    }
    return true;
  });
}
