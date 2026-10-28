import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_item.dart';
import '../services/article_identity.dart';
import '../services/article_preparation_service.dart';
import '../services/article_record_store.dart';

/// Manages the user's bookmarked (saved) articles with Hive persistence.
///
/// Stores both full JSON representations of bookmarked [FeedItem]s and an
/// ID set for backward compatibility with the legacy storage format.
class BookmarkProvider extends ChangeNotifier {
  List<FeedItem> _savedBookmarks = [];
  Set<String> _bookmarkedItemIds = {};
  Map<String, Set<String>> _snapshotFeedsById = {};
  Set<ArticleRef> _snapshotRefs = {};

  /// Normalized ids of legacy ID-only bookmarks (no snapshot proves their
  /// source); rebuilt with the other indexes.
  Set<String> _legacyOnlyIds = {};

  void _indexSnapshots() {
    _snapshotFeedsById = {};
    for (final item in _savedBookmarks) {
      (_snapshotFeedsById[item.id] ??= {}).add(item.feedUrl);
    }
    _snapshotRefs = {for (final item in _savedBookmarks) ArticleRef.of(item)};
    _legacyOnlyIds = {
      for (final id in _bookmarkedItemIds)
        if (!_snapshotFeedsById.containsKey(id))
          ArticleIdentity.normalizeItemId(id) ?? id,
    };
  }

  /// Live bookmark claim of one durable record instance: a saved snapshot,
  /// or a legacy ID-only membership (no source known) with the same id.
  /// Called per item and per record, so both checks are set lookups.
  bool isBookmarkedRef(ArticleRef ref) =>
      _snapshotRefs.contains(ref) || _legacyOnlyIds.contains(ref.id);

  /// Bumped each time a durable bookmark-claim mutation lands — strip or
  /// prepare. FeedProvider diffs it in update() so the offline-status map
  /// is only read AFTER claim changes commit, never before (#41 ordering).
  int _claimVersion = 0;
  int get claimVersion => _claimVersion;

  bool _disposed = false;
  int _restoreGeneration = 0;

  /// Startup restoration writes only local records; automatic downloads keep
  /// their usual unmetered-network gate. Cache cleanup waits for this future.
  late final Future<void> restoration;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _claimLanded() {
    _claimVersion++;
    if (!_disposed) notifyListeners();
  }

  /// The full list of bookmarked articles.
  List<FeedItem> get bookmarkedItems => _savedBookmarks;

  /// The set of bookmarked article IDs (for fast lookups).
  Set<String> get bookmarkedItemIds => _bookmarkedItemIds;

  /// Lazily cached reference to the `'bookmarks'` Hive box.
  Box get _box => Hive.box('bookmarks');

  /// Offline preparation engine — persists the durable record when a
  /// bookmark is saved, then prepares its content in one permitted pass.
  final ArticlePreparationService? _preparation;

  /// The effective full-text preference for a bookmark's feed — the save
  /// path must respect the same tri-state rule the membership pass and
  /// the save-retry path use (#41 consistency).
  final bool Function(String feedUrl)? _fullTextFor;

  BookmarkProvider({
    ArticlePreparationService? preparation,
    bool Function(String feedUrl)? fullTextFor,
  }) : _preparation = preparation,
       _fullTextFor = fullTextFor {
    _loadBookmarks();
    restoration = _restoreDurableBookmarks();
  }

  Future<void> _restoreDurableBookmarks() async {
    final prep = _preparation;
    if (prep == null || _savedBookmarks.isEmpty) return;
    final snapshot = List<FeedItem>.of(_savedBookmarks);
    final generation = _restoreGeneration;
    var restored = false;
    try {
      final epoch = await prep.currentRecordEpoch();
      for (final item in snapshot) {
        bool claimStillLive() =>
            !_disposed &&
            generation == _restoreGeneration &&
            isBookmarked(item.id, feedUrl: item.feedUrl);
        if (_disposed || generation != _restoreGeneration) return;
        if (!claimStillLive()) continue;
        final fullText = _fullTextFor?.call(item.feedUrl) ?? true;
        var result = await prep.registerArticle(
          item,
          const {'bookmark'},
          fullText: fullText,
          expectedEpoch: epoch,
          claimCheck: claimStillLive,
        );
        if (result == StoreWriteResult.failed && claimStillLive()) {
          result = await prep.registerArticle(
            item,
            const {'bookmark'},
            fullText: fullText,
            expectedEpoch: epoch,
            claimCheck: claimStillLive,
          );
        }
        restored = restored || result == StoreWriteResult.applied;
      }
    } catch (error) {
      // Preserve the Hive copy on failure; retry-save or the next startup can
      // restore the archive without a one-time migration flag hiding failure.
      debugPrint('Bookmark archive restoration failed: $error');
    }
    if (restored && !_disposed && generation == _restoreGeneration) {
      _claimLanded();
    }
  }

