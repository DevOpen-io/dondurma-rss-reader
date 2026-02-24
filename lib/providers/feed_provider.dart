import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/feed_item.dart';
import '../services/feed_service.dart';

class FeedSubscription {
  final String url;
  final String name;
  final String category;

  FeedSubscription({
    required this.url,
    required this.name,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'category': category,
  };

  factory FeedSubscription.fromJson(Map<String, dynamic> json) =>
      FeedSubscription(
        url: json['url'],
        name: json['name'],
        category: json['category'],
      );
}

class FeedProvider extends ChangeNotifier {
  final FeedService _feedService = FeedService();

  List<FeedSubscription> _subscriptions = [];
  List<FeedItem> _items = [];
  Set<String> _readItemIds = {};
  bool _isLoading = false;

  List<FeedSubscription> get subscriptions => _subscriptions;
  List<FeedItem> get items => _items;
  bool get isLoading => _isLoading;

  List<FeedItem> get todayItems {
    // Highly simplified: realistically we'd sort by pubDate.
    // Assuming everything fetched currently is "today" for demonstration
    // unless explicitly grouped otherwise.
    return _items.take((_items.length * 0.7).toInt()).toList();
  }

  List<FeedItem> get yesterdayItems {
    return _items.skip((_items.length * 0.7).toInt()).toList();
  }

  Set<String> get categories {
    return _subscriptions.map((s) => s.category).toSet();
  }

  FeedProvider() {
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();

    // Load read item IDs
    final List<String>? readIds = prefs.getStringList('readItemIds');
    if (readIds != null) {
      _readItemIds = readIds.toSet();
    }

    final String? data = prefs.getString('subscriptions');
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
    await refreshAll();
  }

  Future<void> _saveSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(
      _subscriptions.map((s) => s.toJson()).toList(),
    );
    await prefs.setString('subscriptions', data);
  }

  Future<void> _saveReadStates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('readItemIds', _readItemIds.toList());
  }

  Future<void> addFeed(String url, String name, String category) async {
    if (!_subscriptions.any((s) => s.url == url)) {
      _subscriptions.add(
        FeedSubscription(url: url, name: name, category: category),
      );
      await _saveSubscriptions();
      await refreshAll();
    }
  }

  Future<void> removeFeed(String url) async {
    _subscriptions.removeWhere((s) => s.url == url);
    await _saveSubscriptions();
    await refreshAll();
  }

  Future<void> refreshAll() async {
    _isLoading = true;
    notifyListeners();

    List<FeedItem> allItems = [];
    for (var sub in _subscriptions) {
      final fetchedItems = await _feedService.fetchFeed(sub.url, sub.category);
      // Map isRead status when fetching
      allItems.addAll(
        fetchedItems.map((item) {
          if (_readItemIds.contains(item.id)) {
            return item.copyWith(isRead: true);
          }
          return item;
        }),
      );
    }

    // Simplistic sorting just to randomize a bit for the demo,
    // usually we'd sort by pubDate descending here.
    allItems.shuffle();

    _items = allItems;
    _isLoading = false;
    notifyListeners();
  }

  void toggleBookmark(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      final current = _items[index];
      _items[index] = current.copyWith(isBookmarked: !current.isBookmarked);
      notifyListeners();
      // In a full app, bookmarked status should also be persisted to SharedPreferences
    }
  }

  Future<void> markAsRead(String id) async {
    if (!_readItemIds.contains(id)) {
      _readItemIds.add(id);

      final index = _items.indexWhere((item) => item.id == id);
      if (index != -1) {
        _items[index] = _items[index].copyWith(isRead: true);
        notifyListeners();
      }

      await _saveReadStates();
    }
  }
}
