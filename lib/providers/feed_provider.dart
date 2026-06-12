import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, listEquals;
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/feed_item.dart';
import '../services/feed_service.dart';
import '../services/notification_service.dart';
import 'bookmark_provider.dart';
import 'settings_provider.dart';
import 'subscription_provider.dart';

/// Core provider that manages fetching, caching, filtering, and paginated
/// rendering of RSS/Atom feed items.
///
/// Connected to [SubscriptionProvider], [SettingsProvider], and
/// [BookmarkProvider] via `ChangeNotifierProxyProvider3` in `main.dart`.
class FeedProvider extends ChangeNotifier {
  final FeedService _feedService = FeedService();

  /// Max concurrent feed HTTP requests. Limits socket/memory pressure on
  /// devices with constrained network stacks.
  static const _fetchConcurrency = 5;

  List<FeedItem> _items = [];
  String? _selectedCategory;
  String? _selectedFeedUrl;
  Set<String> _readItemIds = {};
  Set<String> _cachedItemIds = {};
  bool _isLoading = false;
  bool _isOffline = false;

  /// How many items from the filtered list are currently rendered.
  int _itemRenderLimit = 50;

  /// Incremented in batches when the user scrolls near the bottom.
  static const int _pageSize = 50;

  bool _isLoadingMore = false;

  Timer? _cacheTimer;

  /// Tracks whether the first load has completed, so we don't fire
  /// notifications on initial startup.
  bool _hasLoadedOnce = false;

  /// Throttles in-app notifications to at most one burst per 15 minutes.
  DateTime? _lastNotificationTime;

  // ---------------------------------------------------------------------------
  // Sync metrics (for the debug screen)
  // ---------------------------------------------------------------------------

  /// Timestamp of the last successful sync completion.
  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// How long the last sync took.
  Duration? _lastSyncDuration;
  Duration? get lastSyncDuration => _lastSyncDuration;

  /// Whether a sync is currently in progress.
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  // Dependencies that need to be updated via ProxyProvider
  SubscriptionProvider? subscriptionProvider;
  SettingsProvider? settingsProvider;
  BookmarkProvider? bookmarkProvider;

  // ---------------------------------------------------------------------------
  // Filtered items cache — avoids recomputing the full filter chain
  // (including regex compilation for keyword exclusion) multiple times per
  // build when todayItems, yesterdayItems, olderItems, and hasMoreItems all
  // access it independently.
  // ---------------------------------------------------------------------------

  List<FeedItem>? _filteredItemsCache;

  /// Invalidates the cached filtered list. Must be called before
  /// [notifyListeners] whenever any filter input changes.
  void _invalidateFilterCache() {
    _filteredItemsCache = null;
    _dateGroupsCache = null;
  }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

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

  /// The full filtered article list (with read/bookmark states applied).
  /// Used by the article screen for swipe navigation between articles.
  List<FeedItem> get filteredItems => _filteredItems;

  // ---------------------------------------------------------------------------
  // Hive box accessor
  // ---------------------------------------------------------------------------

  /// Lazily cached reference to the `'feeds'` Hive box.
  Box get _box => Hive.box('feeds');

  // ---------------------------------------------------------------------------
  // Initialization & dependency updates
  // ---------------------------------------------------------------------------

  FeedProvider() {
    _loadState();
  }

  /// Called by the `ChangeNotifierProxyProvider3` whenever any upstream
  /// provider changes.
  void update(
    SubscriptionProvider sub,
    SettingsProvider set,
    BookmarkProvider book,
  ) {
    final bool isFirstUpdate = subscriptionProvider == null;

    // Snapshot sync settings before overwrite to decide if timer needs reset.
    final int prevInterval = settingsProvider?.cacheIntervalSeconds ?? -1;
    final bool prevSync = settingsProvider?.syncBackground ?? false;

    // Snapshot subscription URLs to detect actual feed-list changes.
    final List<String> prevUrls =
        subscriptionProvider?.subscriptions.map((s) => s.url).toList() ?? [];

    subscriptionProvider = sub;
    settingsProvider = set;
    bookmarkProvider = book;

    if (isFirstUpdate) {
      refreshAll();
      _manageCacheTimer();
      return;
    }

    // Rebuild filter output — cheap, O(n) walk already cached.
    _invalidateFilterCache();
    Future.microtask(() => notifyListeners());

    // Only recreate the background sync timer when interval or toggle changes.
    // Previously this always fired, resetting the countdown on every tap.
    final bool timerSettingsChanged =
        prevInterval != set.cacheIntervalSeconds ||
        prevSync != set.syncBackground;
    if (timerSettingsChanged) {
      _manageCacheTimer();
    }

    // If subscriptions were added/removed, kick off a fresh fetch.
    final List<String> currUrls = sub.subscriptions.map((s) => s.url).toList();
    if (!listEquals(prevUrls, currUrls)) {
      refreshAll();
    }
  }

