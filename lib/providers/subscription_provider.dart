import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/feed_subscription.dart';
import '../services/article_identity.dart';

/// Manages the user's RSS feed subscriptions, categories, and their icons.
///
/// Supports add/remove/rename/move operations for both feeds and categories.
/// Categories come from two sources — feed subscriptions and standalone
/// custom categories — merged in the [categories] getter.
///
/// Persists data in the `'feeds'` Hive box under `'subscriptions'`,
/// `'custom_categories'`, and `'category_icons'` keys.
class SubscriptionProvider extends ChangeNotifier {
  static const List<IconData> categoryIconOptions = [
    Icons.folder_outlined,
    Icons.menu_book_outlined,
    Icons.newspaper_outlined,
    Icons.sports_esports_outlined,
    Icons.lightbulb_outline,
    Icons.local_fire_department_outlined,
    Icons.auto_awesome_outlined,
    Icons.star_outline,
    Icons.smartphone_outlined,
    Icons.laptop_mac_outlined,
    Icons.movie_outlined,
    Icons.music_note_outlined,
    Icons.sports_soccer,
    Icons.restaurant_outlined,
    Icons.flight_outlined,
    Icons.palette_outlined,
    Icons.work_outline,
    Icons.trending_up,
    Icons.science_outlined,
    Icons.park_outlined,
    Icons.smart_toy_outlined,
    Icons.directions_car_outlined,
    Icons.pets_outlined,
    Icons.local_pizza_outlined,
    Icons.coffee_outlined,
    Icons.favorite_outline,
    Icons.public_outlined,
    Icons.rocket_launch_outlined,
    Icons.photo_camera_outlined,
  ];

  static const IconData _defaultCategoryIcon = Icons.folder_outlined;
  static final Set<int> _supportedCategoryCodePoints = categoryIconOptions
      .map((icon) => icon.codePoint)
      .toSet();

  List<FeedSubscription> _subscriptions = [];
  Set<String> _customCategories = {};
  Map<String, String> _categoryIcons = {};
  List<String> _categoryOrder = [];

  /// All current feed subscriptions.
  List<FeedSubscription> get subscriptions => _subscriptions;

  /// Whether [feedUrl] reads full text: the feed's tri-state
  /// `fullTextEnabled`, where null (and an unknown feed) follows
  /// [autoFullText]. The single source of this rule.
  bool effectiveFullText(String feedUrl, {required bool autoFullText}) {
    for (final s in _subscriptions) {
      if (s.url == feedUrl) return s.fullTextEnabled ?? autoFullText;
    }
    return autoFullText;
  }

  /// The union of categories derived from subscriptions and standalone
  /// custom (possibly empty) categories.
  Set<String> get categories {
    final fromSubs = _subscriptions.map((s) => s.category).toSet();
    return fromSubs.union(_customCategories);
  }

  /// Categories in user-defined order, with any new/unknown categories appended sorted.
  List<String> get categoriesOrdered {
    final all = categories;
    final ordered = _categoryOrder.where(all.contains).toList();
    final remaining = all.where((c) => !_categoryOrder.contains(c)).toList()
      ..sort();
    return [...ordered, ...remaining];
  }