  /// Durable records live on the feeds-box archive — the same file the
  /// feed/background reconcilers share, so owner writes serialize globally.
  ArticleRecordStore? _records;
  ArticleRecordStore get _recordStore =>
      _records ??= ArticleRecordStore.forBox(Hive.box('feeds'));

  /// Drops the durable 'bookmark' claim after an un-bookmark. The bookmark
  /// set is re-checked inside the store's locked mutation so a re-bookmark
  /// racing this call can never lose its owner. When a preparation service
  /// is attached the strip rides its register queue — FIFO with delayed
  /// registrations means the toggle order IS the durable order, and a
  /// queued registerArticle can never re-add the owner being stripped.
  void _stripBookmarkOwner(ArticleRef ref) {
    final prep = _preparation;
    unawaited(() async {
      for (var attempt = 0; attempt < 2; attempt++) {
        final result = prep != null
            ? await prep.mutateRecord(ref, _stripBookmarkMutation(ref))
            : await _recordStore.mutate(ref, _stripBookmarkMutation(ref));
        // Fenced by a reset: nothing landed, and the new era owns cleanup.
        if (result == StoreWriteResult.rejected) return;
        if (result != StoreWriteResult.failed) {
          // Claim is durable now — listeners may re-derive status labels.
          _claimLanded();
          // The record may have just become ownerless — release its bytes.
          // The live bookmark set goes along so stale claims elsewhere
          // self-heal in the same pass.
          prep?.sweepCleanup(isBookmarked: isBookmarkedRef).ignore();
          return;
        }
      }
    }());
  }

  ArticleRecord? Function(ArticleRecord?) _stripBookmarkMutation(
    ArticleRef ref,
  ) => (current) {
    if (current == null || isBookmarkedRef(ref)) return current;
    final owners = {...current.owners}..remove('bookmark');
    return owners.length == current.owners.length
        ? current
        : current.copyWith(owners: owners);
  };

  void _loadBookmarks() {
    final String? bookmarkedItemsData = _box.get('bookmarkedItemsJson');
    if (bookmarkedItemsData != null) {
      final List<dynamic> jsonList = jsonDecode(bookmarkedItemsData);
      _savedBookmarks = jsonList.map((e) => FeedItem.fromJson(e)).toList();
      _bookmarkedItemIds = _savedBookmarks.map((e) => e.id).toSet();
    }
    // Legacy ID-only memberships persist beside snapshots: once any
    // snapshot is saved, the ID list is their only record.
    final List<dynamic>? bookmarkedIds = _box.get('bookmarkedItemIds');
    if (bookmarkedIds != null) {
      _bookmarkedItemIds.addAll(bookmarkedIds.cast<String>());
    }
    _indexSnapshots();
    notifyListeners();
  }

  Future<void> _saveBookmarkStates() async {
    final String data = jsonEncode(
      _savedBookmarks.map((b) => b.toJson()).toList(),
    );
    await _box.put('bookmarkedItemsJson', data);
    await _box.put('bookmarkedItemIds', _bookmarkedItemIds.toList());
  }

