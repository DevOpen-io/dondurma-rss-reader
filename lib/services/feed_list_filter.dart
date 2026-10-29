import '../models/feed_item.dart';
import 'article_identity.dart';
import 'feed_decisions.dart';

/// Runs the full feed filtering pipeline in the documented order:
/// runtime sheet filter → selected category → selected feed → text search →
/// keyword exclusion → cross-feed link dedup ([dedupe]). Pure — the caller
/// applies read/bookmark decoration and caches the result.
Iterable<FeedItem> applyFeedFilters({
  required Iterable<FeedItem> items,
  required bool Function(FeedItem item) isRead,
  required String? selectedCategory,
  required String? selectedFeedUrl,
  required String searchQuery,
  required String readFilter,
  required Set<String> filterCategories,
  required List<String> globalKeywords,
  required Map<String, List<String>> feedKeywordsMap,
  Map<String, List<String>> feedOnlyKeywordsMap = const {},
  bool dedupe = true,
}) {
  Iterable<FeedItem> filtered = items;

  // Runtime sheet filter (read status + multi-category, AND) — replaces the
  // old unread-only step, same position in the documented pipeline order.
  if (readFilter != 'all' || filterCategories.isNotEmpty) {
    filtered = filtered.where(
      (i) => feedPassesRuntimeFilter(
        isRead: isRead(i),
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
  if (globalKeywords.isNotEmpty ||
      feedKeywordsMap.isNotEmpty ||
      feedOnlyKeywordsMap.isNotEmpty) {
    filtered = _applyKeywordFilters(
      filtered,
      globalKeywords: globalKeywords,
      feedKeywordsMap: feedKeywordsMap,
      feedOnlyKeywordsMap: feedOnlyKeywordsMap,
    );
  }

  // Cross-feed dedup: the same article reachable through two subscriptions
  // (e.g. an outlet's "News" vs "World" feed) shows once. Runs last so an
  // excluded duplicate never consumes another copy's dedup slot.
  return dedupe ? deduplicateByLink(filtered) : filtered;
}

/// Legacy offline-membership dedup key: the normalized absolute
/// http(s) link when usable, otherwise the legacy global archive ID.
/// Display instances use source-local fallback identities below.
String dedupeKey({required String? link, required String id}) =>
    usableArticleLink(link) ?? id;

/// The normalized absolute http(s) link that identifies an article across
/// feeds, or null when [link] cannot.
String? usableArticleLink(String? link) {
  var key = ArticleIdentity.normalizeArticleUrl(link);
  if (key != null) {
    final uri = Uri.tryParse(key);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      key = null;
    }
  }
  return key;
}

/// Drops duplicate article links globally; without a usable link only
/// duplicates within the same source can be identified safely.
Iterable<FeedItem> deduplicateByLink(Iterable<FeedItem> items) sync* {
  final seen = <Object>{};
  for (final item in items) {
    final Object key = usableArticleLink(item.link) ?? (item.feedUrl, item.id);
    if (seen.add(key)) yield item;
  }
}

/// One keyword rule as typed (#69): a whole word or phrase, `/regex/` for
/// a regular expression, either after `title:` to look at the title only.
/// Matching ignores case.
class KeywordRule {
  KeywordRule._(this._pattern, this._titleOnly);

  final RegExp _pattern;
  final bool _titleOnly;

  static const _titlePrefix = 'title:';

  /// The compiled rule, or null for an empty or invalid one — a stored rule
  /// that no longer compiles is skipped rather than failing the list.
  static KeywordRule? tryParse(String rule) {
    var text = rule.trim();
    var titleOnly = false;
    if (text.toLowerCase().startsWith(_titlePrefix)) {
      titleOnly = true;
      text = text.substring(_titlePrefix.length).trim();
    }
    if (text.isEmpty) return null;
    try {
      final pattern = isRegex(text)
          ? RegExp(text.substring(1, text.length - 1), caseSensitive: false)
          : RegExp(
              r'\b' + RegExp.escape(text.toLowerCase()) + r'\b',
              caseSensitive: false,
            );
      return KeywordRule._(pattern, titleOnly);
    } on FormatException {
      return null;
    }
  }

  /// Whether [text] (after an optional `title:`) is written as `/regex/`.
  static bool isRegex(String text) =>
      text.length > 2 && text.startsWith('/') && text.endsWith('/');

  bool matches({required String title, required String description}) =>
      _pattern.hasMatch(title) ||
      (!_titleOnly && _pattern.hasMatch(description));
}

/// Pre-compiled permanent keyword exclusion (global + per-feed), usable
/// outside the display pipeline — e.g. when cache candidates come from
/// durable records rather than live [FeedItem]s (#37).
class KeywordExcluder {
  KeywordExcluder({
    required List<String> globalKeywords,
    required Map<String, List<String>> feedKeywordsMap,
    Map<String, List<String>> feedOnlyKeywordsMap = const {},
  }) : _globalRules = _compile(globalKeywords),
       _feedRulesMap = {
         for (final e in feedKeywordsMap.entries) e.key: _compile(e.value),
       },
       _feedOnlyRulesMap = {
         for (final e in feedOnlyKeywordsMap.entries)
           if (_compile(e.value) case final rules when rules.isNotEmpty)
             e.key: rules,
       };

  static List<KeywordRule> _compile(List<String> keywords) => [
    for (final kw in keywords) ?KeywordRule.tryParse(kw),
  ];

  final List<KeywordRule> _globalRules;
  final Map<String, List<KeywordRule>> _feedRulesMap;
  final Map<String, List<KeywordRule>> _feedOnlyRulesMap;

  /// Whether [title]/[description] match a global or feed-scoped exclusion,
  /// or miss every "only show" rule of their feed.
  bool excludes({
    required String title,
    required String description,
    required String feedUrl,
  }) {
    bool matchesAny(List<KeywordRule> rules) =>
        rules.any((r) => r.matches(title: title, description: description));

    final only = _feedOnlyRulesMap[feedUrl];
    if (only != null && !matchesAny(only)) return true;
    final feedRules = _feedRulesMap[feedUrl];
    return (_globalRules.isNotEmpty && matchesAny(_globalRules)) ||
        (feedRules != null && matchesAny(feedRules));
  }
}

Iterable<FeedItem> _applyKeywordFilters(
  Iterable<FeedItem> filtered, {
  required List<String> globalKeywords,
  required Map<String, List<String>> feedKeywordsMap,
  required Map<String, List<String>> feedOnlyKeywordsMap,
}) {
  final excluder = KeywordExcluder(
    globalKeywords: globalKeywords,
    feedKeywordsMap: feedKeywordsMap,
    feedOnlyKeywordsMap: feedOnlyKeywordsMap,
  );
  return filtered.where(
    (item) => !excluder.excludes(
      title: item.title,
      description: item.description,
      feedUrl: item.feedUrl,
    ),
  );
}
