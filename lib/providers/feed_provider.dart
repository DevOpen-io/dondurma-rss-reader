import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_item.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';

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
  Set<String> _cachedItemIds = {};
  bool _isLoading = false;
  AppTheme _selectedTheme = AppTheme.system;
  int _offlineCacheLimit = 50;
  int _cacheIntervalSeconds = 0;
  Timer? _cacheTimer;
  int _itemRenderLimit = 100;

  List<FeedSubscription> get subscriptions => _subscriptions;
  List<FeedItem> get items => _items;
  Set<String> get cachedItemIds => _cachedItemIds;
  Set<String> get bookmarkedItemIds => _bookmarkedItemIds;
  bool get isLoading => _isLoading;
  AppTheme get selectedTheme => _selectedTheme;
  int get offlineCacheLimit => _offlineCacheLimit;
  int get cacheIntervalSeconds => _cacheIntervalSeconds;
  String? get selectedCategory => _selectedCategory;
  String? get selectedFeedUrl => _selectedFeedUrl;
  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  bool _showUnreadOnly = false;
  bool get showUnreadOnly => _showUnreadOnly;

  void setTheme(AppTheme theme) async {
    _selectedTheme = theme;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('selectedTheme', theme.name);
  }

  Future<void> setOfflineCacheLimit(int limit) async {
    _offlineCacheLimit = limit;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('offlineCacheLimit', limit);
    await _saveCachedItems();

    // Also restart timer logic
    _startCacheTimer(executeImmediately: false);
  }

  Future<void> setCacheIntervalSeconds(int interval) async {
    _cacheIntervalSeconds = interval;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('cacheIntervalSeconds', interval);

    // If user enabled interval caching (>0) and we can cache, immediately execute once
    final bool immediate = interval > 0 && _offlineCacheLimit > 0;
    _startCacheTimer(executeImmediately: immediate);
  }

  void _startCacheTimer({bool executeImmediately = false}) {
    _cacheTimer?.cancel();

    if (_offlineCacheLimit == 0) return;

    if (_cacheIntervalSeconds > 0) {
      if (executeImmediately) {
        refreshAll();
      }
      _cacheTimer = Timer.periodic(Duration(seconds: _cacheIntervalSeconds), (
        timer,
      ) {
        refreshAll();
      });
    }
  }

  void selectCategory(String? category) {
    _selectedCategory = category;
    _selectedFeedUrl = null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _itemRenderLimit = 50; // Reset pagination on search
    notifyListeners();
  }

  void toggleShowUnreadOnly() {
    _showUnreadOnly = !_showUnreadOnly;
    _itemRenderLimit = 50;
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

    // Check if showing unread strictly across the main view
    if (_showUnreadOnly) {
      filtered = filtered.where((i) => !i.isRead);
    }

    if (_selectedCategory != null) {
      filtered = filtered.where((i) => i.category == _selectedCategory);
    }
    if (_selectedFeedUrl != null) {
      filtered = filtered.where((i) => i.feedUrl == _selectedFeedUrl);
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where(
        (i) =>
            i.title.toLowerCase().contains(query) ||
            i.description.toLowerCase().contains(query) ||
            i.siteName.toLowerCase().contains(query),
      );
    }
    return filtered.toList();
  }

  List<FeedItem> get todayItems {
    final list = _filteredItems;
    final int targetLength = (list.length * 0.7).toInt();
    // Cap at itemRenderLimit
    return list
        .take(targetLength > _itemRenderLimit ? _itemRenderLimit : targetLength)
        .toList();
  }

  List<FeedItem> get yesterdayItems {
    final list = _filteredItems;
    final int todayLength = (list.length * 0.7).toInt();
    final remainingLimit = _itemRenderLimit - todayLength;

    if (remainingLimit <= 0) return []; // We exhausted limits in today

    return list.skip(todayLength).take(remainingLimit).toList();
  }

  bool _isLoadingMore = false;

  void loadMoreItems() {
    if (_isLoadingMore) return;

    final int maxAvailable = _filteredItems.length;
    if (_itemRenderLimit >= maxAvailable) return;

    _isLoadingMore = true;
    // Increase limit by 50 on scroll to bottom
    _itemRenderLimit += 50;
    notifyListeners();

    // Prevent scroll physics bounce from spamming the load trigger
    Future.delayed(const Duration(milliseconds: 250), () {
      _isLoadingMore = false;
    });
  }

  Set<String> get categories {
    return _subscriptions.map((s) => s.category).toSet();
  }

  FeedProvider() {
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    final box = Hive.box('settings');

    _offlineCacheLimit = box.get('offlineCacheLimit', defaultValue: 50);
    _cacheIntervalSeconds = box.get('cacheIntervalSeconds', defaultValue: 0);

    // Load read item IDs
    final List<dynamic>? readIds = box.get('readItemIds');
    if (readIds != null) {
      _readItemIds = readIds.cast<String>().toSet();
    }

    // Load bookmarked items (full objects)
    final String? bookmarkedItemsData = box.get('bookmarkedItemsJson');
    if (bookmarkedItemsData != null) {
      final List<dynamic> jsonList = jsonDecode(bookmarkedItemsData);
      _savedBookmarks = jsonList.map((e) => FeedItem.fromJson(e)).toList();
      _bookmarkedItemIds = _savedBookmarks.map((e) => e.id).toSet();
    } else {
      // Fallback for legacy ID-only bookmarks
      final List<dynamic>? bookmarkedIds = box.get('bookmarkedItemIds');
      if (bookmarkedIds != null) {
        _bookmarkedItemIds = bookmarkedIds.cast<String>().toSet();
      }
    }

    // Load cached offline items
    final String? cachedItemsData = box.get('cachedItemsJson');
    if (cachedItemsData != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(cachedItemsData);
        _items = jsonList.map((e) => FeedItem.fromJson(e)).toList();
        _cachedItemIds = _items.map((e) => e.id).toSet();
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading cached items: $e');
      }
    }

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

    final themeName = box.get('selectedTheme');
    if (themeName != null) {
      try {
        _selectedTheme = AppTheme.values.firstWhere((e) => e.name == themeName);
      } catch (_) {
        _selectedTheme = AppTheme.system;
      }
    } else {
      final isDark = box.get('isDarkMode', defaultValue: true);
      _selectedTheme = isDark ? AppTheme.dark : AppTheme.system;
    }

    notifyListeners();

    // Initial refresh of all feeds
    await refreshAll();
    // Start the cache timer after initial load
    _startCacheTimer(executeImmediately: false);
  }

  Future<void> _saveSubscriptions() async {
    final box = Hive.box('settings');
    final String data = jsonEncode(
      _subscriptions.map((s) => s.toJson()).toList(),
    );
    await box.put('subscriptions', data);
  }

  Future<void> _saveReadStates() async {
    final box = Hive.box('settings');
    await box.put('readItemIds', _readItemIds.toList());
  }

  Future<void> _saveBookmarkStates() async {
    final box = Hive.box('settings');

    // Save full items as JSON
    final String data = jsonEncode(
      _savedBookmarks.map((b) => b.toJson()).toList(),
    );
    await box.put('bookmarkedItemsJson', data);

    // Still save IDs for quick fallback or legacy compliance
    await box.put('bookmarkedItemIds', _bookmarkedItemIds.toList());
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

    await _saveCachedItems();
  }

  Future<void> _saveCachedItems() async {
    final box = Hive.box('settings');
    final itemsToCache = _items.take(_offlineCacheLimit).toList();
    _cachedItemIds = itemsToCache.map((e) => e.id).toSet();
    notifyListeners();
    final String encodedData = jsonEncode(
      itemsToCache.map((e) => e.toJson()).toList(),
    );
    await box.put('cachedItemsJson', encodedData);
  }

  Future<void> clearCache() async {
    final box = Hive.box('settings');
    _cachedItemIds.clear();
    await box.delete('cachedItemsJson');
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

  Future<void> toggleReadStatus(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      final current = _items[index];
      final newStatus = !current.isRead;

      _items[index] = current.copyWith(isRead: newStatus);

      if (newStatus) {
        _readItemIds.add(id);
      } else {
        _readItemIds.remove(id);
      }

      notifyListeners();
      await _saveReadStates();
    }
  }
}
