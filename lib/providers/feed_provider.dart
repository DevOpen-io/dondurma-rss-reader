import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_item.dart';
import '../services/feed_service.dart';
import '../services/notification_service.dart';
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
  bool _isOffline = false;

  /// How many items from [_filteredItems] are currently rendered.
  int _itemRenderLimit = 50;

  /// Incremented in batches when the user scrolls near the bottom.
  static const int _pageSize = 50;

  bool _isLoadingMore = false;

  Timer? _cacheTimer;

  /// Tracks whether the first load has completed, so we don't fire
  /// notifications on initial startup.
  bool _hasLoadedOnce = false;

  // Dependencies that need to be updated via ProxyProvider
  SubscriptionProvider? subscriptionProvider;
  SettingsProvider? settingsProvider;
  BookmarkProvider? bookmarkProvider;

  List<FeedItem> get items => _items;
  Set<String> get cachedItemIds => _cachedItemIds;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isOffline => _isOffline;
  String? get selectedCategory => _selectedCategory;
  String? get selectedFeedUrl => _selectedFeedUrl;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  bool _showUnreadOnly = false;
  bool get showUnreadOnly => _showUnreadOnly;

  /// Whether there are more items beyond the current render window.
  bool get hasMoreItems => _itemRenderLimit < _filteredItems.length;

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
    } else {
      // Re-filter items immediately if dependencies (like keywords) changed.
      Future.microtask(() => notifyListeners());
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
    final box = Hive.box('feeds');

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
    final box = Hive.box('feeds');
    await box.put('readItemIds', _readItemIds.toList());
  }

  void selectCategory(String? category) {
    _selectedCategory = category;
    _selectedFeedUrl = null;
    _itemRenderLimit = _pageSize;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _itemRenderLimit = _pageSize;
    notifyListeners();
  }

  void toggleShowUnreadOnly() {
    _showUnreadOnly = !_showUnreadOnly;
    _itemRenderLimit = _pageSize;
    notifyListeners();
  }

  void selectFeed(String? feedUrl) {
    _selectedFeedUrl = feedUrl;
    _itemRenderLimit = _pageSize;
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

    // Apply Keyword Filtering dynamically
    final globalKeywords = settingsProvider?.globalExcludedKeywords ?? [];
    final Map<String, List<String>> feedKeywordsMap = {};
    if (subscriptionProvider != null) {
      for (var sub in subscriptionProvider!.subscriptions) {
        feedKeywordsMap[sub.url] = sub.excludedKeywords;
      }
    }

    if (globalKeywords.isNotEmpty || feedKeywordsMap.isNotEmpty) {
      filtered = filtered.where((item) {
        final feedKeywords = feedKeywordsMap[item.feedUrl] ?? [];
        if (globalKeywords.isEmpty && feedKeywords.isEmpty) return true;

        bool containsKeyword(List<String> keywords) {
          for (var kw in keywords) {
            final lowerKw = kw.toLowerCase();
            // Match with word boundaries to avoid partial matches (e.g. "ad" vs "ready").
            final RegExp regex = RegExp(
              r'\b' + RegExp.escape(lowerKw) + r'\b',
              caseSensitive: false,
            );
            if (regex.hasMatch(item.title) ||
                regex.hasMatch(item.description)) {
              return true;
            }
          }
          return false;
        }

        return !containsKeyword(globalKeywords) &&
            !containsKeyword(feedKeywords);
      });
    }

    // Update dynamic properties
    return filtered.map((item) {
      bool isRead = _readItemIds.contains(item.id);
      bool isBookmarked = bookmarkProvider?.isBookmarked(item.id) ?? false;
      return item.copyWith(isRead: isRead, isBookmarked: isBookmarked);
    }).toList();
  }

  /// The current render window — a slice of [_filteredItems] up to
  /// [_itemRenderLimit].
  List<FeedItem> get _visibleItems {
    final all = _filteredItems;
    if (_itemRenderLimit >= all.length) return all;
    return all.sublist(0, _itemRenderLimit);
  }

  // ---------------------------------------------------------------------------
  // Date-based section getters
  // ---------------------------------------------------------------------------

  static bool _isToday(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  static bool _isYesterday(DateTime? date) {
    if (date == null) return false;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  /// Items published today, within the current render window.
  List<FeedItem> get todayItems =>
      _visibleItems.where((i) => _isToday(i.pubDate)).toList();

  /// Items published yesterday, within the current render window.
  List<FeedItem> get yesterdayItems =>
      _visibleItems.where((i) => _isYesterday(i.pubDate)).toList();

  /// Items older than yesterday (or with no date), within the current render
  /// window.
  List<FeedItem> get olderItems => _visibleItems
      .where((i) => !_isToday(i.pubDate) && !_isYesterday(i.pubDate))
      .toList();

  // ---------------------------------------------------------------------------
  // Pagination
  // ---------------------------------------------------------------------------

  /// Loads the next page of items. Safe to call multiple times — debounced
  /// internally.
  void loadMoreItems() {
    if (_isLoadingMore) return;
    if (!hasMoreItems) return;

    _isLoadingMore = true;
    notifyListeners();

    // Simulate a brief async delay so the loading indicator is visible.
    Future.delayed(const Duration(milliseconds: 300), () {
      _itemRenderLimit += _pageSize;
      _isLoadingMore = false;
      notifyListeners();
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

    // Capture old item IDs for notification diff
    final oldItemIds = _items.map((e) => e.id).toSet();

    List<FeedItem> freshItems = [];
    for (var items in results) {
      freshItems.addAll(items);
    }

    // If every single fetch failed (e.g. device is offline), keep the
    // previously loaded items so cached articles remain visible.
    final bool fetchedAnything = freshItems.isNotEmpty;

    if (fetchedAnything) {
      // 1) Merge bookmarks into the fresh list so they are always visible.
      if (bookmarkProvider != null) {
        for (var saved in bookmarkProvider!.bookmarkedItems) {
          if (!freshItems.any((item) => item.id == saved.id)) {
            freshItems.add(saved);
          }
        }
      }

      freshItems.sort((a, b) {
        if (a.pubDate == null && b.pubDate == null) return 0;
        if (a.pubDate == null) return 1;
        if (b.pubDate == null) return -1;
        return b.pubDate!.compareTo(a.pubDate!);
      });

      _items = freshItems;
    } else {
      // Offline: keep existing _items but still ensure bookmarks are present.
      if (bookmarkProvider != null) {
        for (var saved in bookmarkProvider!.bookmarkedItems) {
          if (!_items.any((item) => item.id == saved.id)) {
            _items.add(saved);
          }
        }
      }
      debugPrint('FeedProvider: all fetches failed — showing cached items.');
    }

    _isOffline = !fetchedAnything;
    _isLoading = false;
    notifyListeners();

    // Fire notifications for newly discovered items (skip the initial load).
    if (fetchedAnything && _hasLoadedOnce) {
      _notifyNewArticles(oldItemIds, freshItems);
    }
    _hasLoadedOnce = true;

    // Only persist a new cache snapshot when we actually fetched fresh data.
    if (fetchedAnything) {
      await _saveCachedItems();
    }
  }

  /// Computes newly discovered articles and triggers a notification.
  void _notifyNewArticles(Set<String> oldItemIds, List<FeedItem> freshItems) {
    if (settingsProvider == null || subscriptionProvider == null) return;

    // Build a set of feed URLs that have notifications disabled
    final mutedFeedUrls = subscriptionProvider!.subscriptions
        .where((s) => !s.notificationsEnabled)
        .map((s) => s.url)
        .toSet();

    final newItems = freshItems
        .where(
          (item) =>
              !oldItemIds.contains(item.id) &&
              !mutedFeedUrls.contains(item.feedUrl),
        )
        .toList();

    if (newItems.isEmpty) return;

    NotificationService.instance.showNewArticlesNotification(
      newItems: newItems,
      notificationsEnabled: settingsProvider!.notificationsEnabled,
      digestMode: settingsProvider!.digestMode,
      quietHoursStart: settingsProvider!.quietHoursStart,
      quietHoursEnd: settingsProvider!.quietHoursEnd,
    );
  }

  Future<void> _saveCachedItems() async {
    if (settingsProvider == null) return;
    final int limit = settingsProvider!.offlineCacheLimit;

    // offlineCacheLimit == 0 means "no offline cache" — don't save anything
    // and don't wipe an existing cache.
    if (limit == 0) return;

    final box = Hive.box('feeds');
    final itemsToCache = _items.take(limit).toList();
    _cachedItemIds = itemsToCache.map((e) => e.id).toSet();
    notifyListeners();

    final String encodedData = jsonEncode(
      itemsToCache.map((e) => e.toJson()).toList(),
    );
    await box.put('cachedItemsJson', encodedData);
  }

  Future<void> clearCache() async {
    final box = Hive.box('feeds');
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
