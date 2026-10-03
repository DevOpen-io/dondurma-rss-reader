import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image_ce/cached_network_image.dart'
    show DefaultCacheManager;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:html/parser.dart' show parse;

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import '../services/feed_cache_policy.dart';
import '../services/feed_date_groups.dart';
import '../services/feed_decisions.dart';
import '../services/feed_list_filter.dart';
import '../services/feed_refresh.dart';
import '../services/feed_service.dart';
import '../services/full_text_extraction_service.dart';
import '../services/image_cache_service.dart';
import '../services/notification_delivery_policy.dart';
import '../services/notification_service.dart';
import '../services/observed_article_store.dart';
import '../services/widget_update_service.dart';
import '../utils/async_semaphore.dart';
import 'bookmark_provider.dart';
import 'settings_provider.dart';
import 'subscription_provider.dart';

/// Core provider that manages fetching, caching, filtering, and paginated
/// rendering of RSS/Atom feed items.
///
/// Connected to [SubscriptionProvider], [SettingsProvider], and
/// [BookmarkProvider] via `ChangeNotifierProxyProvider3` in `main.dart`.
///
/// Heavy lifting lives in dedicated services: [FeedRefresher] (fetch/merge),
/// [applyFeedFilters] (filter pipeline), [groupFeedItemsByDate] (sections),
/// and `feed_decisions.dart` (pure sync/filter predicates).
class FeedProvider extends ChangeNotifier {
  final FeedService _feedService = FeedService();
  late final ObservedArticleStore _observedArticleStore;
  late final FeedRefresher _refresher;
  late final Future<void> _initialization;

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

  /// Set when a refresh is requested while one is already running. The in-flight
  /// [refreshAll] runs exactly one more pass when it finishes, so overlapping
  /// triggers collapse into a single trailing refresh instead of stacking.
  bool _refreshQueued = false;
  Completer<void>? _refreshWaiter;

  /// Immutable snapshot owned by this provider. The upstream provider is
  /// mutable, so its current list cannot represent previous subscription state.
  Set<String> _knownSubscriptionUrls = const {};

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

  // Snapshots of the upstream inputs that actually feed the filter pipeline.
  // Compared in [update] so unrelated upstream changes (theme, search history,
  // quiet hours…) don't invalidate the cache and rebuild the whole feed list.
  List<String>? _lastGlobalKeywords;
  Map<String, List<String>>? _lastFeedKeywords;
  Set<String>? _lastBookmarkIds;

  /// Memoized unread tallies powering the drawer badges. Rebuilt lazily from
  /// [_items] + [_readItemIds] and invalidated alongside the filter cache, so
  /// the drawer no longer rescans every item for every category/feed row on
  /// each rebuild. `null` means "needs rebuild".
  Map<String, int>? _unreadByCategory;
  Map<String, int>? _unreadByFeed;
  int _unreadTotal = 0;

  /// Invalidates the cached filtered list. Must be called before
  /// [notifyListeners] whenever any filter input changes.
  void _invalidateFilterCache() {
    _filteredItemsCache = null;
    _dateGroupsCache = null;
    _unreadByCategory = null;
    _unreadByFeed = null;
  }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  List<FeedItem> get items => _items;
  Set<String> get cachedItemIds => _cachedItemIds;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isOffline => _isOffline;

  /// Last fetch failure per feed, persisted across restarts so a dead feed
  /// stays visibly unhealthy instead of silently showing stale cache.
  Map<String, String> _feedErrors = {};
  String? feedErrorFor(String url) => _feedErrors[url];

  String? get selectedCategory => _selectedCategory;
  String? get selectedFeedUrl => _selectedFeedUrl;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // Runtime-only filter sheet state — intentionally NOT persisted to Hive;
  // resets on app restart or "clear filters".
  String _readFilter = 'all'; // 'all' | 'unread' | 'read'
  Set<String> _filterCategories = {};
  String get readFilter => _readFilter;
  Set<String> get filterCategories => Set.unmodifiable(_filterCategories);
  bool get hasActiveSheetFilter =>
      _readFilter != 'all' || _filterCategories.isNotEmpty;