  /// Reorders the non-Uncategorized category at [oldIndex] to [newIndex].
  Future<void> reorderCategory(int oldIndex, int newIndex) async {
    final ordered = categoriesOrdered
        .where((c) => c != 'Uncategorized')
        .toList();
    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    if (newIndex < 0 || newIndex > ordered.length) return;
    final item = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, item);
    _categoryOrder = ordered;
    await _saveCategoryOrder();
    notifyListeners();
  }

  /// Lazily cached reference to the `'feeds'` Hive box.
  Box get _box => Hive.box('feeds');

  SubscriptionProvider() {
    _loadSubscriptions();
  }

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  /// Loads subscriptions, custom categories, and icons synchronously from Hive.
  /// Hive box reads are in-memory, so no await needed.
  void _loadSubscriptions() {
    final String? data = _box.get('subscriptions');
    bool iconsNeedSave = false;

    // Load category order
    final String? orderData = _box.get('category_order');
    if (orderData != null) {
      _categoryOrder = List<String>.from(jsonDecode(orderData));
    }

    // Load custom categories
    final String? catData = _box.get('custom_categories');
    if (catData != null) {
      final List<dynamic> catList = jsonDecode(catData);
      _customCategories = catList.cast<String>().toSet();
    }

    // Load category icons
    final String? iconsData = _box.get('category_icons');
    if (iconsData != null) {
      final Map<String, dynamic> iconsMap = jsonDecode(iconsData);
      _categoryIcons = iconsMap.map((key, storedIcon) {
        // Emoji values persist verbatim; only numeric codePoints go through
        // legacy icon resolution.
        if (storedIcon != null && int.tryParse('$storedIcon') == null) {
          return MapEntry(key.toString(), storedIcon.toString());
        }
        final normalizedStoredValue = _storedValueForIcon(
          _resolveCategoryIcon(storedIcon),
        );
        if (storedIcon?.toString() != normalizedStoredValue) {
          iconsNeedSave = true;
        }
        return MapEntry(key.toString(), normalizedStoredValue);
      });
    }

    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      _subscriptions = jsonList
          .map((e) => FeedSubscription.fromJson(e))
          .toList();
    } else {
      _subscriptions = [];
      _saveSubscriptions();
    }

    // Ensure all categories have an assigned icon map
    for (var category in categories) {
      if (!_categoryIcons.containsKey(category)) {
        _assignDefaultIcon(category);
        iconsNeedSave = true;
      }
    }

    if (iconsNeedSave) {
      _saveCategoryIcons();
    }
    notifyListeners();
  }

  Future<void> _saveSubscriptions() async {
    final String data = jsonEncode(
      _subscriptions.map((s) => s.toJson()).toList(),
    );
    await _box.put('subscriptions', data);
  }

  Future<void> _saveCustomCategories() async {
    final String data = jsonEncode(_customCategories.toList());
    await _box.put('custom_categories', data);
  }

  Future<void> _saveCategoryIcons() async {
    final String data = jsonEncode(_categoryIcons);
    await _box.put('category_icons', data);
  }

  Future<void> _saveCategoryOrder() async {
    await _box.put('category_order', jsonEncode(_categoryOrder));
  }

  IconData _resolveCategoryIcon(dynamic storedIcon) {
    final int? parsedCodePoint = int.tryParse(storedIcon?.toString() ?? '');

    if (parsedCodePoint != null) {
      // 1. ÇÖZÜM: Sadece ve sadece categoryIconOptions listesindeki const ikonları eşleştiriyoruz.
      // Eğer listede yoksa, orElse bloğunda ASLA dinamik IconData üretmiyoruz, direkt default ikona düşürüyoruz.
      for (final icon in categoryIconOptions) {
        if (icon.codePoint == parsedCodePoint) {
          return icon;
        }
      }
    }

    // 2. Hiçbiri tutmazsa const olan varsayılan ikonu dönüyoruz (Icons.folder_outlined)
    return _defaultCategoryIcon;
  }

  String _storedValueForIcon(IconData icon) {
    final iconToStore = _supportedCategoryCodePoints.contains(icon.codePoint)
        ? icon
        : _defaultCategoryIcon;
    return iconToStore.codePoint.toString();
  }

  void _assignDefaultIcon(String category) {
    _categoryIcons[category] = _storedValueForIcon(_defaultCategoryIcon);
  }

  // ---------------------------------------------------------------------------
  // Category operations
  // ---------------------------------------------------------------------------

  /// The emoji stored for [category], or `null` when the category uses a
  /// legacy Material icon (numeric codePoint value).
  String? getCategoryEmoji(String category) {
    final storedIcon = _categoryIcons[category];
    if (storedIcon == null || int.tryParse(storedIcon) != null) {
      return null;
    }
    return storedIcon;
  }

  IconData getCategoryIcon(String category) {
    final storedIcon = _categoryIcons[category];
    if (storedIcon == null || int.tryParse(storedIcon) == null) {
      // Emoji or absent value — never normalize a user emoji into a
      // codePoint. A category unknown to the provider (e.g. one a feed
      // declares on its items) just renders the default icon — persisting
      // a default here would write the box on every such build.
      return _defaultCategoryIcon;
    }
    // Numeric values were normalized on load; an unknown codePoint (e.g. a
    // digit typed as an emoji) renders the default without a write here.
    return _resolveCategoryIcon(storedIcon);
  }

  /// Stores the first grapheme cluster of [emoji] as the category icon.
  /// An empty string restores the default icon.
  Future<void> setCategoryEmoji(String category, String emoji) async {
    final trimmed = emoji.trim();
    _categoryIcons[category] = trimmed.isEmpty
        ? _storedValueForIcon(_defaultCategoryIcon)
        : trimmed.characters.first;
    await _saveCategoryIcons();
    notifyListeners();
  }

  /// Whether [name] matches an existing category, ignoring case and
  /// surrounding whitespace — 'news', 'News', and ' NEWS ' are the same
  /// folder to the user.
  bool categoryExists(String name) {
    final needle = name.trim().toLowerCase();
    return categories.any((c) => c.toLowerCase() == needle);
  }

  /// Adds a new empty category/folder. Returns `false` if a category with
  /// the same name (ignoring case/whitespace) already exists.
  Future<bool> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || categoryExists(trimmed)) {
      return false;
    }
    _customCategories.add(trimmed);
    _assignDefaultIcon(trimmed);
    await _saveCustomCategories();
    await _saveCategoryIcons();
    notifyListeners();
    return true;
  }

  /// Renames [oldCategory] to [newCategory] across all subscriptions and
  /// custom categories. Returns `false` when [newCategory] names a
  /// *different* existing category (ignoring case) — renaming onto it
  /// would silently merge folders and clobber the target's icon.
  Future<bool> renameCategory(String oldCategory, String newCategory) async {
    final trimmed = newCategory.trim();
    if (trimmed.isEmpty) return false;
    final isSelf = trimmed.toLowerCase() == oldCategory.trim().toLowerCase();
    if (!isSelf && categoryExists(trimmed)) return false;
    // Exact self-rename is a no-op — without this the icon move below
    // would set the key and immediately remove it, wiping a custom icon.
    if (trimmed == oldCategory) return true;
    bool changed = false;
    for (int i = 0; i < _subscriptions.length; i++) {
      if (_subscriptions[i].category == oldCategory) {
        _subscriptions[i] = _subscriptions[i].copyWith(category: trimmed);
        changed = true;
      }
    }
    if (_customCategories.remove(oldCategory)) {
      _customCategories.add(trimmed);
      await _saveCustomCategories();
      changed = true;
    }

    // Move icon mapping
    if (_categoryIcons.containsKey(oldCategory)) {
      _categoryIcons[trimmed] = _categoryIcons[oldCategory]!;
      _categoryIcons.remove(oldCategory);
      await _saveCategoryIcons();
    } else if (changed) {
      _assignDefaultIcon(trimmed);
      await _saveCategoryIcons();
    }

    // Keep the user-defined position — a renamed category must not drop
    // into the sorted tail of categoriesOrdered.
    if (_categoryOrder.contains(oldCategory)) {
      _categoryOrder = _categoryOrder
          .map((c) => c == oldCategory ? trimmed : c)
          .toList();
      await _saveCategoryOrder();
    }

    if (changed) {
      await _saveSubscriptions();
      notifyListeners();
    }
    return true;
  }

  /// Removes a category and all feeds that belong to it.
  Future<void> removeCategory(String category) async {
    bool changed = false;
    final initialLength = _subscriptions.length;
    _subscriptions.removeWhere((s) => s.category == category);
    if (_subscriptions.length < initialLength) {
      await _saveSubscriptions();
      changed = true;
    }
    if (_customCategories.remove(category)) {
      await _saveCustomCategories();
      changed = true;
    }

    if (_categoryIcons.containsKey(category)) {
      _categoryIcons.remove(category);
      await _saveCategoryIcons();
    }

    if (changed) {
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Feed operations
  // ---------------------------------------------------------------------------

  /// Whether [url] canonically matches an existing subscription
  /// (scheme/host/trailing-slash normalized), so `HTTP://x.com/feed/` and
  /// `https://x.com/feed` count as the same feed.
  bool hasFeedUrl(String url) {
    final canonical = ArticleIdentity.normalizeFeedUrl(url);
    return _subscriptions.any(
      (s) => ArticleIdentity.normalizeFeedUrl(s.url) == canonical,
    );
  }

  /// Canonical URLs of current subscriptions, built once per batch instead
  /// of re-normalizing every subscription for every imported feed.
  Set<String> _canonicalFeedUrls() => {
    for (final s in _subscriptions) ArticleIdentity.normalizeFeedUrl(s.url),
  };

  /// URLs of subscriptions whose canonical form collides with another
  /// subscription — i.e. legacy duplicates added before normalization.
  Set<String> get duplicateFeedUrls {
    final seen = <String>{};
    final dupes = <String>{};
    for (final s in _subscriptions) {
      final canonical = ArticleIdentity.normalizeFeedUrl(s.url);
      if (!seen.add(canonical)) dupes.add(s.url);
    }
    return dupes;
  }

  /// Adds a new feed subscription. Returns `false` if a feed with the same
  /// URL already exists.
  Future<bool> addFeed(String url, String name, String category) async {
    if (!hasFeedUrl(url)) {
      _subscriptions.add(
        FeedSubscription(url: url, name: name, category: category),
      );

      // Ensure category has an icon
      if (!_categoryIcons.containsKey(category)) {
        _assignDefaultIcon(category);
        await _saveCategoryIcons();
      }

      await _saveSubscriptions();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Adds multiple feeds in one Hive write + one [notifyListeners] call.
  Future<void> addFeedsBatch(
    List<({String url, String name, String category})> feeds,
  ) async {
    bool changed = false;
    final known = _canonicalFeedUrls();
    for (final f in feeds) {
      if (!known.add(ArticleIdentity.normalizeFeedUrl(f.url))) continue;
      _subscriptions.add(
        FeedSubscription(url: f.url, name: f.name, category: f.category),
      );
      if (!_categoryIcons.containsKey(f.category)) {
        _assignDefaultIcon(f.category);
      }
      changed = true;
    }
    if (!changed) return;
    await _saveCategoryIcons();
    await _saveSubscriptions();
    notifyListeners();
  }

  /// Removes the feed with the given [url].
  Future<void> removeFeed(String url) async {
    _subscriptions.removeWhere((s) => s.url == url);
    await _saveSubscriptions();
    notifyListeners();
  }

  /// Moves a feed to a different category.
  Future<void> moveFeedToCategory(String feedUrl, String newCategory) async {
    final index = _subscriptions.indexWhere((s) => s.url == feedUrl);
    if (index != -1) {
      _subscriptions[index] = _subscriptions[index].copyWith(
        category: newCategory,
      );

      if (!_categoryIcons.containsKey(newCategory)) {
        _assignDefaultIcon(newCategory);
        await _saveCategoryIcons();
      }

      await _saveSubscriptions();
      notifyListeners();
    }
  }

  /// Edits a subscription's URL, name, and optional excluded keywords.
  /// Returns `false` — leaving the subscription untouched — when [newUrl]
  /// is not an absolute URI or canonically matches a *different*
  /// subscription.
  Future<bool> editSubscription(
    String oldUrl,
    String newUrl,
    String newName, {
    List<String>? excludedKeywords,
  }) async {
    final index = _subscriptions.indexWhere((s) => s.url == oldUrl);
    if (index == -1) return false;
    final uri = Uri.tryParse(newUrl);
    if (uri == null || !uri.isAbsolute) return false;
    final canonical = ArticleIdentity.normalizeFeedUrl(newUrl);
    final collides = _subscriptions.asMap().entries.any(
      (e) =>
          e.key != index &&
          ArticleIdentity.normalizeFeedUrl(e.value.url) == canonical,
    );
    if (collides) return false;
    _subscriptions[index] = _subscriptions[index].copyWith(
      url: newUrl,
      name: newName,
      excludedKeywords: excludedKeywords,
    );
    await _saveSubscriptions();
    notifyListeners();
    return true;
  }

  /// Toggles notification enabled/disabled for a specific feed.
  Future<void> toggleFeedNotifications(String feedUrl) async {
    final index = _subscriptions.indexWhere((s) => s.url == feedUrl);
    if (index != -1) {
      _subscriptions[index] = _subscriptions[index].copyWith(
        notificationsEnabled: !_subscriptions[index].notificationsEnabled,
      );
      await _saveSubscriptions();
      notifyListeners();
    }
  }

  /// Sets full-text mode for a feed: `null` = follow global, `true` = always on,
  /// `false` = always off.
  Future<void> setFullTextMode(String feedUrl, bool? value) async {
    final index = _subscriptions.indexWhere((s) => s.url == feedUrl);
    if (index != -1) {
      _subscriptions[index] = _subscriptions[index].copyWithFullTextMode(value);
      await _saveSubscriptions();
      notifyListeners();
    }
  }

  /// Imports a list of [FeedSubscription]s, skipping any whose URL already
  /// exists. Returns the number of newly added feeds.
  Future<int> importFeeds(List<FeedSubscription> feeds) async {
    int added = 0;
    bool newIcons = false;
    final known = _canonicalFeedUrls();
    for (final feed in feeds) {
      if (known.add(ArticleIdentity.normalizeFeedUrl(feed.url))) {
        _subscriptions.add(feed);
        added++;
        if (!_categoryIcons.containsKey(feed.category)) {
          _assignDefaultIcon(feed.category);
          newIcons = true;
        }
      }
    }

    if (newIcons) {
      await _saveCategoryIcons();
    }

    if (added > 0) {
      await _saveSubscriptions();
      notifyListeners();
    }
    return added;
  }

  /// Memory half of a reset whose storage stages already ran.
  void reloadAfterReset() {
    _subscriptions.clear();
    _customCategories.clear();
    _categoryIcons.clear();
    // This will load default sample feeds since the box is now empty.
    _loadSubscriptions();
  }
}
