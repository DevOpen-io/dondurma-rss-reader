import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_item.dart';
import '../services/feed_service.dart';
import 'subscription_provider.dart';
import 'bookmark_provider.dart';
import 'settings_provider.dart';

class FeedProvider extends ChangeNotifier {
  final FeedService _feedService = FeedService();

  List<FeedItem> _items = [];
  String? _selectedCategory;
  String? _selectedFeedUrl;
  Set<String> _readItemIds = {};
  Set<String> _cachedItemIds = {};
  bool _isLoading = false;
  int _itemRenderLimit = 100;

  Timer? _cacheTimer;

  // Dependencies that need to be updated via ProxyProvider
  SubscriptionProvider? subscriptionProvider;
  SettingsProvider? settingsProvider;
  BookmarkProvider? bookmarkProvider;

  List<FeedItem> get items => _items;
  Set<String> get cachedItemIds => _cachedItemIds;
  bool get isLoading => _isLoading;
  String? get selectedCategory => _selectedCategory;
  String? get selectedFeedUrl => _selectedFeedUrl;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool _showUnreadOnly = false;
  bool get showUnreadOnly => _showUnreadOnly;

  FeedProvider() {
    _loadState();
  }

  void update(
    SubscriptionProvider sub,
    SettingsProvider set,
    BookmarkProvider book,
  ) {
    final bool isFirstUpdate = subscriptionProvider == null;
    subscriptionProvider = sub;
    settingsProvider = set;
    bookmarkProvider = book;

    if (isFirstUpdate) {
      refreshAll();
    }

    _manageCacheTimer();
  }

  void _manageCacheTimer() {
    _cacheTimer?.cancel();
    if (settingsProvider == null) return;
    final interval = settingsProvider!.cacheIntervalSeconds;
    final syncEnabled = settingsProvider!.syncBackground;

    if (interval > 0 && syncEnabled) {
      _cacheTimer = Timer.periodic(Duration(seconds: interval), (timer) {
        refreshAll();
      });
    }
  }

  Future<void> _loadState() async {
    final box = Hive.box('settings');

    final List<dynamic>? readIds = box.get('readItemIds');
    if (readIds != null) {
      _readItemIds = readIds.cast<String>().toSet();
    }

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
  }

  Future<void> _saveReadStates() async {
    final box = Hive.box('settings');
    await box.put('readItemIds', _readItemIds.toList());
  }

  void selectCategory(String? category) {
    _selectedCategory = category;
    _selectedFeedUrl = null;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _itemRenderLimit = 50;
    notifyListeners();
  }

  void toggleShowUnreadOnly() {
    _showUnreadOnly = !_showUnreadOnly;
    _itemRenderLimit = 50;
    notifyListeners();
  }

  void selectFeed(String? feedUrl) {
    _selectedFeedUrl = feedUrl;
    if (feedUrl != null && subscriptionProvider != null) {
      try {
        final sub = subscriptionProvider!.subscriptions.firstWhere(
          (s) => s.url == feedUrl,
        );
        _selectedCategory = sub.category;
      } catch (_) {}
    }
    notifyListeners();
  }

  List<FeedItem> get _filteredItems {
    Iterable<FeedItem> filtered = _items;

    if (_showUnreadOnly) {
      filtered = filtered.where((i) => !_readItemIds.contains(i.id));
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

    // Update dynamic properties
    return filtered.map((item) {
      bool isRead = _readItemIds.contains(item.id);
      bool isBookmarked = bookmarkProvider?.isBookmarked(item.id) ?? false;
      return item.copyWith(isRead: isRead, isBookmarked: isBookmarked);
    }).toList();
  }

  List<FeedItem> get todayItems {
    final list = _filteredItems;
    final int targetLength = (list.length * 0.7).toInt();
    return list
        .take(targetLength > _itemRenderLimit ? _itemRenderLimit : targetLength)
        .toList();
  }

  List<FeedItem> get yesterdayItems {
    final list = _filteredItems;
    final int todayLength = (list.length * 0.7).toInt();
    final remainingLimit = _itemRenderLimit - todayLength;

    if (remainingLimit <= 0) return [];

    return list.skip(todayLength).take(remainingLimit).toList();
  }

  bool _isLoadingMore = false;

  void loadMoreItems() {
    if (_isLoadingMore) return;

    final int maxAvailable = _filteredItems.length;
    if (_itemRenderLimit >= maxAvailable) return;

    _isLoadingMore = true;
    _itemRenderLimit += 50;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 250), () {
      _isLoadingMore = false;
    });
  }

  bool isRead(String id) => _readItemIds.contains(id);

  Future<void> refreshAll() async {
    if (subscriptionProvider == null) return;

    _isLoading = true;
    notifyListeners();

    final futures = subscriptionProvider!.subscriptions.map((sub) async {
      try {
        return await _feedService.fetchFeed(sub.url, sub.category);
      } catch (e) {
        debugPrint('Error fetching feed ${sub.url}: $e');
        return <FeedItem>[];
      }
    });

    final results = await Future.wait(futures);

    List<FeedItem> allItems = [];
    for (var items in results) {
      allItems.addAll(items);
    }

    if (bookmarkProvider != null) {
      for (var saved in bookmarkProvider!.bookmarkedItems) {
        if (!allItems.any((item) => item.id == saved.id)) {
          allItems.add(saved);
        }
      }
    }

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
    if (settingsProvider == null) return;
    final limit = settingsProvider!.offlineCacheLimit;

    final box = Hive.box('settings');
    final itemsToCache = _items.take(limit).toList();
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

  Future<void> markAsRead(String id) async {
    if (!_readItemIds.contains(id)) {
      _readItemIds.add(id);
      notifyListeners();
      await _saveReadStates();
    }
  }

  Future<void> toggleReadStatus(String id) async {
    if (_readItemIds.contains(id)) {
      _readItemIds.remove(id);
    } else {
      _readItemIds.add(id);
    }
    notifyListeners();
    await _saveReadStates();
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    super.dispose();
  }
}