  /// Legacy view of the read filter, kept for existing call sites.
  bool get showUnreadOnly => _readFilter == 'unread';

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

  FeedProvider({ObservedArticleStore? observedArticleStore}) {
    _observedArticleStore =
        observedArticleStore ?? ObservedArticleStore.forBox(_box);
    _refresher = FeedRefresher(
      feedService: _feedService,
      observedArticleStore: _observedArticleStore,
    );
    _initialization = _loadState();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (_) {},
    );
  }

  /// Re-sync as soon as connectivity returns after an offline stretch —
  /// otherwise a device that sat through a flap waits for the next timer tick.
  /// Gated on `_isOffline` so a momentary blip while online stays free.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed || !_isOffline) return;
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    if (hasNetwork) refreshAll();
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

    subscriptionProvider = sub;
    settingsProvider = set;
    bookmarkProvider = book;

    // Snapshot the filter-relevant inputs and compare against the previous
    // update, so theme/search-history/quiet-hours changes don't trigger a
    // full refilter + feed-list rebuild.
    final nextGlobalKeywords = List<String>.of(set.globalExcludedKeywords);
    final nextFeedKeywords = <String, List<String>>{
      for (final s in sub.subscriptions)
        if (s.excludedKeywords.isNotEmpty)
          s.url: List<String>.of(s.excludedKeywords),
    };
    final nextBookmarkIds = Set<String>.of(book.bookmarkedItemIds);
    final inputsChanged = feedFilterInputsChanged(
      prevGlobalKeywords: _lastGlobalKeywords,
      nextGlobalKeywords: nextGlobalKeywords,
      prevFeedKeywords: _lastFeedKeywords,
      nextFeedKeywords: nextFeedKeywords,
      prevBookmarkIds: _lastBookmarkIds,
      nextBookmarkIds: nextBookmarkIds,
    );
    _lastGlobalKeywords = nextGlobalKeywords;
    _lastFeedKeywords = nextFeedKeywords;
    _lastBookmarkIds = nextBookmarkIds;

    final currentUrls = sub.subscriptions.map((s) => s.url).toSet();
    final subscriptionsChanged = !setEquals(
      _knownSubscriptionUrls,
      currentUrls,
    );
    _knownSubscriptionUrls = Set.unmodifiable(currentUrls);

    if (isFirstUpdate) {
      refreshAll();
      _manageCacheTimer();
      return;
    }

    if (inputsChanged) {
      // Rebuild filter output — cheap, O(n) walk already cached.
      _invalidateFilterCache();
      Future.microtask(() => notifyListeners());
    }

    // Only recreate the background sync timer when interval or toggle changes.
    // Previously this always fired, resetting the countdown on every tap.
    final bool timerSettingsChanged =
        prevInterval != set.cacheIntervalSeconds ||
        prevSync != set.syncBackground;
    if (timerSettingsChanged) {
      _manageCacheTimer();
    }

    // If subscriptions were added/removed, kick off a fresh fetch.
    if (subscriptionsChanged) {
      refreshAll();
    }
  }

  /// Refreshes feeds when the app returns to the foreground, unless a sync
  /// completed very recently. Keeps notification-tap / cold-resume launches
  /// showing current news without spamming fetches on rapid app switches.
  Future<void> maybeRefreshOnResume() async {
    if (!feedShouldRefreshOnResume(
      hasDependencies: subscriptionProvider != null,
      isSyncing: _isSyncing,
      lastSyncTime: _lastSyncTime,
      now: DateTime.now(),
    )) {
      return;
    }
    await refreshAll();
  }

  void _manageCacheTimer() {
    _cacheTimer?.cancel();
    _cacheTimer = null;
    if (settingsProvider == null) return;
    final interval = settingsProvider!.cacheIntervalSeconds;
    final syncEnabled = settingsProvider!.syncBackground;

    if (interval > 0 && syncEnabled) {
      _cacheTimer = Timer.periodic(Duration(seconds: interval), (timer) {
        if (!feedShouldRunPeriodicSync(
          lastSyncTime: _lastSyncTime,
          now: DateTime.now(),
          intervalSeconds: interval,
        )) {
          return;
        }
        refreshAll();
      });
    }
  }

  /// Stops the foreground auto-refresh timer. Called when the app is
  /// backgrounded so the polling loop doesn't keep firing HTTP requests (and
  /// draining battery/data) while the isolate is still alive but the user is
  /// away — WorkManager handles fetching in the background instead.
  void pauseAutoRefresh() {
    _cacheTimer?.cancel();
    _cacheTimer = null;
  }

  /// Restarts the foreground auto-refresh timer (subject to the user's sync
  /// settings) when the app returns to the foreground.
  void resumeAutoRefresh() {
    _manageCacheTimer();
  }

  // ---------------------------------------------------------------------------
  // State persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadState() async {
    final List<dynamic>? readIds = _box.get('readItemIds');
    if (readIds != null) {
      _readItemIds = readIds.cast<String>().toSet();
    }

    final feedErrors = _box.get('feedErrors');
    if (feedErrors is Map) {
      _feedErrors = feedErrors.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
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

  /// Hard cap on persisted read ids — pruning only above this keeps normal
  /// behavior intact: a trimmed article that reappears in a later fetch must
  /// keep its read mark (unlike a hard-pruned set, which forgets it).
  static const int _readIdsHardCap = 10000;

  Future<void> _saveReadStates() async {
    if (_readItemIds.length > _readIdsHardCap) {
      // Bounded-growth path: keep marks only for articles still reachable
      // (current items or bookmarks). Beyond the cap, forgetting read marks
      // for evicted articles is cheaper than an ever-growing set.
      final liveIds = <String>{
        for (final i in _items) i.id,
        for (final b in bookmarkProvider?.bookmarkedItems ?? const <FeedItem>[])
          b.id,
      };
      _readItemIds.removeWhere((id) => !liveIds.contains(id));
    }
    await _box.put('readItemIds', _readItemIds.toList());
  }

  /// Loads persisted per-feed HTTP cache validators (ETag / Last-Modified),
  /// stored as a JSON object `{ feedUrl: {etag, lastModified} }`. Returns an
  /// empty map when absent or corrupt — a missing validator just means the next
  /// fetch is unconditional.
  Map<String, dynamic> _loadFeedValidators() {
    final raw = _box.get('feedValidators');
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return {};
  }

  void _saveFeedValidators(Map<String, dynamic> validators) {
    _box.put('feedValidators', jsonEncode(validators));
  }

  /// Learned per-feed redirect map (`{ canonicalUrl: resolvedUrl }`). A 301'd
  /// feed keeps answering at its new location; fetching it directly skips a
  /// redirect round-trip on every sync.
  Map<String, String> _loadFeedRedirects() {
    final raw = _box.get('feedRedirects');
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    return {};
  }

  void _saveFeedRedirects(Map<String, String> redirects) {
    _box.put('feedRedirects', jsonEncode(redirects));
  }

  /// Merges one refresh pass into the per-feed error map: recorded failures
  /// are written, successes clear, and feeds in [unproven] (connectivity-only
  /// failures during a fully offline pass) keep whatever they had — a network
  /// outage neither indicts nor acquits a feed. Removed feeds are pruned.
  void _updateFeedErrors(Map<String, String> passErrors, Set<String> unproven) {
    final urls =
        subscriptionProvider?.subscriptions.map((s) => s.url).toSet() ??
        const <String>{};
    final next = <String, String>{};
    for (final url in urls) {
      if (passErrors.containsKey(url)) {
        next[url] = passErrors[url]!;
      } else if (unproven.contains(url) && _feedErrors.containsKey(url)) {
        next[url] = _feedErrors[url]!;
      }
    }
    if (!mapEquals(_feedErrors, next)) {
      _feedErrors = next;
      _box.put('feedErrors', _feedErrors);
    }
  }

  // ---------------------------------------------------------------------------
  // Filter & selection controls
  // ---------------------------------------------------------------------------

  /// Selects a category filter (or `null` for "All News").
  void selectCategory(String? category) {
    _selectedCategory = category;
    _selectedFeedUrl = null;
    // Drawer selection replaces sheet category chips — one category axis.
    _filterCategories = {};
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

  /// Applies the runtime filter chosen in the filter bottom sheet.
  /// [readFilter] is `'all' | 'unread' | 'read'`; an empty [categories] set
  /// means "all categories". State lives only in memory (never persisted).
  void applySheetFilter({
    required String readFilter,
    required Set<String> categories,
  }) {
    _readFilter = readFilter;
    _filterCategories = {...categories};
    // The sheet now owns category filtering: it pre-selects the drawer
    // category, so applying carries it over — keep one axis, not two ANDed.
    _selectedCategory = null;
    _itemRenderLimit = _pageSize;
    _invalidateFilterCache();
    notifyListeners();
  }

  /// Resets the filter sheet state back to "show everything".
  void clearSheetFilter() =>
      applySheetFilter(readFilter: 'all', categories: const {});

  /// Selects a specific feed URL for filtering.
  void selectFeed(String? feedUrl) {
    _selectedFeedUrl = feedUrl;
    // Feed selection replaces sheet category chips — one category axis.
    _filterCategories = {};
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

    final globalKeywords = settingsProvider?.globalExcludedKeywords ?? [];
    final Map<String, List<String>> feedKeywordsMap = {};
    if (subscriptionProvider != null) {
      for (final sub in subscriptionProvider!.subscriptions) {
        if (sub.excludedKeywords.isNotEmpty) {
          feedKeywordsMap[sub.url] = sub.excludedKeywords;
        }
      }
    }

    final filtered = applyFeedFilters(
      items: _items,
      readItemIds: _readItemIds,
      selectedCategory: _selectedCategory,
      selectedFeedUrl: _selectedFeedUrl,
      searchQuery: _searchQuery,
      readFilter: _readFilter,
      filterCategories: _filterCategories,
      globalKeywords: globalKeywords,
      feedKeywordsMap: feedKeywordsMap,
    );

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
  FeedDateGroups? _dateGroupsCache;
  int _dateGroupsCacheHash = -1;

  /// Returns the single-pass date-grouped result for the current visible items.
  FeedDateGroups get _dateGroups {
    final visible = _visibleItems;
    final hash = Object.hash(
      visible.length,
      _filteredItemsCache?.length,
      _itemRenderLimit,
    );
    if (_dateGroupsCache != null && _dateGroupsCacheHash == hash) {
      return _dateGroupsCache!;
    }

    _dateGroupsCache = groupFeedItemsByDate(visible, DateTime.now());
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

  /// Number of unread items, optionally scoped to a [category] or [feedUrl].
  /// Used by the drawer to show unread badges next to categories and feeds.
  /// Backed by memoized tallies — a single O(n) pass amortized across all rows.
  int unreadCount({String? category, String? feedUrl}) {
    if (_unreadByCategory == null) _rebuildUnreadCounts();
    if (feedUrl != null) return _unreadByFeed![feedUrl] ?? 0;
    if (category != null) return _unreadByCategory![category] ?? 0;
    return _unreadTotal;
  }

  /// Single-pass rebuild of the unread tallies. Cached until the next
  /// [_invalidateFilterCache] (read-state change, fetch, or filter change).
  void _rebuildUnreadCounts() {
    final byCategory = <String, int>{};
    final byFeed = <String, int>{};
    int total = 0;
    for (final item in _items) {
      if (_readItemIds.contains(item.id)) continue;
      total++;
      byCategory[item.category] = (byCategory[item.category] ?? 0) + 1;
      byFeed[item.feedUrl] = (byFeed[item.feedUrl] ?? 0) + 1;
    }
    _unreadByCategory = byCategory;
    _unreadByFeed = byFeed;
    _unreadTotal = total;
  }

  /// Marks an article as read (no-op if already read).
  Future<void> markAsRead(String id) async {
    if (!_readItemIds.contains(id)) {
      _readItemIds.add(id);
      _invalidateFilterCache();
      notifyListeners();
      await _saveReadStates();
    }
  }

  /// Marks all articles in [category] as read in one atomic operation.
  Future<void> markAllInCategoryAsRead(String category) async {
    final ids = _items
        .where((i) => i.category == category)
        .map((i) => i.id)
        .toSet();
    if (ids.isEmpty) return;
    final hadUnread = ids.any((id) => !_readItemIds.contains(id));
    if (!hadUnread) return;
    _readItemIds.addAll(ids);
    _invalidateFilterCache();
    notifyListeners();
    await _saveReadStates();
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

  /// Validates, persists, and makes a subscription usable in one awaited
  /// foreground transaction. The authoritative validation response is reused
  /// by the normal refresh pipeline, including cache and observation handling.
  Future<bool> addSubscriptionAndRefresh(
    String url,
    String name,
    String category,
  ) async {
    await _initialization;
    final subscriptions = subscriptionProvider;
    if (subscriptions == null) return false;
    if (subscriptions.hasFeedUrl(url)) {
      return false;
    }

    _isLoading = true;
    notifyListeners();
    final previousKnownUrls = _knownSubscriptionUrls;
    try {
      final prefetched = await _feedService.fetchFeed(url, category);
      if (prefetched.notModified) {
        throw Exception('Authoritative subscription fetch returned 304.');
      }

      // ProxyProvider may rebuild after addFeed returns. Pre-advance this
      // provider-owned snapshot so that delayed update does not start a second,
      // all-feed refresh for a transaction already owned here.
      _knownSubscriptionUrls = Set.unmodifiable({...previousKnownUrls, url});
      final added = await subscriptions.addFeed(url, name, category);
      if (!added) {
        _knownSubscriptionUrls = previousKnownUrls;
        return false;
      }

      // If another refresh was already running, let its queued pass settle
      // before applying the authoritative new-feed result so it cannot overwrite
      // the transaction's articles with an older subscription snapshot.
      if (_isSyncing) await refreshAll();
      final subscription = subscriptions.subscriptions.firstWhere(
        (item) => item.url == url,
      );
      await _applyNewSubscriptionResult(subscription, prefetched);
      return true;
    } catch (_) {
      _knownSubscriptionUrls = previousKnownUrls;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _applyNewSubscriptionResult(
    FeedSubscription subscription,
    FeedFetchResult result,
  ) async {
    final merged = _items
        .where((item) => item.feedUrl != subscription.url)
        .toList();
    merged.addAll(result.items);
    merged.sort((a, b) {
      if (a.pubDate == null && b.pubDate == null) return 0;
      if (a.pubDate == null) return 1;
      if (b.pubDate == null) return -1;
      return b.pubDate!.compareTo(a.pubDate!);
    });
    _items = merged;

    final validators = _loadFeedValidators();
    if (result.etag != null || result.lastModified != null) {
      validators[subscription.url] = {
        'etag': result.etag,
        'lastModified': result.lastModified,
      };
    } else {
      validators.remove(subscription.url);
    }
    _saveFeedValidators(validators);

    if (result.finalUrl != null) {
      final redirects = _loadFeedRedirects();
      redirects[subscription.url] = result.finalUrl!;
      _saveFeedRedirects(redirects);
    }

    await _observedArticleStore.claimFeedBatch(
      feedUrl: subscription.url,
      observationEpoch: subscription.notificationEpoch,
      items: result.items,
      allowInitialization: true,
    );

    _isOffline = false;
    // A successful add proves the feed is healthy — drop any stale error a
    // delete-and-re-add cycle left behind.
    if (_feedErrors.remove(subscription.url) != null) {
      _box.put('feedErrors', _feedErrors);
    }
    _invalidateFilterCache();
    notifyListeners();
    await _saveCachedItems();
    WidgetUpdateService.updateFeedWidgets(_items).ignore();
  }

  /// Fetches all subscribed feeds with bounded concurrency, merges bookmarks,
  /// sorts by date, fires notifications for new articles, and persists cache.
  Future<void> refreshAll() async {
    await _initialization;
    if (subscriptionProvider == null) return;

    // Coalesce overlapping refreshes. The periodic timer, app-resume, and
    // subscription-change triggers can all fire close together; without this a
    // second full-feed fetch storm would run in parallel, doubling HTTP load.
    // Instead, record that one more pass is needed and let the in-flight call
    // run it when it finishes.
    if (_isSyncing) {
      _refreshQueued = true;
      return (_refreshWaiter ??= Completer<void>()).future;
    }

    _isSyncing = true;
    Object? failure;
    StackTrace? failureStack;
    try {
      do {
        _refreshQueued = false;
        await _performRefresh();
      } while (_refreshQueued);
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
      rethrow;
    } finally {
      // Always clear the guard, even if a fetch/persist step throws — otherwise
      // the provider would deadlock and never refresh again.
      _isSyncing = false;
      final waiter = _refreshWaiter;
      _refreshWaiter = null;
      if (waiter != null && !waiter.isCompleted) {
        if (failure == null) {
          waiter.complete();
        } else {
          waiter.completeError(failure, failureStack);
        }
      }
    }
  }

  /// Internal single-pass refresh. Always invoke through [refreshAll], which
  /// owns the `_isSyncing` guard and trailing-refresh coalescing.
  Future<void> _performRefresh() async {
    if (_disposed) return;
    _isLoading = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    final result = await _refresher.refresh(
      subscriptions: subscriptionProvider!.subscriptions,
      existingItems: _items,
      validators: _loadFeedValidators(),
      bookmarkedItems: bookmarkProvider?.bookmarkedItems ?? const [],
      redirects: _loadFeedRedirects(),
    );

    _saveFeedValidators(result.validators);
    _saveFeedRedirects(result.redirects);
    _updateFeedErrors(result.feedErrors, result.unprovenUrls);
    _items = result.items;
    _isOffline = !result.online;
    _isLoading = false;
    _invalidateFilterCache();
    if (!_disposed) notifyListeners();

    // First foreground load suppresses delivery only. Observation already
    // advanced above, so these articles cannot backfill on a later refresh.
    if (_hasLoadedOnce) {
      await _deliverClaimedArticles(result.claimedItems);
    }
    _hasLoadedOnce = true;

    // Only persist a new cache snapshot when a feed actually returned new data.
    if (result.anyFreshBody) {
      await _saveCachedItems();
    }

    stopwatch.stop();
    _lastSyncDuration = stopwatch.elapsed;
    // Stamp only when a feed actually reached the network — an all-offline
    // pass must not look like a real sync to the resume/periodic gates.
    if (result.online) _lastSyncTime = DateTime.now();
    // Notify debug screen that sync state + timestamps have updated.
    if (!_disposed) notifyListeners();

    // Refresh widget ages on every completed pass, not only when a feed body
    // changed — otherwise the "5m" strings written last cycle freeze in place.
    WidgetUpdateService.updateFeedWidgets(_items).ignore();

    // Offline-first: fetch article bodies for full-text feeds so they read
    // without a network. Runs after the refresh settles — never blocks it.
    if (result.online) _prefetchFullText().ignore();
  }

  /// Whether a full-text prefetch pass is already in flight.
  bool _isPrefetching = false;

  /// Set when a refresh asks for prefetch while one is draining — rerun once
  /// the in-flight pass settles so newer articles aren't skipped a whole
  /// sync cycle (mirrors [_refreshQueued]).
  bool _prefetchQueued = false;

  /// Set once [dispose] runs so async prefetch continuations skip
  /// [notifyListeners], which throws on a disposed [ChangeNotifier].
  bool _disposed = false;

  /// Articles per feed prefetch attempts in one pass.
  static const _fullTextPrefetchPerFeed = 5;

  /// Max parallel article-page fetches during prefetch.
  static const _fullTextPrefetchConcurrency = 3;

  /// Downloads article bodies for offline reading (decision on issue #14):
  /// only subscriptions with `fullTextEnabled == true`, the newest
  /// [_fullTextPrefetchPerFeed] items lacking content, foreground-sync only.
  /// Extraction failures stay silent — the article keeps its RSS excerpt.
  Future<void> _prefetchFullText() async {
    if (_isPrefetching) {
      _prefetchQueued = true;
      return;
    }
    final subs = subscriptionProvider?.subscriptions
        .where((s) => s.fullTextEnabled == true)
        .toList();
    if (subs == null || subs.isEmpty) return;

    _isPrefetching = true;
    try {
      final extraction = FullTextExtractionService.instance;
      // _items is date-sorted newest-first, so take() picks the latest.
      // Skipping session-failed URLs keeps them from stalling backfill.
      final candidates = <FeedItem>[];
      for (final sub in subs) {
        candidates.addAll(
          _items
              .where(
                (i) =>
                    i.feedUrl == sub.url &&
                    i.prefetchedFullText == null &&
                    i.link.isNotEmpty &&
                    !extraction.hasFailedAttempt(i.link),
              )
              .take(_fullTextPrefetchPerFeed),
        );
      }

      var changed = false;
      final semaphore = AsyncSemaphore(_fullTextPrefetchConcurrency);
      await Future.wait(
        candidates.map((item) async {
          await semaphore.acquire();
          try {
            final html = await extraction.extractFullText(item.link);
            if (html == null) return;
            final index = _items.indexWhere(
              (e) => e.id == item.id && e.feedUrl == item.feedUrl,
            );
            if (index == -1) return; // item trimmed meanwhile
            _items[index] = _items[index].copyWith(prefetchedFullText: html);
            changed = true;
            // Decision #15: warm the image caches too — the thumbnail and
            // the body's inline images — inside the same concurrency slot.
            await _prefetchImages(item, html);
          } catch (_) {
            // Extraction threw — the RSS excerpt remains; the session failure
            // cache stops this URL from re-attempting until app restart.
          } finally {
            semaphore.release();
          }
        }),
      );

      if (changed) {
        if (!_disposed) {
          _invalidateFilterCache();
          notifyListeners();
        }
        await _saveCachedItems();
      }
    } finally {
      _isPrefetching = false;
      if (_prefetchQueued) {
        _prefetchQueued = false;
        _prefetchFullText().ignore();
      }
    }
  }

  /// Max inline `<img>` downloads per prefetched article — bounds a runaway
  /// gallery page to a sane per-article image budget.
  static const _prefetchImagesPerArticle = 8;

  /// Warms the thumbnail and article-image caches for [item] using [html]
  /// (its prefetched body). Best-effort: every failure is silent — a missing
  /// image just renders broken offline, same as today. Each download is
  /// isolated so one bad image can't forfeit the rest of the budget.
  Future<void> _prefetchImages(FeedItem item, String html) async {
    final thumbnail = item.imageUrl;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      // The feed list reads ThumbnailCacheManager; the article hero reads
      // ArticleCacheManager for the same URL — warm both.
      await _warmImage(ThumbnailCacheManager.instance, thumbnail);
      await _warmImage(ArticleCacheManager.instance, thumbnail);
    }
    final srcs = parse(html)
        .getElementsByTagName('img')
        .map((e) => e.attributes['src'])
        .whereType<String>()
        .where((s) => s.startsWith('http'))
        .take(_prefetchImagesPerArticle);
    for (final src in srcs) {
      await _warmImage(ArticleCacheManager.instance, src);
    }
  }

  Future<void> _warmImage(DefaultCacheManager manager, String url) async {
    try {
      await manager
          .getFileStream(url)
          .timeout(const Duration(seconds: 15))
          .drain<void>();
    } catch (_) {
      // Dead image, dead cache init, timeout — all silent by policy.
    }
  }

  // ---------------------------------------------------------------------------
  // Notification diffing
  // ---------------------------------------------------------------------------

  /// Applies delivery policy to articles already claimed by the durable,
  /// cross-isolate observed-history store.
  Future<void> _deliverClaimedArticles(List<FeedItem> claimedItems) async {
    if (settingsProvider == null || subscriptionProvider == null) return;

    // Rate limit: max 1 notification burst per 15 minutes in-app.
    final now = DateTime.now();
    if (_lastNotificationTime != null &&
        now.difference(_lastNotificationTime!) < const Duration(minutes: 15)) {
      return;
    }

    final mutedFeedUrls = subscriptionProvider!.subscriptions
        .where((s) => !s.notificationsEnabled)
        .map((s) => s.url)
        .toSet();

    final newItems = NotificationDeliveryPolicy.eligibleItems(
      claimedItems: claimedItems,
      notificationsEnabled: settingsProvider!.notificationsEnabled,
      digestMode: settingsProvider!.digestMode,
      quietHoursEnabled: settingsProvider!.quietHoursEnabled,
      quietHoursStart: settingsProvider!.quietHoursStart,
      quietHoursEnd: settingsProvider!.quietHoursEnd,
      mutedFeedUrls: mutedFeedUrls,
      now: now,
    );

    if (newItems.isEmpty) return;

    _lastNotificationTime = now;
    final latestJson = jsonEncode(newItems.first.toJson());

    await NotificationService.instance.showNewArticlesNotification(
      newItems: newItems,
      notificationsEnabled: true,
      digestMode: 'instant',
      quietHoursEnabled: false,
      quietHoursStart: 0,
      quietHoursEnd: 0,
      latestItemJson: latestJson,
    );
  }

  // ---------------------------------------------------------------------------
  // Cache persistence
  // ---------------------------------------------------------------------------

  /// Serializes [cachedItemsJson] writes. Prefetch saves are fire-and-forget
  /// and can overlap a refresh save — unsynchronized, an older snapshot could
  /// `put` last and regress the durable cache. Chaining keeps writes ordered.
  Future<void> _saveChain = Future<void>.value();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Bumped by cache-clearing operations ([clearCache], [factoryReset]) so an
  /// in-flight [cachedItemsJson] write started before the reset cannot land
  /// its stale snapshot after the delete.
  int _cacheGeneration = 0;

  Future<void> _saveCachedItems() {
    final run = _saveChain.then((_) => _writeCachedItems());
    // Keep the chain usable after a failed write instead of poisoning it.
    _saveChain = run.catchError((_) {});
    return run;
  }

  Future<void> _writeCachedItems() async {
    if (settingsProvider == null) return;
    final int limit = settingsProvider!.offlineCacheLimit;

    // offlineCacheLimit == 0 means "no offline cache"
    if (limit == 0) return;

    final subscriptions = subscriptionProvider;
    if (subscriptions == null) return;
    final itemsToCache = FeedCachePolicy.fairTrim(
      items: _items,
      subscribedFeedUrls: subscriptions.subscriptions.map((sub) => sub.url),
      limit: limit,
    );
    _cachedItemIds = itemsToCache.map((e) => e.id).toSet();
    // No notifyListeners() here — cachedItemIds is only used for badge display
    // and the next normal rebuild will pick it up, avoiding an unnecessary
    // full widget tree rebuild during a background write.

    // Encode JSON in a background isolate — avoids blocking scroll/animation
    // while serializing potentially hundreds of items.
    final generation = _cacheGeneration;
    final maps = itemsToCache.map((e) => e.toJson()).toList();
    final String encodedData = await compute(_encodeCachedItems, maps);
    // A reset landed while encoding — dropping the write preserves the wipe.
    if (generation != _cacheGeneration) return;
    await _box.put('cachedItemsJson', encodedData);
  }

  /// Clears all cached offline articles.
  Future<void> clearCache() async {
    _cacheGeneration++;
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
    _feedErrors = {};
    _searchQuery = '';
    _readFilter = 'all';
    _filterCategories = {};
    _itemRenderLimit = _pageSize;

    _lastSyncTime = null;
    _lastSyncDuration = null;
    _hasLoadedOnce = false;
    _lastNotificationTime = null;

    _cacheGeneration++;
    await _box.clear();
    _invalidateFilterCache();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cacheTimer?.cancel();
    _connectivitySub?.cancel();
    _feedService.dispose();
    super.dispose();
  }
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
String _encodeCachedItems(List<Map<String, dynamic>> maps) => jsonEncode(maps);
