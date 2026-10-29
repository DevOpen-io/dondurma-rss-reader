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
    if (seen.add(articleKey(item))) yield item;
  }
}

/// What makes two rows the same article: the usable link, else the source
/// instance.
Object articleKey(FeedItem item) =>
    usableArticleLink(item.link) ?? (item.feedUrl, item.id);

/// One keyword rule as typed (#69): a whole word or phrase, `/regex/` for
/// a regular expression, either after `title:` to look at the title only.
/// Matching ignores case.
class KeywordRule {
  KeywordRule._(this._pattern, this._titleOnly);

  final RegExp _pattern;
  final bool _titleOnly;

  static const _titlePrefix = 'title:';

  /// Text beyond this is not searched: a long summary must not make a rule
  /// expensive, and titles are far shorter.
  static const _maxText = 1000;

  // Rules are compiled once per text, not on every filter pass.
  static final _compiled = <String, KeywordRule?>{};

  /// A group repeated by a quantifier that itself holds one, like
  /// `(\w+\s?)+` — the shape of patterns that backtrack exponentially and
  /// would freeze the list on an unlucky title.
  static final _nestedQuantifier = RegExp(r'\([^()]*[+*}][^()]*\)[+*{]');

  /// Only ASCII punctuation, like `//` (an empty pattern) or `/`: never a
  /// word a reader means, and it would match stray marks in summaries.
  static final _punctuationOnly = RegExp(r'^[!-/:-@\[-`{-~\s]+$');

  /// The compiled rule, or null for an empty, invalid or unsafe one — a
  /// stored rule that does not pass is skipped rather than failing the list.
  static KeywordRule? tryParse(String rule) =>
      _compiled.putIfAbsent(rule, () => _parse(rule));

  static KeywordRule? _parse(String rule) {
    var text = rule.trim();
    var titleOnly = false;
    if (text.toLowerCase().startsWith(_titlePrefix)) {
      titleOnly = true;
      text = text.substring(_titlePrefix.length).trim();
    }
    if (text.isEmpty) return null;
    final RegExp pattern;
    try {
      if (isRegex(text)) {
        final source = text.substring(1, text.length - 1);
        if (_nestedQuantifier.hasMatch(source)) return null;
        pattern = RegExp(source, caseSensitive: false, unicode: true);
        // A pattern that matches empty text would hide or read everything.
        if (pattern.hasMatch('')) return null;
      } else {
        if (_punctuationOnly.hasMatch(text)) return null;
        // Word edges by Unicode letters and digits: `\b` only knows ASCII,
        // so Turkish or Cyrillic words never matched.
        pattern = RegExp(
          r'(?<![\p{L}\p{N}_])' +
              RegExp.escape(text.toLowerCase()) +
              r'(?![\p{L}\p{N}_])',
          caseSensitive: false,
          unicode: true,
        );
      }
    } on FormatException {
      return null;
    }
    return KeywordRule._(pattern, titleOnly);
  }

  /// Whether [text] (after an optional `title:`) is written as `/regex/`.
  static bool isRegex(String text) =>
      text.length > 2 && text.startsWith('/') && text.endsWith('/');

  /// Splits typed input into rules at commas, keeping a `/pattern/` whole
  /// even when it holds commas (`/a{1,3}/, word` is two rules).
  static List<String> split(String input) {
    final rules = <String>[];
    var pending = '';
    for (final piece in input.split(',')) {
      pending = pending.isEmpty ? piece : '$pending,$piece';
      final bare = pending.trim().replaceFirst(
        RegExp(r'^title:\s*', caseSensitive: false),
        '',
      );
      // An opened pattern waits for its closing slash.
      if (bare.startsWith('/') && !isRegex(bare)) continue;
      if (pending.trim().isNotEmpty) rules.add(pending.trim());
      pending = '';
    }
    if (pending.trim().isNotEmpty) rules.add(pending.trim());
    return rules;
  }

  bool matches({required String title, required String description}) =>
      _pattern.hasMatch(_capped(title)) ||
      (!_titleOnly && _pattern.hasMatch(_capped(description)));

  static String _capped(String text) =>
      text.length <= _maxText ? text : text.substring(0, _maxText);
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
