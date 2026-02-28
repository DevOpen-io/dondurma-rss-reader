import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_subscription.dart';

/// Manages the user's RSS feed subscriptions and categories.
///
/// Supports add/remove/rename/move operations for both feeds and categories.
/// Categories come from two sources — feed subscriptions and standalone
/// custom categories — merged in the [categories] getter.
///
/// Persists data in the `'feeds'` Hive box under `'subscriptions'` and
/// `'custom_categories'` keys.
class SubscriptionProvider extends ChangeNotifier {
  List<FeedSubscription> _subscriptions = [];
  Set<String> _customCategories = {};

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

  /// Loads subscriptions and custom categories synchronously from Hive.
  /// Hive box reads are in-memory, so no await needed.
  void _loadSubscriptions() {
    final String? data = _box.get('subscriptions');

    // Load custom categories
    final String? catData = _box.get('custom_categories');
    if (catData != null) {
      final List<dynamic> catList = jsonDecode(catData);
      _customCategories = catList.cast<String>().toSet();
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

  // ---------------------------------------------------------------------------
  // Category operations
  // ---------------------------------------------------------------------------

  /// Adds a new empty category/folder. Returns `false` if it already exists.
  Future<bool> addCategory(String name) async {
    if (categories.contains(name)) {
      return false;
    }
    _customCategories.add(name);
    await _saveCustomCategories();
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
    for (final feed in feeds) {
      if (!_subscriptions.any((s) => s.url == feed.url)) {
        _subscriptions.add(feed);
        added++;
      }
    }
    if (added > 0) {
      await _saveSubscriptions();
      notifyListeners();
    }
    return added;
  }
}
