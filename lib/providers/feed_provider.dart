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
  List<FeedItem> _savedBookmarks = [];
  String? _selectedCategory;
  String? _selectedFeedUrl;
  Set<String> _readItemIds = {};
  Set<String> _bookmarkedItemIds = {};
  bool _isLoading = false;
  bool _isDarkMode = true;

  List<FeedSubscription> get subscriptions => _subscriptions;
  List<FeedItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get isDarkMode => _isDarkMode;
  String? get selectedCategory => _selectedCategory;
  String? get selectedFeedUrl => _selectedFeedUrl;

  void toggleTheme(bool isDark) async {
    _isDarkMode = isDark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
  }

  void selectCategory(String? category) {
    _selectedCategory = category;
    _selectedFeedUrl = null;
    notifyListeners();
  }

  void selectFeed(String? feedUrl) {
    _selectedFeedUrl = feedUrl;
    if (feedUrl != null) {
      final sub = _subscriptions.firstWhere(
        (s) => s.url == feedUrl,
        orElse: () => FeedSubscription(name: '', url: '', category: ''),
      );
      if (sub.url.isNotEmpty) {
        _selectedCategory = sub.category;
      }
    }
    notifyListeners();
  }

  List<FeedItem> get bookmarkedItems =>
      _items.where((i) => i.isBookmarked).toList();

  List<FeedItem> get _filteredItems {
    Iterable<FeedItem> filtered = _items;
    if (_selectedCategory != null) {
      filtered = filtered.where((i) => i.category == _selectedCategory);
    }
    if (_selectedFeedUrl != null) {
      filtered = filtered.where((i) => i.feedUrl == _selectedFeedUrl);
    }
    return filtered.toList();
  }

  List<FeedItem> get todayItems {
    // Highly simplified: realistically we'd sort by pubDate.
    // Assuming everything fetched currently is "today" for demonstration
    // unless explicitly grouped otherwise.
    final list = _filteredItems;
    return list.take((list.length * 0.7).toInt()).toList();
  }

  List<FeedItem> get yesterdayItems {
    final list = _filteredItems;
    return list.skip((list.length * 0.7).toInt()).toList();
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

    // Load bookmarked items (full objects)
    final String? bookmarkedItemsData = prefs.getString('bookmarkedItemsJson');
    if (bookmarkedItemsData != null) {
      final List<dynamic> jsonList = jsonDecode(bookmarkedItemsData);
      _savedBookmarks = jsonList.map((e) => FeedItem.fromJson(e)).toList();
      _bookmarkedItemIds = _savedBookmarks.map((e) => e.id).toSet();
    } else {
      // Fallback for legacy ID-only bookmarks
      final List<String>? bookmarkedIds = prefs.getStringList(
        'bookmarkedItemIds',
      );
      if (bookmarkedIds != null) {
        _bookmarkedItemIds = bookmarkedIds.toSet();
      }
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

    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    notifyListeners();

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

  Future<void> _saveBookmarkStates() async {
    final prefs = await SharedPreferences.getInstance();

    // Save full items as JSON
    final String data = jsonEncode(
      _savedBookmarks.map((b) => b.toJson()).toList(),
    );
    await prefs.setString('bookmarkedItemsJson', data);

    // Still save IDs for quick fallback or legacy compliance
    await prefs.setStringList('bookmarkedItemIds', _bookmarkedItemIds.toList());
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
      await refreshAll();
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
      await refreshAll();
    }
  }

  Future<void> refreshAll() async {
    _isLoading = true;
    notifyListeners();

    // Fetch all feeds concurrently
    final futures = _subscriptions.map((sub) async {
      try {
        final fetchedItems = await _feedService.fetchFeed(
          sub.url,
          sub.category,
        );
        return fetchedItems.map((item) {
          bool isRead = _readItemIds.contains(item.id);
          bool isBookmarked = _bookmarkedItemIds.contains(item.id);

          if (isRead || isBookmarked) {
            return item.copyWith(isRead: isRead, isBookmarked: isBookmarked);
          }
          return item;
        }).toList();
      } catch (e) {
        debugPrint('Error fetching feed \${sub.url}: \$e');
        return <FeedItem>[];
      }
    });

    final results = await Future.wait(futures);

    List<FeedItem> allItems = [];
    for (var items in results) {
      allItems.addAll(items);
    }

    // Ensure our saved bookmarks are always present in our known items array
    // so they are visible even if the RSS feed dropped them.
    for (var saved in _savedBookmarks) {
      if (!allItems.any((item) => item.id == saved.id)) {
        allItems.add(saved);
      }
    }

    // Sort by pubDate descending (newest first)
    allItems.sort((a, b) {
      if (a.pubDate == null && b.pubDate == null) return 0;
      if (a.pubDate == null) return 1;
      if (b.pubDate == null) return -1;
      return b.pubDate!.compareTo(a.pubDate!);
    });

    _items = allItems;
    _isLoading = false;
    notifyListeners();
  }

  void toggleBookmark(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      final current = _items[index];
      final newStatus = !current.isBookmarked;

      final updatedItem = current.copyWith(isBookmarked: newStatus);

      _items[index] = updatedItem;

      if (newStatus) {
        _bookmarkedItemIds.add(id);
        if (!_savedBookmarks.any((b) => b.id == id)) {
          _savedBookmarks.add(updatedItem);
        }
      } else {
        _bookmarkedItemIds.remove(id);
        _savedBookmarks.removeWhere((b) => b.id == id);
      }

      notifyListeners();
      _saveBookmarkStates();
    } else {
      // In case we are trying to unbookmark something that only exists in saved memory
      final savedIndex = _savedBookmarks.indexWhere((item) => item.id == id);
      if (savedIndex != -1) {
        _savedBookmarks.removeAt(savedIndex);
        _bookmarkedItemIds.remove(id);
        notifyListeners();
        _saveBookmarkStates();
      }
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
