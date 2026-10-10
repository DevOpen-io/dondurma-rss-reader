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

/// The dedup key used by [deduplicateByLink]: the normalized absolute
/// http(s) link when usable, otherwise the item's own id — which can never
/// collide across genuinely different articles. Junk links (`#`,
/// `about:blank`, relative paths) fall back to the id path.
String dedupeKey({required String? link, required String id}) {
  var key = ArticleIdentity.normalizeArticleUrl(link);
  if (key != null) {
    final uri = Uri.tryParse(key);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      key = null;
    }
  }
  return key ?? id;
}

/// Drops later items whose normalized article link was already yielded —
/// the list arrives date-sorted, so the newest copy wins. Items with no
/// usable link dedup on their own id, which can never collide.
Iterable<FeedItem> deduplicateByLink(Iterable<FeedItem> items) sync* {
  final seen = <String>{};
  for (final item in items) {
    if (seen.add(dedupeKey(link: item.link, id: item.id))) yield item;
  }
}

/// Pre-compiled permanent keyword exclusion (global + per-feed), usable
/// outside the display pipeline — e.g. when cache candidates come from
/// durable records rather than live [FeedItem]s (#37).
class KeywordExcluder {
  KeywordExcluder({
    required List<String> globalKeywords,
    required Map<String, List<String>> feedKeywordsMap,
  }) : _globalPatterns = _compile(globalKeywords),
       _feedPatternsMap = {
         for (final e in feedKeywordsMap.entries) e.key: _compile(e.value),
       };

  static List<RegExp> _compile(List<String> keywords) => keywords
      .map(
        (kw) => RegExp(
          r'\b' + RegExp.escape(kw.toLowerCase()) + r'\b',
          caseSensitive: false,
        ),
      )
      .toList();

  final List<RegExp> _globalPatterns;
  final Map<String, List<RegExp>> _feedPatternsMap;

  /// Whether [title]/[description] match a global or feed-scoped exclusion.
  bool excludes({
    required String title,
    required String description,
    required String feedUrl,
  }) {
    final feedPatterns = _feedPatternsMap[feedUrl];
    if (_globalPatterns.isEmpty && feedPatterns == null) return false;

    bool matchesAny(List<RegExp> patterns) {
      for (final regex in patterns) {
        if (regex.hasMatch(title) || regex.hasMatch(description)) {
          return true;
        }
      }
      return false;
    }

    return (_globalPatterns.isNotEmpty && matchesAny(_globalPatterns)) ||
        (feedPatterns != null && matchesAny(feedPatterns));
  }
}

Iterable<FeedItem> _applyKeywordFilters(
  Iterable<FeedItem> filtered, {
  required List<String> globalKeywords,
  required Map<String, List<String>> feedKeywordsMap,
}) {
  final excluder = KeywordExcluder(
    globalKeywords: globalKeywords,
    feedKeywordsMap: feedKeywordsMap,
  );
  return filtered.where(
    (item) => !excluder.excludes(
      title: item.title,
      description: item.description,
      feedUrl: item.feedUrl,
    ),
  );
}