  void _manageCacheTimer() {
    _cacheTimer?.cancel();
    _cacheTimer = null;
    if (settingsProvider == null) return;
    final interval = settingsProvider!.cacheIntervalSeconds;
    final syncEnabled = settingsProvider!.syncBackground;

    if (interval > 0 && syncEnabled) {
      _cacheTimer = Timer.periodic(Duration(seconds: interval), (timer) {
        refreshAll();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // State persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadState() async {
    final List<dynamic>? readIds = _box.get('readItemIds');
    if (readIds != null) {
      _readItemIds = readIds.cast<String>().toSet();
    }

    final String? cachedItemsData = _box.get('cachedItemsJson');
    if (cachedItemsData != null) {
      try {
        // Decode JSON in a background isolate — large caches can be 500ms+ on
        // main thread for users with many feeds.
        final maps = await compute(_decodeCachedItems, cachedItemsData);
        _items = maps.map(FeedItem.fromJson).toList();
        _cachedItemIds = _items.map((e) => e.id).toSet();
        _invalidateFilterCache();
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading cached items: $e');
      }
    }
  }

  Future<void> _saveReadStates() async {
    await _box.put('readItemIds', _readItemIds.toList());
  }

  // ---------------------------------------------------------------------------
  // Filter & selection controls
  // ---------------------------------------------------------------------------

  /// Selects a category filter (or `null` for "All News").
  void selectCategory(String? category) {
    _selectedCategory = category;
    _selectedFeedUrl = null;
    _itemRenderLimit = _pageSize;
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Updates the text search query.
  void setSearchQuery(String query) {
    _searchQuery = query;
    _itemRenderLimit = _pageSize;
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Toggles between showing all items and unread-only items.
  void toggleShowUnreadOnly() {
    _showUnreadOnly = !_showUnreadOnly;
    _itemRenderLimit = _pageSize;
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Selects a specific feed URL for filtering.
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
    _invalidateFilterCache();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Filtering pipeline (cached)
  // ---------------------------------------------------------------------------

  /// The full list of items after applying all active filters (unread, category,
  /// feed, search, keyword exclusion) and decorating with read/bookmark state.
  ///
  /// Result is cached and invalidated whenever filter inputs change.
  List<FeedItem> get _filteredItems {
    if (_filteredItemsCache != null) return _filteredItemsCache!;

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

    // Keyword filtering — compile regex patterns once for the entire pass
    final globalKeywords = settingsProvider?.globalExcludedKeywords ?? [];
    final Map<String, List<String>> feedKeywordsMap = {};
    if (subscriptionProvider != null) {
      for (final sub in subscriptionProvider!.subscriptions) {
        if (sub.excludedKeywords.isNotEmpty) {
          feedKeywordsMap[sub.url] = sub.excludedKeywords;
        }
      }
    }

    if (globalKeywords.isNotEmpty || feedKeywordsMap.isNotEmpty) {
      // Pre-compile global keyword patterns once
      final globalPatterns = globalKeywords
          .map(
            (kw) => RegExp(
              r'\b' + RegExp.escape(kw.toLowerCase()) + r'\b',
              caseSensitive: false,
            ),
          )
          .toList();

      // Pre-compile per-feed keyword patterns once
      final Map<String, List<RegExp>> feedPatternsMap = {};
      for (final entry in feedKeywordsMap.entries) {
        feedPatternsMap[entry.key] = entry.value
            .map(
              (kw) => RegExp(
                r'\b' + RegExp.escape(kw.toLowerCase()) + r'\b',
                caseSensitive: false,
              ),
            )
            .toList();
      }

      filtered = filtered.where((item) {
        final feedPatterns = feedPatternsMap[item.feedUrl];
        if (globalPatterns.isEmpty && feedPatterns == null) return true;

        bool matchesAny(List<RegExp> patterns) {
          for (final regex in patterns) {
            if (regex.hasMatch(item.title) ||
                regex.hasMatch(item.description)) {
              return true;
            }
          }
          return false;
        }

        if (globalPatterns.isNotEmpty && matchesAny(globalPatterns)) {
          return false;
        }
        if (feedPatterns != null && matchesAny(feedPatterns)) {
          return false;
        }
        return true;
      });
    }

    // Apply dynamic read/bookmark state
    _filteredItemsCache = filtered.map((item) {
      final isRead = _readItemIds.contains(item.id);
      final isBookmarked = bookmarkProvider?.isBookmarked(item.id) ?? false;
      return item.copyWith(isRead: isRead, isBookmarked: isBookmarked);
    }).toList();

    return _filteredItemsCache!;
  }

  /// The current render window — a slice of [_filteredItems] up to
  /// [_itemRenderLimit].
  List<FeedItem> get _visibleItems {
    final all = _filteredItems;
    if (_itemRenderLimit >= all.length) return all;
    return all.sublist(0, _itemRenderLimit);
  }

  // ---------------------------------------------------------------------------
  // Date-based section getters (single-pass grouping)
  // ---------------------------------------------------------------------------

  /// Cached date-group result to avoid re-computing on every getter call.
  _DateGroups? _dateGroupsCache;
  int _dateGroupsCacheHash = -1;

  /// Returns the single-pass date-grouped result for the current visible items.
  _DateGroups get _dateGroups {
    final visible = _visibleItems;
    final hash = Object.hash(
      visible.length,
      _filteredItemsCache?.length,
      _itemRenderLimit,
    );
    if (_dateGroupsCache != null && _dateGroupsCacheHash == hash) {
      return _dateGroupsCache!;
    }

    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final today = <FeedItem>[];
    final yester = <FeedItem>[];
    final older = <FeedItem>[];

    for (final item in visible) {
      final d = item.pubDate;
      if (d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day) {
        today.add(item);
      } else if (d != null &&
          d.year == yesterday.year &&
          d.month == yesterday.month &&
          d.day == yesterday.day) {
        yester.add(item);
      } else {
        older.add(item);
      }
    }

    _dateGroupsCache = _DateGroups(today, yester, older);
    _dateGroupsCacheHash = hash;
    return _dateGroupsCache!;
  }

  /// Items published today, within the current render window.
  List<FeedItem> get todayItems => _dateGroups.today;

  /// Items published yesterday, within the current render window.
  List<FeedItem> get yesterdayItems => _dateGroups.yesterday;

  /// Items older than yesterday (or with no date), within the current render
  /// window.
  List<FeedItem> get olderItems => _dateGroups.older;

  // ---------------------------------------------------------------------------
  // Pagination
  // ---------------------------------------------------------------------------

  /// Loads the next page of items. Safe to call multiple times — debounced
  /// internally.
  void loadMoreItems() {
    if (_isLoadingMore) return;
    if (!hasMoreItems) return;

    _isLoadingMore = true;
    _dateGroupsCache = null;
    notifyListeners();

    // Single-frame delay so the spinner is visible without blocking scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _itemRenderLimit += _pageSize;
      _isLoadingMore = false;
      _dateGroupsCache = null;
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // Read state
  // ---------------------------------------------------------------------------

  /// Whether the article with [id] has been read.
  bool isRead(String id) => _readItemIds.contains(id);

  /// Marks an article as read (no-op if already read).
  Future<void> markAsRead(String id) async {
    if (!_readItemIds.contains(id)) {
      _readItemIds.add(id);
      _invalidateFilterCache();
      notifyListeners();
      await _saveReadStates();
    }
  }

  /// Toggles the read/unread state of an article.
  Future<void> toggleReadStatus(String id) async {
    if (_readItemIds.contains(id)) {
      _readItemIds.remove(id);
    } else {
      _readItemIds.add(id);
    }
    _invalidateFilterCache();
    notifyListeners();
    await _saveReadStates();
  }

  // ---------------------------------------------------------------------------
  // Refresh & sync
  // ---------------------------------------------------------------------------

  /// Fetches all subscribed feeds with bounded concurrency, merges bookmarks,
  /// sorts by date, fires notifications for new articles, and persists cache.
  Future<void> refreshAll() async {
    if (subscriptionProvider == null) return;

    _isSyncing = true;
    _isLoading = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    final subs = subscriptionProvider!.subscriptions;

    // Rate-limit concurrent HTTP requests to avoid network/memory saturation.
    // With 30+ feeds, unbounded Future.wait exhausts connection pools and causes
    // TCP resets on constrained devices.
    final semaphore = _Semaphore(_fetchConcurrency);
    final futures = subs.map((sub) async {
      await semaphore.acquire();
      try {
        return await _feedService.fetchFeed(sub.url, sub.category);
      } catch (e) {
        debugPrint('Error fetching feed ${sub.url}: $e');
        return <FeedItem>[];
      } finally {
        semaphore.release();
      }
    });

    final results = await Future.wait(futures);

    List<FeedItem> freshItems = [];
    for (final items in results) {
      freshItems.addAll(items);
    }

    // If every single fetch failed (e.g. device is offline), keep the
    // previously loaded items so cached articles remain visible.
    final bool fetchedAnything = freshItems.isNotEmpty;

    if (fetchedAnything) {
      // Merge bookmarks into the fresh list so they are always visible.
      // Use a Set for O(1) lookup — avoids O(bookmarks × items) scan.
      if (bookmarkProvider != null) {
        final freshIds = freshItems.map((i) => i.id).toSet();
        for (final saved in bookmarkProvider!.bookmarkedItems) {
          if (!freshIds.contains(saved.id)) {
            freshItems.add(saved);
            freshIds.add(saved.id);
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
        final existingIds = _items.map((i) => i.id).toSet();
        for (final saved in bookmarkProvider!.bookmarkedItems) {
          if (!existingIds.contains(saved.id)) {
            _items.add(saved);
            existingIds.add(saved.id);
          }
        }
      }
      debugPrint('FeedProvider: all fetches failed — showing cached items.');
    }

    _isOffline = !fetchedAnything;
    _isLoading = false;
    _invalidateFilterCache();
    notifyListeners();

    // Fire notifications for newly discovered items (skip the initial load).
    if (fetchedAnything && _hasLoadedOnce) {
      _notifyNewArticles(freshItems);
    }
    _hasLoadedOnce = true;

    // Only persist a new cache snapshot when we actually fetched fresh data.
    if (fetchedAnything) {
      await _saveCachedItems();
    }

    stopwatch.stop();
    _lastSyncDuration = stopwatch.elapsed;
    _lastSyncTime = DateTime.now();
    _isSyncing = false;
    // Notify debug screen that sync state + timestamps have updated.
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Notification diffing
  // ---------------------------------------------------------------------------

  /// Computes newly discovered articles and triggers a notification.
  ///
  /// Uses the persisted [bgKnownItemIds] set (shared with the background
  /// service) so notifications are never duplicated across sessions or between
  /// the foreground timer and Workmanager. Only articles newer than 48 hours
  /// are eligible, and bursts are throttled to at most one per 15 minutes.
  void _notifyNewArticles(List<FeedItem> freshItems) {
    if (settingsProvider == null || subscriptionProvider == null) return;

    // Rate limit: max 1 notification burst per 15 minutes in-app.
    final now = DateTime.now();
    if (_lastNotificationTime != null &&
        now.difference(_lastNotificationTime!) < const Duration(minutes: 15)) {
      return;
    }

    // Use the persisted seen-ID set shared with the background service.
    final List<dynamic>? knownIdsList = _box.get('bgKnownItemIds');
    final Set<String> knownIds = knownIdsList?.cast<String>().toSet() ?? {};

    // Always update the persisted set so the next run has an accurate baseline.
    _box.put('bgKnownItemIds', freshItems.map((i) => i.id).toList());

    // No baseline yet (first ever install) — skip to avoid flood.
    if (knownIds.isEmpty) return;

    // Recency guard: only notify for articles published in the last 48 hours.
    final cutoff = now.subtract(const Duration(hours: 48));

    final mutedFeedUrls = subscriptionProvider!.subscriptions
        .where((s) => !s.notificationsEnabled)
        .map((s) => s.url)
        .toSet();

    final newItems = freshItems
        .where(
          (item) =>
              !knownIds.contains(item.id) &&
              !mutedFeedUrls.contains(item.feedUrl) &&
              item.pubDate != null &&
              item.pubDate!.isAfter(cutoff),
        )
        .toList();

    if (newItems.isEmpty) return;

    _lastNotificationTime = now;
    final latestJson = jsonEncode(newItems.first.toJson());

    NotificationService.instance.showNewArticlesNotification(
      newItems: newItems,
      notificationsEnabled: settingsProvider!.notificationsEnabled,
      digestMode: settingsProvider!.digestMode,
      quietHoursEnabled: settingsProvider!.quietHoursEnabled,
      quietHoursStart: settingsProvider!.quietHoursStart,
      quietHoursEnd: settingsProvider!.quietHoursEnd,
      latestItemJson: latestJson,
    );
  }

  // ---------------------------------------------------------------------------
  // Cache persistence
  // ---------------------------------------------------------------------------

  Future<void> _saveCachedItems() async {
    if (settingsProvider == null) return;
    final int limit = settingsProvider!.offlineCacheLimit;

    // offlineCacheLimit == 0 means "no offline cache"
    if (limit == 0) return;

    final itemsToCache = _items.take(limit).toList();
    _cachedItemIds = itemsToCache.map((e) => e.id).toSet();
    // No notifyListeners() here — cachedItemIds is only used for badge display
    // and the next normal rebuild will pick it up, avoiding an unnecessary
    // full widget tree rebuild during a background write.

    // Encode JSON in a background isolate — avoids blocking scroll/animation
    // while serializing potentially hundreds of items.
    final maps = itemsToCache.map((e) => e.toJson()).toList();
    final String encodedData = await compute(_encodeCachedItems, maps);
    await _box.put('cachedItemsJson', encodedData);
  }

  /// Clears all cached offline articles.
  Future<void> clearCache() async {
    _cachedItemIds.clear();
    await _box.delete('cachedItemsJson');
    notifyListeners();
  }

  /// Clears all feed data, caches, and read states, resetting to default.
  Future<void> factoryReset() async {
    _items.clear();
    _selectedCategory = null;
    _selectedFeedUrl = null;
    _readItemIds.clear();
    _cachedItemIds.clear();
    _searchQuery = '';
    _showUnreadOnly = false;
    _itemRenderLimit = _pageSize;

    _lastSyncTime = null;
    _lastSyncDuration = null;
    _hasLoadedOnce = false;
    _lastNotificationTime = null;

    await _box.clear();
    _invalidateFilterCache();
    notifyListeners();
  }

  @override
  void dispose() {
    _cacheTimer?.cancel();
    _feedService.dispose();
    super.dispose();
  }
}

/// Simple tuple holding the three date-based groups computed in a single pass.
class _DateGroups {
  final List<FeedItem> today;
  final List<FeedItem> yesterday;
  final List<FeedItem> older;

  const _DateGroups(this.today, this.yesterday, this.older);
}

// ---------------------------------------------------------------------------
// Isolate-safe top-level functions for compute()
// ---------------------------------------------------------------------------

/// Decodes a JSON string into a list of item maps (runs in background isolate).
List<Map<String, dynamic>> _decodeCachedItems(String data) {
  final list = jsonDecode(data) as List<dynamic>;
  return list.cast<Map<String, dynamic>>();
}

/// Encodes a list of item maps to JSON string (runs in background isolate).
String _encodeCachedItems(List<Map<String, dynamic>> maps) =>
    jsonEncode(maps);

// ---------------------------------------------------------------------------
// Concurrency limiter
// ---------------------------------------------------------------------------

/// Simple semaphore that gates access to at most [maxCount] concurrent slots.
///
/// Used to limit parallel HTTP requests so the device's connection pool and
/// memory aren't overwhelmed when many feeds are subscribed.
class _Semaphore {
  final int maxCount;
  int _current = 0;
  final Queue<Completer<void>> _waitQueue = Queue();

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_current < maxCount) {
      _current++;
      return;
    }
    final c = Completer<void>();
    _waitQueue.add(c);
    await c.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeFirst().complete();
    } else {
      _current--;
    }
  }
}
