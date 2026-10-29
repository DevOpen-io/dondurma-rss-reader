import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import '../models/refresh_progress.dart';
import '../services/article_identity.dart';
import '../services/feed_backoff.dart';
import '../services/app_reset_service.dart';
import '../services/feed_cache_policy.dart';
import '../services/lifecycle_gate.dart';
import '../services/read_state.dart';
import '../services/feed_date_groups.dart';
import '../services/feed_decisions.dart';
import '../services/feed_discovery.dart';
import '../services/feed_list_filter.dart';
import '../services/feed_schedule.dart';
import '../services/feed_refresh.dart';
import '../services/article_preparation_service.dart';
import '../services/article_media_store.dart';
import '../services/article_record_store.dart';
import '../services/article_status.dart';
import '../services/temp_cache_membership.dart';
import '../services/feed_service.dart';
import '../services/full_text_extraction_service.dart';
import '../utils/host_pacer.dart';
import '../services/notification_delivery_policy.dart';
import '../services/notification_service.dart';
import '../services/observed_article_store.dart';
import '../services/widget_update_service.dart';
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
  final FeedService _feedService;
  late final ObservedArticleStore _observedArticleStore;
  late final FeedRefresher _refresher;
  late final Future<void> _initialization;

  List<FeedItem> _items = [];
  String? _selectedCategory;
  String? _selectedFeedUrl;

  /// Read marks per source instance; see [ReadState].
  ReadState _readState = ReadState.migrate(
    legacyIds: const [],
    stored: const {},
  );
  bool _isLoading = false;
  bool _isOffline = false;

  /// How many items from the filtered list are currently rendered.
  int _itemRenderLimit = 50;

  /// Incremented in batches when the user scrolls near the bottom.
  static const int _pageSize = 50;

  bool _isLoadingMore = false;

  Timer? _cacheTimer;
  Timer? _refreshPublishTimer;
  final Timer Function(Duration, void Function()) _scheduleRefreshPublish;

  /// Tracks whether the first load has completed, so we don't fire
  /// notifications on initial startup.
  bool _hasLoadedOnce = false;
  @visibleForTesting
  bool get hasLoadedOnce => _hasLoadedOnce;

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

  /// Incremental refresh status — a dedicated [ValueNotifier] so per-feed
  /// progress repaints only the small toolbar indicator instead of the
  /// entire provider listener tree.
  final ValueNotifier<RefreshProgress> refreshProgress = ValueNotifier(
    const RefreshProgress.idle(),
  );

  /// Set when a refresh is requested while one is already running. The in-flight
  /// [refreshAll] runs exactly one more pass when it finishes, so overlapping
  /// triggers collapse into a single trailing refresh instead of stacking.
  bool _refreshQueued = false;
  Completer<void>? _refreshWaiter;

  /// Subscription URLs the running pass fetches; null until it reads the
  /// list, so a change landing before that read rides along with it.
  Set<String>? _passSubscriptionUrls;

  /// Connectivity came back while a pass was running. Decided when the pass
  /// settles: only a pass that still ended offline earns a retry.
  bool _connectivityReturnedMidPass = false;

  /// True while the current/queued pass carries a user request — the
  /// completion toast only fires for user-initiated passes.
  bool _refreshIsUserInitiated = false;

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
  List<FeedItem>? _viewItemsCache;
  Map<Object, List<FeedItem>>? _viewGroupsCache;

  // Snapshots of the upstream inputs that actually feed the filter pipeline.
  // Compared in [update] so unrelated upstream changes (theme, search history,
  // quiet hours…) don't invalidate the cache and rebuild the whole feed list.
  List<String>? _lastGlobalKeywords;
  Map<String, List<String>>? _lastFeedKeywords;
  Map<String, List<String>>? _lastFeedOnlyKeywords;
  List<String>? _lastReadRules;

  /// Compiled "mark read" rules (#69), rebuilt only when the list changes.
  List<KeywordRule> _readRules = const [];
  Set<String>? _lastBookmarkIds;
  Set<(String, String)>? _lastBookmarkInstances;
  Map<String, bool?>? _knownFullTextPrefs;
  int _lastClaimVersion = -1;

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
    _viewItemsCache = null;
    _viewGroupsCache = null;
    _dateGroupsCache = null;
    _unreadByCategory = null;
    _unreadByFeed = null;
  }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  List<FeedItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isOffline => _isOffline;

  /// Per-article durable-state summaries (#41): rows and the article
  /// surface derive their offline labels from these — never from prefetch
  /// flags or image-cache guesses. Refreshed after each membership pass.
  Map<ArticleRef, ArticleStatus> _articleStatuses = const {};

  /// True once the first status-map read settled — distinguishes "still
  /// loading" from "verified absent" so a missing entry is not flashed as
  /// a failed save (#41 honesty).
  bool _articleStatusesLoaded = false;
  bool get articleStatusesLoaded => _articleStatusesLoaded;

  /// Current transport verdict from the connectivity plugin; `true` until
  /// the first check lands.
  bool _unmetered = true;
  bool get unmetered => _unmetered;

  /// Status summary for [id] (canonicalized), or null when the article has
  /// no durable record — meaning "no offline claim", never "ready".
  ArticleStatus? articleStatus(FeedItem item) =>
      _articleStatuses[ArticleRef.of(item)];

  /// The effective full-text preference for [item]'s feed — per-feed
  /// tri-state falling back to the global setting, same rule as the
  /// membership pass's `fullTextFor`.
  bool _effectiveFullText(FeedItem item) {
    final auto = settingsProvider?.autoFullText ?? false;
    return subscriptionProvider?.effectiveFullText(
          item.feedUrl,
          autoFullText: auto,
        ) ??
        auto;
  }

  /// Explicit single-article preparation pass (#41): one foreground pass
  /// for that article's missing pieces — allowed on metered transport but
  /// never bypasses a server `Retry-After` wait.
  Future<int> prepareArticleNow(FeedItem item) async {
    // Persist missing-file demotions BEFORE preparation reads the manifest.
    // Otherwise the first retry trusts stale `ready` entries and does no work.
    await _refreshArticleStatuses();
    final attempted = await _preparation.prepareArticle(ArticleRef.of(item));
    await _refreshArticleStatuses();
    return attempted;
  }

  /// Re-asserts a bookmark's durable claim and runs one foreground pass —
  /// the "retry save" path when the minimum persistent write failed (#41).
  /// The live bookmark predicate is rechecked inside the store lock.
  Future<void> retrySaveArticle(FeedItem item) async {
    final epoch = await _preparation.currentRecordEpoch();
    await _preparation.registerArticle(
      item,
      const {'bookmark'},
      expectedEpoch: epoch,
      // The feed's effective full-text preference must survive a save
      // retry — registerArticle's default (true) would silently re-arm
      // extraction for a feed the user set to RSS-only (#41).
      fullText: _effectiveFullText(item),
      claimCheck: () =>
          bookmarkProvider?.isBookmarked(item.id, feedUrl: item.feedUrl) ??
          false,
    );
    await _preparation.prepareArticle(ArticleRef.of(item));
    await _refreshArticleStatuses();
  }

  /// Monotonic guard on the status map: overlapping refreshes must apply
  /// in call order — a read started before a cache clear or owner strip
  /// must never overwrite the post-change truth (#41 freshness).
  int _statusGeneration = 0;

  /// The status read loop in flight; requests arriving meanwhile join it.
  Future<void>? _statusRefresh;
  bool _statusRefreshQueued = false;

  /// One media store for status reads: it resolves its directory once.
  final ArticleMediaStore _statusMedia = ArticleMediaStore();

  /// Re-reads the offline status map. Each read decodes the archive and
  /// checks every ready file, so overlapping requests share one loop: a
  /// read in flight may predate the change that prompted the request, so
  /// it is voided and the loop reads once more (#41 freshness).
  @visibleForTesting
  Future<void> refreshArticleStatuses() => _refreshArticleStatuses();

  Future<void> _refreshArticleStatuses() {
    if (_statusRefresh != null) {
      _statusGeneration++;
      _statusRefreshQueued = true;
      return _statusRefresh!;
    }
    return _statusRefresh = _runStatusRefreshes();
  }

  Future<void> _runStatusRefreshes() async {
    try {
      do {
        _statusRefreshQueued = false;
        final gen = ++_statusGeneration;
        final map = await listArticleStatuses(
          ArticleRecordStore.of(_box),
          // Files that vanished or are truncated must not back a "ready"
          // label — verify() demotes them for repair (#41).
          media: _statusMedia,
        );
        if (_disposed) return;
        if (gen != _statusGeneration) continue;
        final changed =
            !_articleStatusesLoaded || !mapEquals(map, _articleStatuses);
        _articleStatuses = map;
        _articleStatusesLoaded = true;
        if (changed) notifyListeners();
      } while (_statusRefreshQueued);
    } finally {
      _statusRefresh = null;
    }
  }

  /// Per-feed rate-limit cooldowns. Loaded from Hive at startup so the
  /// background isolate's deadlines are honored here too — and persisted
  /// back after each refresh so the next background pass sees them.
  final FeedBackoff _feedBackoff;

  /// Last fetch failure per feed, persisted across restarts so a dead feed
  /// stays visibly unhealthy instead of silently showing stale cache.
  Map<String, String> _feedErrors = {};
  String? feedErrorFor(String url) => _feedErrors[url];

  String? get selectedCategory => _selectedCategory;
  String? get selectedFeedUrl => _selectedFeedUrl;

  /// Category that owns the individually selected feed — the ancestor node
  /// nav trees highlight when [selectedFeedUrl] is set. `null` when the
  /// selection is a category, the global view, or nothing.
  ///
  /// Resolved live from the subscription so feed moves and category renames
  /// keep the ancestor indicator on the real parent.
  String? get selectedFeedParentCategory {
    if (_selectedFeedUrl == null) return null;
    if (subscriptionProvider != null) {
      for (final sub in subscriptionProvider!.subscriptions) {
        if (sub.url == _selectedFeedUrl) return sub.category;
      }
    }
    return _selectedCategory;
  }

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

  /// The isolate's lifecycle gate, resolved at use time so a gate installed
  /// after construction (entry point, test setup) still governs resets.
  final LifecycleGate? _injectedGate;
  LifecycleGate? get _gate => _injectedGate ?? LifecycleGate.current;

  // ---------------------------------------------------------------------------
  // Initialization & dependency updates
  // ---------------------------------------------------------------------------

  FeedProvider({
    FeedService? feedService,
    @visibleForTesting
    Timer Function(Duration, void Function())? scheduleRefreshPublish,
    ObservedArticleStore? observedArticleStore,
    ArticlePreparationService? preparation,
    HostPacer? hostPacer,
    FeedBackoff? backoff,
    LifecycleGate? gate,
  }) : _injectedGate = gate,
       _scheduleRefreshPublish = scheduleRefreshPublish ?? Timer.new,
       _feedService = feedService ?? FeedService(),
       _ownsPreparation = preparation == null,
       _hostPacer = hostPacer ?? HostPacer(),
       _feedBackoff = backoff ?? FeedBackoff() {
    _preparation =
        preparation ??
        ArticlePreparationService(
          hostPacer: _hostPacer,
          backoff: _feedBackoff,
          gate: gate,
        );
    _observedArticleStore =
        observedArticleStore ?? ObservedArticleStore.forBox(_box, gate: gate);
    // One pacing schedule and one cooldown policy per isolate: feed
    // fetches, full-text extraction, and media downloads to the same
    // host all serialize through the pacer and respect the same
    // rate-limit records.
    FullTextExtractionService.instance.pacer = _hostPacer;
    FullTextExtractionService.instance.backoff = _feedBackoff;
    _refresher = FeedRefresher(
      feedService: _feedService,
      observedArticleStore: _observedArticleStore,
      backoff: _feedBackoff,
      schedule: _feedSchedule,
      hostPacer: _hostPacer,
    );
    _initialization = _loadState();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (_) {},
    );
    // Seed the transport verdict used by status labels — a stale guess
    // would mislabel "waiting for unmetered" articles as "preparing".
    unawaited(
      Connectivity()
          .checkConnectivity()
          .then((r) => _setUnmetered(r))
          .catchError((_) => false),
    );
  }

  /// Offline preparation engine — sweeps durable pending work after each
  /// online refresh, on the transport eligibility terms of the moment.
  late final ArticlePreparationService _preparation;

  /// One pacing schedule for every HTTP service in this isolate — feed
  /// refresh, extraction, and media downloads all reserve same-host
  /// slots through it.
  final HostPacer _hostPacer;

  /// An injected service belongs to its owner (Provider disposes it); a
  /// default-constructed one is this provider's to release.
  final bool _ownsPreparation;

  /// Applies the transport verdict; notifies when it actually flips so a
  /// "waiting for unmetered" label re-renders as "preparing" (or back)
  /// without waiting for the next refresh (#41 freshness).
  void _setUnmetered(List<ConnectivityResult> results) {
    final next = ArticlePreparationService.unmeteredNetwork(results);
    if (next == _unmetered || _disposed) return;
    _unmetered = next;
    notifyListeners();
  }

  /// Re-sync as soon as connectivity returns after an offline stretch —
  /// otherwise a device that sat through a flap waits for the next timer tick.
  /// Gated on `_isOffline` so a momentary blip while online stays free.
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;
    _setUnmetered(results);
    if (!_isOffline) return;
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    if (!hasNetwork) return;
    // Connectivity appearing mid-sync — an in-flight pass that ran fully
    // offline must be followed by a real one; [refreshAll] decides once the
    // pass settles, so a pass that reached the network is not repeated.
    if (_isSyncing) {
      _connectivityReturnedMidPass = true;
    } else {
      refreshAll();
    }
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
    // Cache-membership inputs (#37): a change here must recompute selection
    // immediately — no network wait — so snapshot them for comparison.
    final int prevCacheLimit = settingsProvider?.offlineCacheLimit ?? -1;
    final bool prevAutoFullText = settingsProvider?.autoFullText ?? false;

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
    final nextBookmarkInstances = {
      for (final item in book.bookmarkedItems) (item.feedUrl, item.id),
    };
    final bookmarkInstancesChanged = !setEquals(
      _lastBookmarkInstances,
      nextBookmarkInstances,
    );
    final inputsChanged =
        bookmarkInstancesChanged ||
        feedFilterInputsChanged(
          prevGlobalKeywords: _lastGlobalKeywords,
          nextGlobalKeywords: nextGlobalKeywords,
          prevFeedKeywords: _lastFeedKeywords,
          nextFeedKeywords: nextFeedKeywords,
          prevBookmarkIds: _lastBookmarkIds,
          nextBookmarkIds: nextBookmarkIds,
        );
    _lastGlobalKeywords = nextGlobalKeywords;
    _lastFeedKeywords = nextFeedKeywords;
    // "Only show" lists (#69) are filter inputs too.
    final nextFeedOnly = _feedOnlyKeywords(sub);
    final onlyChanged =
        _lastFeedOnlyKeywords == null ||
        _lastFeedOnlyKeywords!.length != nextFeedOnly.length ||
        nextFeedOnly.entries.any(
          (e) => !listEquals(_lastFeedOnlyKeywords![e.key], e.value),
        );
    _lastFeedOnlyKeywords = nextFeedOnly;
    // "Mark read" rules apply to the loaded articles when they change.
    final nextReadRules = List<String>.of(set.globalReadKeywords);
    final readRulesChanged = !listEquals(_lastReadRules, nextReadRules);
    if (readRulesChanged) {
      _lastReadRules = nextReadRules;
      _readRules = [for (final r in nextReadRules) ?KeywordRule.tryParse(r)];
    }
    // Marks are not membership input: only the hide/only lists are.
    final rulesMarked = readRulesChanged && _applyReadRules();
    final filterChanged = inputsChanged || onlyChanged;
    _lastBookmarkIds = nextBookmarkIds;
    _lastBookmarkInstances = nextBookmarkInstances;

    // A durable bookmark-claim mutation (strip/prepare) lands AFTER the
    // bookmark set already changed — its completion bumps this version.
    // Re-running membership + status refresh on the bump keeps labels from
    // reading a record mid-strip (#41 ordering).
    final claimsChanged = book.claimVersion != _lastClaimVersion;
    _lastClaimVersion = book.claimVersion;

    final currentUrls = sub.subscriptions.map((s) => s.url).toSet();
    final subscriptionsChanged = !setEquals(
      _knownSubscriptionUrls,
      currentUrls,
    );
    _knownSubscriptionUrls = Set.unmodifiable(currentUrls);

    // A same-URL tri-state flip (on/off/follow-global) changes each feed's
    // effective extraction preference — a membership input (#37) that the
    // URL-set comparison above cannot see.
    final nextFullText = <String, bool?>{
      for (final s in sub.subscriptions) s.url: s.fullTextEnabled,
    };
    final fullTextPrefsChanged = !mapEquals(_knownFullTextPrefs, nextFullText);
    _knownFullTextPrefs = nextFullText;

    if (isFirstUpdate) {
      refreshAll();
      _manageCacheTimer();
      return;
    }

    if (filterChanged || rulesMarked) {
      // Rebuild filter output — cheap, O(n) walk already cached.
      _invalidateFilterCache();
      Future.microtask(() {
        if (!_disposed) notifyListeners();
      });
    }

    // Only recreate the background sync timer when interval or toggle changes.
    // Previously this always fired, resetting the countdown on every tap.
    final bool timerSettingsChanged =
        prevInterval != set.cacheIntervalSeconds ||
        prevSync != set.syncBackground;
    if (timerSettingsChanged) {
      _manageCacheTimer();
    }

    // Membership inputs changed (limit, keywords, bookmark set, full-text
    // preference, subscriptions) → recompute temp membership + snapshot now,
    // without waiting for a network pass (#37). Runs through the serialized
    // save chain so it can't interleave with an in-flight refresh write.
    // (isFirstUpdate already returned above.)
    if (filterChanged ||
        subscriptionsChanged ||
        fullTextPrefsChanged ||
        claimsChanged ||
        prevCacheLimit != set.offlineCacheLimit ||
        prevAutoFullText != set.autoFullText) {
      _saveCachedItems().ignore();
    }

    // If subscriptions were added/removed, kick off a fresh fetch. A running
    // pass that fetched the OLD set earns a trailing pass; one that already
    // read the new set (onboarding/Explore refresh right after adding) or
    // has not read it yet covers the change, so this just attaches.
    if (subscriptionsChanged) {
      final fetching = _passSubscriptionUrls;
      refreshAll(
        queueIfRunning: fetching != null && !setEquals(fetching, currentUrls),
      );
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
    // Legacy global 'readItemIds' is migration input only — never rewritten.
    final List<dynamic>? legacyReadIds = _box.get('readItemIds');
    final storedReads = _box.get('readItemRefs');
    _readState = ReadState.migrate(
      legacyIds: legacyReadIds?.cast<String>() ?? const [],
      stored: storedReads is Map ? storedReads : null,
    );

    final feedErrors = _box.get('feedErrors');
    if (feedErrors is Map) {
      _feedErrors = feedErrors.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    }

    _loadFeedBackoff();
    final exempt = _box.get(_ruleExemptKey);
    if (exempt is List) {
      _ruleExempt.addAll([
        for (final pair in exempt)
          if (pair case [final String feedUrl, final String id]) (feedUrl, id),
      ]);
    }

    final String? cachedItemsData = _box.get('cachedItemsJson');
    if (cachedItemsData != null) {
      try {
        // Decode JSON in a background isolate — large caches can be 500ms+ on
        // main thread for users with many feeds.
        final maps = await compute(_decodeCachedItems, cachedItemsData);
        _items = maps.map(FeedItem.fromJson).toList();
        _invalidateFilterCache();
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading cached items: $e');
      }
    }
    _bindLegacyReads();
    _applyReadRules();
  }

  /// "Only show" rules per feed, as filter and membership input.
  static Map<String, List<String>> _feedOnlyKeywords(
    SubscriptionProvider sub,
  ) => {
    for (final s in sub.subscriptions)
      if (s.onlyKeywords.isNotEmpty) s.url: List<String>.of(s.onlyKeywords),
  };

  /// Articles set back to unread by hand, which "mark read" rules leave
  /// alone from then on (persisted, bounded to loaded articles).
  final _ruleExempt = <(String, String)>{};
  static const _ruleExemptKey = 'readRuleExemptions';

  void _saveRuleExemptions() {
    if (_ruleExempt.length > 500) {
      final live = {for (final i in _items) (i.feedUrl, i.id)};
      _ruleExempt.retainWhere(live.contains);
    }
    _box.put(_ruleExemptKey, [
      for (final (feedUrl, id) in _ruleExempt) [feedUrl, id],
    ]);
  }

  /// Marks unread loaded articles matching a "mark read" rule (#69) and
  /// persists that; returns whether anything changed so callers rebuild.
  /// An article marked unread by hand is never read again by a rule.
  bool _applyReadRules() {
    if (_readRules.isEmpty) return false;
    var changed = false;
    for (final item in _items) {
      if (_readState.isRead(item) ||
          _ruleExempt.contains((item.feedUrl, item.id))) {
        continue;
      }
      if (_readRules.any(
        (r) => r.matches(title: item.title, description: item.description),
      )) {
        changed = _readState.mark(item, read: true) || changed;
      }
    }
    if (changed) {
      _invalidateFilterCache();
      _scheduleReadStateSave();
    }
    return changed;
  }

  /// Gives unresolved legacy read ids to the instances now in view (items
  /// and bookmarks), once; persists when that changed anything.
  void _bindLegacyReads() {
    final bound = _readState.bindLegacy([
      ..._items,
      ...?bookmarkProvider?.bookmarkedItems,
    ]);
    if (bound) {
      _invalidateFilterCache();
      unawaited(_saveReadStates());
    }
  }

  /// Hard cap on persisted read ids — pruning only above this keeps normal
  /// behavior intact: a trimmed article that reappears in a later fetch must
  /// keep its read mark (unlike a hard-pruned set, which forgets it).
  static const int _readIdsHardCap = 10000;

  /// Pending batched write of read marks; see [_scheduleReadStateSave].
  Timer? _readSaveTimer;

  /// Read marks change on every opened article and each write serializes
  /// the whole set, so user marks are batched into one write after a quiet
  /// second. [flushReadStates] writes early (app paused, dispose).
  void _scheduleReadStateSave() {
    _readSaveTimer?.cancel();
    _readSaveTimer = Timer(const Duration(seconds: 1), () {
      _readSaveTimer = null;
      unawaited(_saveReadStates());
    });
  }

  /// Writes a pending batch of read marks now.
  Future<void> flushReadStates() async {
    if (_readSaveTimer == null) return;
    _readSaveTimer!.cancel();
    _readSaveTimer = null;
    await _saveReadStates();
  }

  Future<void> _saveReadStates() async {
    // Bounded-growth path: above the cap keep marks only for articles still
    // reachable (current items or bookmarks). Beyond the cap, forgetting
    // read marks for evicted articles is cheaper than an ever-growing set.
    _readState.prune(
      live: [..._items, ...?bookmarkProvider?.bookmarkedItems],
      cap: _readIdsHardCap,
    );
    await _box.put('readItemRefs', _readState.toStored());
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

  /// Loads persisted cooldown snapshots written by either isolate. Each
  /// writer owns its own slot (`feedBackoffUntil` for the foreground,
  /// `feedBackoffUntil.bg` for the background isolate) and every reader
  /// merges both — there is no shared read-modify-write register, so
  /// concurrent isolates can't lose each other's cooldowns. Loading
  /// merges: later expiries win, newer clears suppress superseded
  /// records.
  void _loadFeedBackoff() {
    _feedBackoff.loadSlots(_box);
    _feedSchedule.loadSlots(_box);
  }

  /// Merge-then-write into this isolate's own slot: a background sync may
  /// have recorded a fresher 429 while this isolate was fetching — folding
  /// its slot in before the snapshot means the write can't drop a newer
  /// deadline. The background slot is never written from here.
  void _saveFeedBackoff() {
    _feedBackoff.saveSlot(_box, FeedBackoff.foregroundSlot);
    _feedSchedule.saveSlot(
      _box,
      FeedSchedule.foregroundSlot,
      subscriptionProvider?.subscriptions.map((s) => s.url) ?? const [],
    );
  }

  /// Last fetch per feed (#68), persisted next to the cooldowns.
  final _feedSchedule = FeedSchedule();

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

  /// The current view before the cross-feed dedup: every copy of a link
  /// the list shows once. Cached with the filtered list.
  List<FeedItem> get _viewItems =>
      _viewItemsCache ??= _applyViewFilters().toList();

  Iterable<FeedItem> _applyViewFilters() {
    final globalKeywords = settingsProvider?.globalExcludedKeywords ?? [];
    final Map<String, List<String>> feedKeywordsMap = {};
    if (subscriptionProvider != null) {
      for (final sub in subscriptionProvider!.subscriptions) {
        if (sub.excludedKeywords.isNotEmpty) {
          feedKeywordsMap[sub.url] = sub.excludedKeywords;
        }
      }
    }

    return applyFeedFilters(
      items: _items,
      isRead: _readState.isRead,
      // Feed-scoped views track the live parent category (moves/renames);
      // a stale snapshot would AND-filter the feed's items out.
      selectedCategory: _selectedFeedUrl != null
          ? selectedFeedParentCategory
          : _selectedCategory,
      selectedFeedUrl: _selectedFeedUrl,
      searchQuery: _searchQuery,
      readFilter: _readFilter,
      filterCategories: _filterCategories,
      globalKeywords: globalKeywords,
      feedKeywordsMap: feedKeywordsMap,
      feedOnlyKeywordsMap: subscriptionProvider == null
          ? const {}
          : _feedOnlyKeywords(subscriptionProvider!),
      dedupe: false,
    );
  }

  /// The full list of items after applying all active filters (unread, category,
  /// feed, search, keyword exclusion) and decorating with read/bookmark state.
  ///
  /// Result is cached and invalidated whenever filter inputs change.
  List<FeedItem> get _filteredItems {
    if (_filteredItemsCache != null) return _filteredItemsCache!;

    // One row per article (the first copy, cross-feed dedup); the row is
    // read only when every copy the view holds is (#70).
    _filteredItemsCache = [
      for (final copies in _viewGroups.values)
        copies.first.copyWith(
          isRead: copies.every(_readState.isRead),
          isBookmarked:
              bookmarkProvider?.isBookmarked(
                copies.first.id,
                feedUrl: copies.first.feedUrl,
              ) ??
              false,
        ),
    ];

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

  /// Cached date-group result; cleared with the filter cache and when the
  /// render window grows.
  FeedDateGroups? _dateGroupsCache;

  /// Returns the single-pass date-grouped result for the current visible items.
  FeedDateGroups get _dateGroups =>
      _dateGroupsCache ??= groupFeedItemsByDate(_visibleItems, DateTime.now());

  /// The date-grouped view of the visible render window. The returned
  /// instance is memoized and replaced whenever data changes — suitable for
  /// `context.select` so widgets rebuild only on real data changes, not on
  /// status-only notifications (`isLoading`, connectivity flips).
  FeedDateGroups get dateGroups => _dateGroups;

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

    // The window is unchanged until the next frame — keep the same groups
    // so date-group selectors don't rebuild for the spinner alone.
    _isLoadingMore = true;
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

  /// Whether this source instance of the article has been read.
  bool isRead(FeedItem item) => _readState.isRead(item);

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
    // An article several feeds carry is one row in a view, so one unread
    // count: overall, per folder and per feed, as the lists show them (#70).
    final counted = <Object>{};
    final countedInCategory = <String, Set<Object>>{};
    final countedInFeed = <String, Set<Object>>{};
    for (final item in _items) {
      if (_readState.isRead(item)) continue;
      final key = _keyOf(item);
      if (counted.add(key)) total++;
      if ((countedInCategory[item.category] ??= {}).add(key)) {
        byCategory[item.category] = (byCategory[item.category] ?? 0) + 1;
      }
      if ((countedInFeed[item.feedUrl] ??= {}).add(key)) {
        byFeed[item.feedUrl] = (byFeed[item.feedUrl] ?? 0) + 1;
      }
    }
    _unreadByCategory = byCategory;
    _unreadByFeed = byFeed;
    _unreadTotal = total;
  }

  /// Marks this source instance as read, with the copies the current view
  /// hides behind it (no-op if nothing changed).
  Future<void> markAsRead(FeedItem item) async {
    if (_markWithViewCopies([item], read: true) > 0) {
      _invalidateFilterCache();
      notifyListeners();
      _scheduleReadStateSave();
    }
  }

  /// Marks all articles in [category] as read in one atomic operation.
  Future<void> markAllInCategoryAsRead(String category) async {
    var changed = false;
    for (final item in _items) {
      if (item.category != category) continue;
      changed = _readState.mark(item, read: true) || changed;
    }
    if (!changed) return;
    _invalidateFilterCache();
    notifyListeners();
    _scheduleReadStateSave();
  }

  /// Unread articles in the current view (folder, feed, search and sheet
  /// filters — the whole filtered list, not just the render window),
  /// optionally only those published more than [olderThan] ago. Undated
  /// articles count as old, as in the date groups. Copies of a link the
  /// list shows once count too, as in the unread badges: a hidden copy
  /// stays unread when its shown twin was opened.
  List<FeedItem> unreadInView({Duration? olderThan}) {
    final cutoff = olderThan == null
        ? null
        : DateTime.now().subtract(olderThan);
    // One entry per article, as the badges count; marking it marks the
    // copies the view hides.
    return [
      for (final copies in _viewGroups.values)
        if (copies.where((c) => !_readState.isRead(c)).firstOrNull
            case final unread?
            when cutoff == null ||
                copies.first.pubDate == null ||
                copies.first.pubDate!.isBefore(cutoff))
          unread,
    ];
  }

  /// Whether the current view has an unread article, hidden copies
  /// included — cheap enough for a `select`, it stops at the first one.
  bool get hasUnreadInView =>
      _viewItems.any((item) => !_readState.isRead(item));

  // The article key per item object, so a link is normalized once per
  // article rather than on every open and recount (#70).
  final _keys = Expando<Object>();
  Object _keyOf(FeedItem item) => _keys[item] ??= articleKey(item);

  /// The current view's copies per article, in list order; cached with the
  /// view.
  Map<Object, List<FeedItem>> get _viewGroups => _viewGroupsCache ??= () {
    final groups = <Object, List<FeedItem>>{};
    for (final item in _viewItems) {
      (groups[_keyOf(item)] ??= []).add(item);
    }
    return groups;
  }();

  /// [item] with the copies of it the current view holds — only when
  /// [item] is in the view: an article opened from elsewhere (bookmarks)
  /// is just itself.
  List<FeedItem> _copiesInView(FeedItem item) {
    final copies = _viewGroups[_keyOf(item)];
    return copies != null && copies.contains(item) ? copies : [item];
  }

  /// Marks [items] as read in one operation and returns how many changed.
  /// Callers pass the list they showed the user, so articles arriving in
  /// the meantime are not marked unseen. The current view shows one copy of
  /// a link that several of its feeds carry (`deduplicateByLink`); the
  /// copies it hides are marked with it. Copies outside the view (another
  /// folder) are separate rows there and keep their own read state.
  Future<int> markItemsAsRead(Iterable<FeedItem> items) async {
    final marked = _markWithViewCopies(items, read: true);
    if (marked == 0) return 0;
    _invalidateFilterCache();
    notifyListeners();
    _scheduleReadStateSave();
    return marked;
  }

  /// Every read mark as `(feedUrl, id)`, for a backup.
  Set<(String, String)> get readRefs => _readState.refs;

  /// Adds read marks from a backup; articles need not be loaded. Stops at
  /// the hard cap: above it the next save keeps only marks of loaded
  /// articles, which right after a restore would drop the restored ones.
  void restoreReadRefs(Iterable<(String, String)> refs) {
    final room = _readIdsHardCap - _readState.refs.length;
    if (room <= 0 || !_readState.markRefs(refs.take(room))) return;
    _invalidateFilterCache();
    notifyListeners();
    _scheduleReadStateSave();
  }

  /// Sets [read] on [items] and, for an item in the current view, on the
  /// copies of it the view hides (`deduplicateByLink`) — the row stands for
  /// all of them. Copies outside the view (another folder) are separate
  /// rows there and keep their own state; an item opened from outside the
  /// view (bookmarks) changes only itself. Returns how many marks changed.
  int _markWithViewCopies(Iterable<FeedItem> items, {required bool read}) {
    var changed = 0;
    for (final item in items) {
      for (final copy in _copiesInView(item)) {
        if (_readState.mark(copy, read: read)) changed++;
      }
    }
    return changed;
  }

  /// Toggles the read/unread state of this source instance and of the
  /// copies the current view hides behind it. [item] carries the state its
  /// row shows (`isRead`): a feed row its group's, a bookmark row its own.
  Future<void> toggleReadStatus(FeedItem item) async {
    // Flip what the caller showed: a feed row carries its group's state,
    // a bookmark row its own copy's.
    final copies = _copiesInView(item);
    final read = !item.isRead;
    _markWithViewCopies([item], read: read);
    // Unread by hand outranks the "mark read" rules (#69).
    var exemptionsChanged = false;
    for (final copy in copies) {
      final key = (copy.feedUrl, copy.id);
      exemptionsChanged =
          (read ? _ruleExempt.remove(key) : _ruleExempt.add(key)) ||
          exemptionsChanged;
    }
    if (exemptionsChanged) _saveRuleExemptions();
    _invalidateFilterCache();
    notifyListeners();
    _scheduleReadStateSave();
  }

  // ---------------------------------------------------------------------------
  // Refresh & sync
  // ---------------------------------------------------------------------------

  /// Feeds behind a web page the user entered instead of a feed address,
  /// paced with the other requests to the same host.
  Future<List<DiscoveredFeed>> discoverFeeds(FeedPage page) async {
    final found = await _feedService.discoverFeeds(page, pace: _hostPacer.pace);
    // The add that follows fetches a feed on a host discovery just hit.
    if (found.length == 1) await _hostPacer.pace(found.single.url);
    return found;
  }

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
    // A factoryReset landing mid-transaction voids the whole add: the
    // subscription, its articles, validators, claims and cache writes all
    // belong to the wiped era (#40).
    final resetGeneration = _resetGeneration;
    try {
      // Captured before the request: only this era may publish its claims.
      final ticket = await _gate?.beginWork();
      final prefetched = await _feedService.fetchFeed(url, category);
      if (prefetched.notModified) {
        throw Exception('Authoritative subscription fetch returned 304.');
      }
      if (resetGeneration != _resetGeneration) return false;

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
      if (resetGeneration != _resetGeneration) {
        // The reset landed after addFeed — compensate the subscription
        // write so the wiped box stays wiped.
        await subscriptions.removeFeed(url);
        _knownSubscriptionUrls = previousKnownUrls;
        return false;
      }
      final subscription = subscriptions.subscriptions.firstWhere(
        (item) => item.url == url,
      );
      await _applyNewSubscriptionResult(subscription, prefetched, ticket);
      return true;
    } catch (e) {
      debugPrint('Failed to add feed $url: $e');
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
    LifecycleTicket? ticket,
  ) async {
    final merged = _items
        .where((item) => item.feedUrl != subscription.url)
        .toList();
    merged.addAll(result.items);
    // Clamps implausible future dates (mislabeled tz, CMS clock skew) so
    // they can't pin above legitimately newer items.
    sortByEffectivePubDateDesc(merged, DateTime.now());
    _items = merged;
    _bindLegacyReads();
    _applyReadRules();

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
      ticket: ticket,
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
  ///
  /// Calls arriving while a pass is already running normally *attach* to it —
  /// a manual click, a timer tick, or a resume asking for "a sync" is already
  /// served by the in-flight pass. Pass `queueIfRunning: true` only when the
  /// caller knows the in-flight pass read stale inputs (a subscription set it
  /// did not fetch) so it is followed by one fresh pass — never an unbounded
  /// queue. Connectivity regained mid-pass earns that pass only when the
  /// in-flight one still ended offline.
  /// [userInitiated] marks passes driven by an explicit user action (refresh
  /// button, pull-to-refresh). A user request arriving mid-pass attaches to
  /// the running pass — no duplicate pass — and still marks it so the
  /// completion toast summarizes the operation the user is waiting for.
  Future<void> refreshAll({
    bool queueIfRunning = false,
    bool userInitiated = false,
  }) async {
    await _initialization;
    if (_disposed || subscriptionProvider == null) return;

    if (_isSyncing) {
      // An automatic pass may skip feeds whose own interval is not up; a
      // user asking now gets one trailing pass that fetches every feed.
      // Without such feeds the running pass already covers the request.
      final skipsIntervals =
          !_refreshIsUserInitiated &&
          subscriptionProvider!.subscriptions.any(
            (s) => s.refreshIntervalMinutes != null,
          );
      if (queueIfRunning || (userInitiated && skipsIntervals)) {
        _refreshQueued = true;
      }
      if (userInitiated) {
        _refreshIsUserInitiated = true;
        refreshProgress.value = refreshProgress.value.copyWith(
          userInitiated: true,
        );
      }
      return (_refreshWaiter ??= Completer<void>()).future;
    }

    _isSyncing = true;
    _refreshIsUserInitiated = userInitiated;
    Object? failure;
    StackTrace? failureStack;
    try {
      do {
        _refreshQueued = false;
        _connectivityReturnedMidPass = false;
        _passSubscriptionUrls = null;
        await _performRefresh();
      } while (_refreshQueued || (_connectivityReturnedMidPass && _isOffline));
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
      if (!_disposed) {
        refreshProgress.value = refreshProgress.value.copyWith(
          phase: RefreshPhase.failed,
          inFlight: 0,
          completedAt: DateTime.now(),
        );
      }
      rethrow;
    } finally {
      // Always clear the guard, even if a fetch/persist step throws — otherwise
      // the provider would deadlock and never refresh again.
      _isSyncing = false;
      _refreshIsUserInitiated = false;
      _passSubscriptionUrls = null;
      _connectivityReturnedMidPass = false;
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
    // Fixed when the pass starts: a user request joining later is served by
    // the trailing pass refreshAll queues for it.
    final honorIntervals = !_refreshIsUserInitiated;
    _isLoading = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    // A factoryReset landing mid-fetch must void the whole apply phase:
    // subscriptions, items, validators, notifications, and the widget all
    // belong to the era being wiped (#40).
    final resetGeneration = _resetGeneration;
    // Lifecycle ticket before any input snapshot or HTTP: observation
    // claims of this pass publish only while its era is current.
    final ticket = await _gate?.beginWork();

    // Pick up cooldowns the background isolate wrote since the last
    // pass — a stale in-memory snapshot must never bypass a fresh 429.
    _loadFeedBackoff();
    final cacheGeneration = _cacheGeneration;
    final subscriptions = List<FeedSubscription>.of(
      subscriptionProvider!.subscriptions,
    );
    _passSubscriptionUrls = {for (final s in subscriptions) s.url};
    final epochs = {for (final s in subscriptions) s.url: s.notificationEpoch};
    final refreshGeneration = ++_refreshGeneration;
    final freshByFeed = <String, List<FeedItem>>{};
    var acceptingPublications = true;
    bool isCurrent() =>
        refreshGeneration == _refreshGeneration &&
        !_disposed &&
        resetGeneration == _resetGeneration &&
        cacheGeneration == _cacheGeneration;
    List<FeedItem> mergeCurrent() => FeedCachePolicy.mergeVisibleFeeds(
      existingItems: _items,
      freshItemsByFeed: {
        for (final s in subscriptionProvider!.subscriptions)
          if (epochs[s.url] == s.notificationEpoch &&
              freshByFeed.containsKey(s.url))
            s.url: freshByFeed[s.url]!,
      },
      subscribedFeedUrls: subscriptionProvider!.subscriptions.map((s) => s.url),
      bookmarkedItems: bookmarkProvider?.bookmarkedItems ?? const [],
      now: DateTime.now(),
    );
    void publish() {
      if (!acceptingPublications || !isCurrent()) return;
      _refreshPublishTimer = null;
      _items = mergeCurrent();
      _bindLegacyReads();
      _applyReadRules();
      _isOffline = false;
      _invalidateFilterCache();
      notifyListeners();
    }

    refreshProgress.value = RefreshProgress(
      phase: RefreshPhase.refreshing,
      total: subscriptions.length,
      completedAt: refreshProgress.value.completedAt,
      userInitiated: _refreshIsUserInitiated,
    );
    final FeedRefreshResult result;
    try {
      result = await _refresher.refresh(
        subscriptions: subscriptions,
        existingItems: _items,
        validators: _loadFeedValidators(),
        bookmarkedItems: bookmarkProvider?.bookmarkedItems ?? const [],
        redirects: _loadFeedRedirects(),
        ticket: ticket,
        honorIntervals: honorIntervals,
        // Observation survives cache eviction, but not a factory reset or
        // the removal/replacement of this subscription namespace.
        canObserve: (url, epoch) =>
            !_disposed &&
            resetGeneration == _resetGeneration &&
            subscriptionProvider!.subscriptions.any(
              (s) => s.url == url && s.notificationEpoch == epoch,
            ),
        onFreshFeed: (url, items) {
          if (!isCurrent()) return;
          freshByFeed[url] = items;
          _refreshPublishTimer ??= _scheduleRefreshPublish(
            const Duration(milliseconds: 100),
            publish,
          );
        },
        onProgress:
            ({
              required total,
              required completed,
              required succeeded,
              required failed,
              required skipped,
              required inFlight,
            }) {
              if (!isCurrent()) return;
              refreshProgress.value = refreshProgress.value.copyWith(
                total: total,
                completed: completed,
                succeeded: succeeded,
                failed: failed,
                skipped: skipped,
                inFlight: inFlight,
              );
            },
      );
    } catch (_) {
      // Even a later orchestration/storage failure must not hide successful
      // bodies already received, or leave the loading state stuck forever.
      if (!_disposed) _isLoading = false;
      if (isCurrent()) {
        if (_refreshPublishTimer != null) {
          _refreshPublishTimer!.cancel();
          publish();
        } else {
          notifyListeners();
        }
      }
      rethrow;
    } finally {
      acceptingPublications = false;
      _refreshPublishTimer?.cancel();
      _refreshPublishTimer = null;
    }

    if (_disposed) return;
    final suppressDelivery = !_hasLoadedOnce;
    // Observation already advanced inside the refresher, so even an
    // interrupted apply ends first-load suppression. Only a reset voids it.
    if (resetGeneration == _resetGeneration) _hasLoadedOnce = true;
    if (!isCurrent()) {
      // Cache clearing invalidates article writes, not server Retry-After.
      // Only a factory reset discards the old era's cooldown state.
      if (resetGeneration == _resetGeneration) _saveFeedBackoff();
      _isLoading = false;
      refreshProgress.value = refreshProgress.value.copyWith(
        phase: RefreshPhase.idle,
        inFlight: 0,
      );
      if (!_disposed) notifyListeners();
      return;
    }

    _saveFeedValidators(result.validators);
    _saveFeedRedirects(result.redirects);
    _saveFeedBackoff();
    _updateFeedErrors(result.feedErrors, result.unprovenUrls);
    // Reconcile against live subscriptions/bookmarks and any articles added
    // during this pass, not the stale inputs captured before HTTP started.
    _items = mergeCurrent();
    _bindLegacyReads();
    _applyReadRules();
    // A pass that skipped every feed (none due, or all cooling down) did
    // not touch the network: it is a finished no-op, not an offline pass.
    final networkUnknown = !result.attempted;
    if (!networkUnknown) _isOffline = !result.online;
    _isLoading = false;
    refreshProgress.value = refreshProgress.value.copyWith(
      // online==false with real HTTP errors means every feed failed for a
      // definitive reason — report 'failed', not 'offline'. Offline is only
      // when failures were connectivity-unproven.
      phase: networkUnknown
          ? RefreshPhase.completed
          : !result.online
          ? (result.feedErrors.isEmpty
                ? RefreshPhase.offline
                : RefreshPhase.failed)
          : result.feedErrors.isNotEmpty
          ? RefreshPhase.completedWithErrors
          : RefreshPhase.completed,
      inFlight: 0,
      completedAt: DateTime.now(),
    );
    _invalidateFilterCache();
    if (!_disposed) notifyListeners();

    // Listeners may clear/reset/dispose synchronously on completion.
    if (!isCurrent()) return;

    // First foreground load suppresses delivery only. Observation already
    // advanced above, so these articles cannot backfill on a later refresh.
    if (!suppressDelivery) {
      final activeEpochs = {
        for (final s in subscriptionProvider!.subscriptions)
          s.url: s.notificationEpoch,
      };
      await _deliverClaimedArticles([
        for (final item in result.claimedItems)
          if (activeEpochs.containsKey(item.feedUrl) &&
              activeEpochs[item.feedUrl] == epochs[item.feedUrl])
            item,
      ]);
    }
    if (!isCurrent()) return;

    // Persist a new cache snapshot when a feed returned new data — and once
    // unconditionally, so the durable owner layer bootstraps even when the
    // very first pass is all-304 or fully offline (#37).
    if (result.anyFreshBody || _needsInitialReconcile) {
      _needsInitialReconcile = false;
      await _saveCachedItems();
    }
    if (!isCurrent()) return;

    stopwatch.stop();
    _lastSyncDuration = stopwatch.elapsed;
    // Stamp only when a feed actually reached the network — an all-offline
    // pass must not look like a real sync to the resume/periodic gates.
    if (result.online || networkUnknown) _lastSyncTime = DateTime.now();
    // Notify debug screen that sync state + timestamps have updated.
    if (!_disposed) notifyListeners();

    // Refresh widget ages on every completed pass, not only when a feed body
    // changed — otherwise the "5m" strings written last cycle freeze in place.
    WidgetUpdateService.updateFeedWidgets(_items).ignore();

    // Offline-first: durable preparation fetches article bodies and media
    // so they read without a network. Runs after the refresh settles —
    // never blocks it.
    if (result.online) {
      // Sweep durable preparation work on the CURRENT transport's terms —
      // metered/unknown waits for the next unmetered opportunity. The
      // verdict is queried fresh here: the cached stream value can be
      // stale right after resume (wifi→mobile handoff).
      unawaited(() async {
        final gen = _resetGeneration;
        try {
          final results = await Connectivity().checkConnectivity();
          if (!isCurrent()) return;
          _setUnmetered(results);
          await _preparation.preparePending(unmetered: _unmetered);
          // A page/media 429 during the sweep cooled a shared host —
          // persist now so the next refresh pass and the bg isolate
          // see it even if the app dies before the next sync. Skip the
          // write if a factory reset landed mid-sweep — the box and the
          // in-memory cooldowns were already wiped.
          if (gen == _resetGeneration) _saveFeedBackoff();
          // Preparation commits landed — labels may now claim ready.
          await _refreshArticleStatuses();
        } catch (_) {
          // Connectivity plugin absence or a storage error simply defers
          // the sweep to the next refresh — never a crash path.
        }
      }());
    }
  }

  /// Set once [dispose] runs so async continuations skip
  /// [notifyListeners], which throws on a disposed [ChangeNotifier].
  bool _disposed = false;

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
      latestItemJson: latestJson,
    );
  }

  // ---------------------------------------------------------------------------
  // Cache persistence
  // ---------------------------------------------------------------------------

  /// Serializes [cachedItemsJson] writes. Membership-change and sweep saves
  /// are fire-and-forget and can overlap a refresh save — unsynchronized,
  /// an older snapshot could `put` last and regress the durable cache.
  /// Chaining keeps writes ordered.
  Future<void> _saveChain = Future<void>.value();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// True until the first refresh completes one membership pass — an
  /// all-304/offline first load must still establish durable owners.
  bool _needsInitialReconcile = true;

  /// Bumped by cache-clearing operations ([clearCache], [factoryReset]) so an
  /// in-flight [cachedItemsJson] write started before the reset cannot land
  /// its stale snapshot after the delete.
  int _cacheGeneration = 0;
  int _refreshGeneration = 0;

  /// Bumped only by [factoryReset]: an in-flight refresh that started before
  /// the reset must void its entire apply phase — items, validators,
  /// notifications and widget data all belong to the wiped era (#40).
  int _resetGeneration = 0;

  Future<void> _bumpCacheEpoch() => _box.put(
    tempCacheEpochKey,
    DateTime.now().toUtc().microsecondsSinceEpoch,
  );

  /// Completes once queued cache saves and preparation mutations drained.
  @visibleForTesting
  Future<void> get idle async {
    while (true) {
      final chain = _saveChain;
      await chain;
      await _preparation.idle;
      if (identical(chain, _saveChain)) return;
    }
  }

  @visibleForTesting
  Future<void> saveCachedItems() => _saveCachedItems();

  Future<void> _saveCachedItems() {
    // The fence is captured at ENQUEUE time, not when the link runs —
    // a clearCache landing while this link is still queued must kill it,
    // and the execution-time read would let it slip through post-clear.
    final generation = _cacheGeneration;
    // A queued link that has not started reads items, settings and the
    // bookmark set when it runs, so a request in the same era joins it
    // instead of repeating the whole reconcile + encode + write.
    final queued = _queuedSave;
    if (queued != null && queued.generation == generation) return queued.run;
    late final Future<void> run;
    run = _saveChain.then((_) {
      if (identical(_queuedSave?.run, run)) _queuedSave = null;
      return _writeCachedItems(generation);
    });
    _queuedSave = (run: run, generation: generation);
    // Keep the chain usable after a failed write instead of poisoning it.
    _saveChain = run.catchError((_) {});
    return run;
  }

  /// The save link waiting behind [_saveChain]; see [_saveCachedItems].
  ({Future<void> run, int generation})? _queuedSave;

  /// Lazily-built temp membership reconciler — shares this provider's
  /// preparation service so registration rides the same op queue.
  TempCacheMembership? _tempMembership;

  TempCacheMembership get _membership =>
      _tempMembership ??= TempCacheMembership(
        records: ArticleRecordStore.of(_box),
        preparation: _preparation,
      );

  /// Recomputes temp membership per #37 and persists the transient item
  /// cache. Membership changes happen here — not at download time — so an
  /// N change or keyword edit takes effect without waiting for a refresh.
  Future<void> _writeCachedItems(int generation) async {
    // Wait out the startup load: an update()-triggered save reconciling an
    // empty _items would strip every owner and write '[]' over the still-
    // unread persisted snapshot.
    await _initialization;
    final settings = settingsProvider;
    final subscriptions = subscriptionProvider;
    final bookmarks = bookmarkProvider;
    if (settings == null || subscriptions == null || bookmarks == null) {
      return;
    }
    // Legacy Hive bookmarks must have their durable claims before membership
    // selection and cleanup can make decisions about the archive.
    await bookmarks.restoration;
    // [generation] was captured when the caller enqueued this write —
    // a clearCache/factoryReset landing before this link ran already
    // bumped it, voiding both the badge ids and the file write below.
    if (generation != _cacheGeneration) return;
    // Persisted lifecycle epoch — carried by every record mutation this
    // pass issues, so a factoryReset landing mid-reconcile rejects the
    // remaining writes instead of resurrecting wiped members (#40).
    final recordEpoch = await _preparation.currentRecordEpoch();
    final int limit = settings.offlineCacheLimit;
    final items = List<FeedItem>.of(_items);

    final selected = await _membership.reconcile(
      items: items,
      isBookmarked: bookmarks.isBookmarkedRef,
      subscribedFeedUrls: subscriptions.subscriptions.map((s) => s.url),
      globalKeywords: settings.globalExcludedKeywords,
      feedKeywordsMap: {
        for (final sub in subscriptions.subscriptions)
          if (sub.excludedKeywords.isNotEmpty) sub.url: sub.excludedKeywords,
      },
      feedOnlyKeywordsMap: _feedOnlyKeywords(subscriptions),
      limit: limit,
      fullTextFor: (feedUrl) => subscriptions.effectiveFullText(
        feedUrl,
        autoFullText: settings.autoFullText,
      ),
      epoch: recordEpoch,
    );
    // Lifecycle hygiene rides the same pass: whatever membership just
    // released gets its bytes evaluated for collection (#40). The predicate
    // reads the LIVE bookmark set at commit time — a materialized snapshot
    // could wrongly strip a claim toggled on after enqueue.
    _preparation.sweepCleanup(isBookmarked: bookmarks.isBookmarkedRef).ignore();
    if (generation != _cacheGeneration) return;
    // The transient snapshot = selected members plus bookmarked items
    // (bookmarks never consume a temp slot but must stay browsable offline).
    final itemsToCache = [
      for (final item in items)
        if (selected.contains(ArticleRef.of(item)) ||
            bookmarks.isBookmarked(item.id, feedUrl: item.feedUrl))
          item,
    ];

    // Encode JSON in a background isolate — avoids blocking scroll/animation
    // while serializing potentially hundreds of items.
    final maps = itemsToCache.map((e) => e.toJson()).toList();
    final String encodedData = await compute(_encodeCachedItems, maps);
    // A reset landed while encoding — dropping the write preserves the wipe.
    if (generation != _cacheGeneration) return;
    await _box.put('cachedItemsJson', encodedData);
    // Membership/ownership settled for this pass — refresh row labels.
    unawaited(_refreshArticleStatuses());
  }

  /// Clears all cached offline articles — temp membership included (#40):
  /// records keep other owners and contents; the sweep reclaims the bytes
  /// that lose their last owner.
  Future<void> clearCache() async {
    _cacheGeneration++;
    _refreshPublishTimer?.cancel();
    _refreshPublishTimer = null;
    // Back to "loading": an empty+loaded map would flash "could not save"
    // on every bookmarked row until the refresh lands.
    _statusGeneration++;
    _articleStatuses = const {};
    _articleStatusesLoaded = false;
    // bump → delete → bump: a bg write that validated the first epoch can
    // still lose to the delete, so the second bump fences it entirely —
    // the same pattern factoryReset uses around box.clear().
    await _bumpCacheEpoch();
    await _box.delete('cachedItemsJson');
    await _bumpCacheEpoch();
    // Cross-isolate fence on the RECORD side too: a background task's
    // fenced mutations captured before this bump are now rejected, so an
    // in-flight bg reconcile can't re-add owners the strip removes (#40).
    await ArticleRecordStore.of(_box).bumpEpoch();
    // The strip rides the save chain: an in-flight write's step-4
    // registrations must finish BEFORE owners are removed, or a queued
    // registerArticle would resurrect the owner the strip just dropped.
    // The record epoch fences the strips against a mid-strip wipe.
    final run = _saveChain.then((_) async {
      final stripEpoch = await _preparation.currentRecordEpoch();
      return _membership.reconcile(
        items: const [],
        isBookmarked: (_) => false,
        subscribedFeedUrls:
            subscriptionProvider?.subscriptions.map((s) => s.url) ??
            const <String>[],
        globalKeywords: const [],
        feedKeywordsMap: const {},
        limit: 0,
        fullTextFor: (_) => false,
        epoch: stripEpoch,
      );
    });
    _saveChain = run.catchError((_) => <ArticleRef>{});
    await run.catchError((_) => <ArticleRef>{});
    // The strip just released every tempCache claim — collect the bytes
    // that are now unreferenced (#40: clearCache frees temp-only media).
    // The predicate reads the LIVE bookmark set at commit time so a claim
    // toggled on after this call is never wrongly stripped.
    _preparation
        .sweepCleanup(
          isBookmarked: (ref) =>
              bookmarkProvider?.isBookmarkedRef(ref) ?? false,
        )
        .ignore();
    unawaited(_refreshArticleStatuses());
    if (!_disposed) notifyListeners();
  }

  /// Clears all feed data, caches, and read states, resetting to default.
  /// Returns false when the durable record sidecar could not be wiped —
  /// the caller must not claim a clean erase then (#40 honesty rule). With
  /// a lifecycle gate the wipe is a journaled reset: a failure leaves it
  /// pending, so no new work starts until startup recovery finishes it.
  Future<bool> factoryReset() async {
    discardStateForReset();
    final wiped = await AppResetService.run(_gate, [
      (AppResetService.feeds, wipeStorageForReset),
    ]);
    finishReset();
    return wiped;
  }

  /// In-memory half of a reset, run BEFORE the storage stages: voids every
  /// in-flight apply phase and fences queued writes.
  void discardStateForReset() {
    _items.clear();
    _invalidateFilterCache();
    _selectedCategory = null;
    _selectedFeedUrl = null;
    _readState.clear();
    _ruleExempt.clear();
    _readSaveTimer?.cancel();
    _readSaveTimer = null;
    _statusGeneration++;
    _articleStatuses = const {};
    _articleStatusesLoaded = false;
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
    _resetGeneration++; // an in-flight refresh's apply phase is now void
    _refreshPublishTimer?.cancel();
    _refreshPublishTimer = null;
    // Rate-limit state belongs to the wiped era too — otherwise an async
    // save (prep sweep) could resurrect it into the new box.
    _feedBackoff.reset();
    _feedSchedule.reset();
    _needsInitialReconcile = true; // the next era bootstraps owners again
    _knownSubscriptionUrls = const {};
    // Queued record writes enqueued before the reset must no-op — a delayed
    // registration can never resurrect a wiped record (#40).
    _preparation.resetFence();
  }

  /// The feed storage stage: cache box, durable records, observation
  /// history and managed media. Throws when a sidecar wipe fails.
  Future<void> wipeStorageForReset() =>
      AppResetService.wipeFeedStorage(observed: _observedArticleStore);

  /// Publishes the empty post-reset state.
  void finishReset() {
    // Widgets read from shared storage — publish the empty state so stale
    // articles/categories don't survive the reset.
    unawaited(WidgetUpdateService.updateFeedWidgets(const []));
    _invalidateFilterCache();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(flushReadStates());
    _disposed = true;
    _cacheGeneration++;
    _refreshGeneration++;
    _cacheTimer?.cancel();
    _refreshPublishTimer?.cancel();
    _connectivitySub?.cancel();
    refreshProgress.dispose();
    _feedService.dispose();
    if (_ownsPreparation) _preparation.dispose();
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
