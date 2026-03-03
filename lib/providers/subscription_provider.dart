import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_subscription.dart';

/// Manages the user's RSS feed subscriptions, categories, and their icons.
///
/// Supports add/remove/rename/move operations for both feeds and categories.
/// Categories come from two sources — feed subscriptions and standalone
/// custom categories — merged in the [categories] getter.
///
/// Persists data in the `'feeds'` Hive box under `'subscriptions'`,
/// `'custom_categories'`, and `'category_icons'` keys.
class SubscriptionProvider extends ChangeNotifier {
  List<FeedSubscription> _subscriptions = [];
  Set<String> _customCategories = {};
  Map<String, String> _categoryIcons = {};

  /// All current feed subscriptions.
  List<FeedSubscription> get subscriptions => _subscriptions;

  /// The union of categories derived from subscriptions and standalone
  /// custom (possibly empty) categories.
  Set<String> get categories {
    final fromSubs = _subscriptions.map((s) => s.category).toSet();
    return fromSubs.union(_customCategories);
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
      _categoryIcons = iconsMap.cast<String, String>();
    }

    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      _subscriptions = jsonList
          .map((e) => FeedSubscription.fromJson(e))
          .toList();
    } else {
      // Default sample feeds if user has none
      _subscriptions = [
        FeedSubscription(
          url: 'https://techcrunch.com/feed/',
          name: 'TechCrunch',
          category: 'Technology',
        ),
        FeedSubscription(
          url: 'https://www.theverge.com/rss/index.xml',
          name: 'The Verge',
          category: 'Technology',
        ),
        FeedSubscription(
          url: 'https://news.ycombinator.com/rss',
          name: 'Hacker News',
          category: 'All News',
        ),
      ];
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

  void _assignDefaultIcon(String category) {
    _categoryIcons[category] = '📁';
  }

  // ---------------------------------------------------------------------------
  // Category operations
  // ---------------------------------------------------------------------------

  String getCategoryIcon(String category) {
    if (!_categoryIcons.containsKey(category)) {
      _assignDefaultIcon(category);
      _saveCategoryIcons();
    }
    return _categoryIcons[category] ?? '📁';
  }

  Future<void> setCategoryIcon(String category, String icon) async {
    _categoryIcons[category] = icon;
    await _saveCategoryIcons();
    notifyListeners();
  }

  /// Adds a new empty category/folder. Returns `false` if it already exists.
  Future<bool> addCategory(String name) async {
    if (categories.contains(name)) {
      return false;
    }
    _customCategories.add(name);
    _assignDefaultIcon(name);
    await _saveCustomCategories();
    await _saveCategoryIcons();
    notifyListeners();
    return true;
  }

  /// Renames [oldCategory] to [newCategory] across all subscriptions and
  /// custom categories.
  Future<void> renameCategory(String oldCategory, String newCategory) async {
    bool changed = false;
    for (int i = 0; i < _subscriptions.length; i++) {
      if (_subscriptions[i].category == oldCategory) {
        _subscriptions[i] = _subscriptions[i].copyWith(category: newCategory);
        changed = true;
      }
    }
    if (_customCategories.remove(oldCategory)) {
      _customCategories.add(newCategory);
      await _saveCustomCategories();
      changed = true;
    }

    // Move icon mapping
    if (_categoryIcons.containsKey(oldCategory)) {
      _categoryIcons[newCategory] = _categoryIcons[oldCategory]!;
      _categoryIcons.remove(oldCategory);
      await _saveCategoryIcons();
    } else if (changed) {
      _assignDefaultIcon(newCategory);
      await _saveCategoryIcons();
    }

    if (changed) {
      await _saveSubscriptions();
      notifyListeners();
    }
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

  /// Adds a new feed subscription. Returns `false` if a feed with the same
  /// URL already exists.
  Future<bool> addFeed(String url, String name, String category) async {
    if (!_subscriptions.any((s) => s.url == url)) {
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
  Future<void> editSubscription(
    String oldUrl,
    String newUrl,
    String newName, {
    List<String>? excludedKeywords,
  }) async {
    final index = _subscriptions.indexWhere((s) => s.url == oldUrl);
    if (index != -1) {
      _subscriptions[index] = _subscriptions[index].copyWith(
        url: newUrl,
        name: newName,
        excludedKeywords: excludedKeywords,
      );
      await _saveSubscriptions();
      notifyListeners();
    }
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

  /// Toggles full-text extraction enabled/disabled for a specific feed.
  Future<void> toggleFullText(String feedUrl) async {
    final index = _subscriptions.indexWhere((s) => s.url == feedUrl);
    if (index != -1) {
      _subscriptions[index] = _subscriptions[index].copyWith(
        fullTextEnabled: !_subscriptions[index].fullTextEnabled,
      );
      await _saveSubscriptions();
      notifyListeners();
    }
  }

  /// Imports a list of [FeedSubscription]s, skipping any whose URL already
  /// exists. Returns the number of newly added feeds.
  Future<int> importFeeds(List<FeedSubscription> feeds) async {
    int added = 0;
    bool newIcons = false;
    for (final feed in feeds) {
      if (!_subscriptions.any((s) => s.url == feed.url)) {
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
}
