import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_subscription.dart';

class SubscriptionProvider extends ChangeNotifier {
  List<FeedSubscription> _subscriptions = [];

  List<FeedSubscription> get subscriptions => _subscriptions;

  Set<String> get categories {
    return _subscriptions.map((s) => s.category).toSet();
  }

  SubscriptionProvider() {
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    final box = Hive.box('settings');
    final String? data = box.get('subscriptions');

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
    final box = Hive.box('settings');
    final String data = jsonEncode(
      _subscriptions.map((s) => s.toJson()).toList(),
    );
    await box.put('subscriptions', data);
  }

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

  Future<void> removeFeed(String url) async {
    _subscriptions.removeWhere((s) => s.url == url);
    await _saveSubscriptions();
    notifyListeners();
  }

  Future<void> renameCategory(String oldCategory, String newCategory) async {
    bool changed = false;
    for (int i = 0; i < _subscriptions.length; i++) {
      if (_subscriptions[i].category == oldCategory) {
        _subscriptions[i] = FeedSubscription(
          url: _subscriptions[i].url,
          name: _subscriptions[i].name,
          category: newCategory,
        );
        changed = true;
      }
    }
    if (changed) {
      await _saveSubscriptions();
      notifyListeners();
    }
  }

  Future<void> removeCategory(String category) async {
    int initialLength = _subscriptions.length;
    _subscriptions.removeWhere((s) => s.category == category);
    if (_subscriptions.length < initialLength) {
      await _saveSubscriptions();
      notifyListeners();
    }
  }

  Future<void> editSubscription(
    String oldUrl,
    String newUrl,
    String newName,
  ) async {
    final index = _subscriptions.indexWhere((s) => s.url == oldUrl);
    if (index != -1) {
      _subscriptions[index] = FeedSubscription(
        url: newUrl,
        name: newName,
        category: _subscriptions[index].category,
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
