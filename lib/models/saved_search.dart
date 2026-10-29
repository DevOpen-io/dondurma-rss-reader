import 'dart:convert';

/// A search kept under a name (#71): the query with the scope and filters
/// it ran in — folder or feed, read filter and filter-sheet folders — so
/// opening it gives the same results.
class SavedSearch {
  const SavedSearch({
    required this.name,
    required this.query,
    this.category,
    this.feedUrl,
    this.readFilter = 'all',
    this.filterCategories = const [],
  });

  final String name;
  final String query;
  final String? category;
  final String? feedUrl;

  /// `'all' | 'unread' | 'read'`.
  final String readFilter;
  final List<String> filterCategories;

  static const _readFilters = {'all', 'unread', 'read'};

  Map<String, Object?> toJson() => {
    'name': name,
    'query': query,
    if (category != null) 'category': category,
    if (feedUrl != null) 'feedUrl': feedUrl,
    if (readFilter != 'all') 'readFilter': readFilter,
    if (filterCategories.isNotEmpty) 'filterCategories': filterCategories,
  };

  /// Null for anything that is not a saved search (a hand-edited backup).
  static SavedSearch? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final query = raw['query'];
    final category = raw['category'];
    final feedUrl = raw['feedUrl'];
    final readFilter = raw['readFilter'] ?? 'all';
    final categories = raw['filterCategories'] ?? const [];
    if (name is! String || name.trim().isEmpty) return null;
    if (query is! String || query.trim().isEmpty) return null;
    if (category is! String? || feedUrl is! String?) return null;
    if (readFilter is! String || !_readFilters.contains(readFilter)) {
      return null;
    }
    if (categories is! List || categories.any((c) => c is! String)) {
      return null;
    }
    return SavedSearch(
      name: name,
      query: query,
      category: category,
      feedUrl: feedUrl,
      readFilter: readFilter,
      filterCategories: categories.cast<String>().toList()..sort(),
    );
  }

  /// What the search finds; saving the same search again renames it.
  String get key => jsonEncode(toJson()..remove('name'));

  SavedSearch rename(String newName) => SavedSearch(
    name: newName,
    query: query,
    category: category,
    feedUrl: feedUrl,
    readFilter: readFilter,
    filterCategories: filterCategories,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedSearch &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