  /// Toggles the bookmark state of [originalItem].
  ///
  /// If already bookmarked, removes it. Otherwise, adds it with
  /// [isBookmarked] set to `true`. Persistence is fire-and-forget
  /// (not awaited) to keep the UI responsive.
  void toggleBookmark(FeedItem originalItem) {
    final String id = originalItem.id;
    final bool isPresent = isBookmarked(id, feedUrl: originalItem.feedUrl);
    bool matches(FeedItem b) => b.id == id && b.feedUrl == originalItem.feedUrl;

    if (isPresent) {
      _savedBookmarks.removeWhere(matches);
      if (!_savedBookmarks.any((b) => b.id == id)) {
        _bookmarkedItemIds.remove(id);
      }
      _stripBookmarkOwner(ArticleRef.of(originalItem));
    } else {
      _bookmarkedItemIds.add(id);
      final updatedItem = originalItem.copyWith(isBookmarked: true);
      // Source-local snapshots coexist while durable owners retain legacy IDs.
      _savedBookmarks.removeWhere(matches);
      _savedBookmarks.add(updatedItem);
      // New bookmark → persist the minimal record, then prepare this one
      // article in a single pass (the explicit-action metered permit).
      final prep = _preparation;
      if (prep != null) {
        // claimCheck runs INSIDE the store lock at mutation time: an
        // un-bookmark racing this delayed registration leaves no ghost
        // 'bookmark' owner behind — including on the retry.
        bool claimStillLive() =>
            !_disposed && isBookmarked(id, feedUrl: updatedItem.feedUrl);
        final fullText = _fullTextFor?.call(updatedItem.feedUrl) ?? true;
        unawaited(() async {
          var result = await prep.registerArticle(
            updatedItem,
            const {'bookmark'},
            fullText: fullText,
            claimCheck: claimStillLive,
          );
          // One immediate retry on storage failure — a rejected/failed
          // register would otherwise leave a bookmark with no durable
          // record and no later reconciliation.
          if (result == StoreWriteResult.failed && claimStillLive()) {
            result = await prep.registerArticle(
              updatedItem,
              const {'bookmark'},
              fullText: fullText,
              claimCheck: claimStillLive,
            );
          }
          if (result == StoreWriteResult.applied && claimStillLive()) {
            // The claim landed — labels may already read "save requested".
            _claimLanded();
            // Prepare commits land inside this same call; the version bump
            // afterwards lets status readers observe the finished state.
            await prep.prepareArticle(ArticleRef.of(updatedItem));
            _claimLanded();
          }
        }());
      }
    }

    _indexSnapshots();
    notifyListeners();
    // Fire-and-forget: persist bookmark states.
    _saveBookmarkStates();
  }

  /// Persistence seam so tests can simulate write failures without a real
  /// Hive box (box writes cannot be forced to fail deterministically in
  /// widget tests).
  @visibleForTesting
  Future<void> persistBookmarks() => _saveBookmarkStates();

  /// Removes [item] from bookmarks, awaiting persistence.
  ///
  /// Returns `false` and restores the in-memory record if the write fails so
  /// the article stays visibly bookmarked instead of silently rolling back.
  Future<bool> removeBookmark(FeedItem item) async {
    bool matches(FeedItem b) => b.id == item.id && b.feedUrl == item.feedUrl;
    final index = _savedBookmarks.indexWhere(matches);
    // ID-only legacy bookmarks carry membership without any snapshot.
    final legacy = index < 0 && isBookmarked(item.id, feedUrl: item.feedUrl);
    if (index < 0 && !legacy) return true;
    final removed = legacy ? null : _savedBookmarks.removeAt(index);
    if (!_savedBookmarks.any((b) => b.id == item.id)) {
      _bookmarkedItemIds.remove(item.id);
    }
    _indexSnapshots();
    notifyListeners();
    try {
      await persistBookmarks();
      _stripBookmarkOwner(ArticleRef.of(item));
      return true;
    } catch (_) {
      // De-dupe in case the item was re-bookmarked while the write was in
      // flight, then restore the record at its original position.
      _savedBookmarks.removeWhere(matches);
      if (removed != null) {
        _savedBookmarks.insert(index.clamp(0, _savedBookmarks.length), removed);
      }
      _bookmarkedItemIds.add(item.id);
      _indexSnapshots();
      notifyListeners();
      // The failed write may have been partially applied (first put ok,
      // second failed); converge disk with the restored state.
      unawaited(persistBookmarks().catchError((_) {}));
      return false;
    }
  }

  /// Returns `true` if the article with [id] is bookmarked.
  bool isBookmarked(String id, {String? feedUrl}) {
    if (!_bookmarkedItemIds.contains(id)) return false;
    if (feedUrl == null) return true;
    // ID-only legacy bookmarks have no source information. Preserve their
    // global membership until an actual article snapshot becomes available.
    final feeds = _snapshotFeedsById[id];
    return feeds == null || feeds.contains(feedUrl);
  }

  /// Clears all bookmarks and resets to default state.
  Future<void> factoryReset() async {
    _restoreGeneration++;
    _savedBookmarks.clear();
    _bookmarkedItemIds.clear();
    _indexSnapshots();
    await _box.clear();
    notifyListeners();
  }
}
