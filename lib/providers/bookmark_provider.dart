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

  /// The full list of bookmarked articles.
  List<FeedItem> get bookmarkedItems => _savedBookmarks;

  /// The set of bookmarked article IDs (for fast lookups).
  Set<String> get bookmarkedItemIds => _bookmarkedItemIds;

  /// Lazily cached reference to the `'bookmarks'` Hive box.
  Box get _box => Hive.box('bookmarks');

  /// Offline preparation engine — persists the durable record when a
  /// bookmark is saved, then prepares its content in one permitted pass.
  final ArticlePreparationService? _preparation;

  BookmarkProvider({ArticlePreparationService? preparation})
    : _preparation = preparation {
    _loadBookmarks();
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
  void _stripBookmarkOwner(String id) {
    final prep = _preparation;
    unawaited(() async {
      for (var attempt = 0; attempt < 2; attempt++) {
        final result = prep != null
            ? await prep.mutateRecord(id, _stripBookmarkMutation(id))
            : await _recordStore.mutate(id, _stripBookmarkMutation(id));
        if (result != StoreWriteResult.failed) {
          // The record may have just become ownerless — release its bytes.
          // The live bookmark set goes along so stale claims elsewhere
          // self-heal in the same pass.
          prep
              ?.sweepCleanup(
                isBookmarked: (recordId) => _bookmarkedItemIds.any(
                  (b) => (ArticleIdentity.normalizeItemId(b) ?? b) == recordId,
                ),
              )
              .ignore();
          return;
        }
      }
    }());
  }

  ArticleRecord? Function(ArticleRecord?) _stripBookmarkMutation(String id) =>
      (current) {
        if (current == null || _bookmarkedItemIds.contains(id)) {
          return current;
        }
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
    } else {
      // Fallback for legacy ID-only bookmarks
      final List<dynamic>? bookmarkedIds = _box.get('bookmarkedItemIds');
      if (bookmarkedIds != null) {
        _bookmarkedItemIds = bookmarkedIds.cast<String>().toSet();
      }
    }
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
    final bool isPresent = _bookmarkedItemIds.contains(id);

    if (isPresent) {
      _bookmarkedItemIds.remove(id);
      _savedBookmarks.removeWhere((b) => b.id == id);
      _stripBookmarkOwner(id);
    } else {
      _bookmarkedItemIds.add(id);
      final updatedItem = originalItem.copyWith(isBookmarked: true);
      // Remove previously loaded if exists to avoid duplicates
      _savedBookmarks.removeWhere((b) => b.id == id);
      _savedBookmarks.add(updatedItem);
      // New bookmark → persist the minimal record, then prepare this one
      // article in a single pass (the explicit-action metered permit).
      final prep = _preparation;
      if (prep != null) {
        // claimCheck runs INSIDE the store lock at mutation time: an
        // un-bookmark racing this delayed registration leaves no ghost
        // 'bookmark' owner behind — including on the retry.
        bool claimStillLive() => _bookmarkedItemIds.contains(id);
        unawaited(() async {
          var result = await prep.registerArticle(updatedItem, const {
            'bookmark',
          }, claimCheck: claimStillLive);
          // One immediate retry on storage failure — a rejected/failed
          // register would otherwise leave a bookmark with no durable
          // record and no later reconciliation.
          if (result == StoreWriteResult.failed &&
              _bookmarkedItemIds.contains(id)) {
            result = await prep.registerArticle(updatedItem, const {
              'bookmark',
            }, claimCheck: claimStillLive);
          }
          if (result == StoreWriteResult.applied &&
              _bookmarkedItemIds.contains(id)) {
            unawaited(prep.prepareArticle(updatedItem.id));
          }
        }());
      }
    }

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
    final index = _savedBookmarks.indexWhere((b) => b.id == item.id);
    if (index < 0) return true;
    final removed = _savedBookmarks.removeAt(index);
    _bookmarkedItemIds.remove(item.id);
    notifyListeners();
    try {
      await persistBookmarks();
      _stripBookmarkOwner(item.id);
      return true;
    } catch (_) {
      // De-dupe in case the item was re-bookmarked while the write was in
      // flight, then restore the record at its original position.
      _savedBookmarks.removeWhere((b) => b.id == item.id);
      _savedBookmarks.insert(index.clamp(0, _savedBookmarks.length), removed);
      _bookmarkedItemIds.add(item.id);
      notifyListeners();
      // The failed write may have been partially applied (first put ok,
      // second failed); converge disk with the restored state.
      unawaited(persistBookmarks().catchError((_) {}));
      return false;
    }
  }

  /// Returns `true` if the article with [id] is bookmarked.
  bool isBookmarked(String id) {
    return _bookmarkedItemIds.contains(id);
  }

  /// Clears all bookmarks and resets to default state.
  Future<void> factoryReset() async {
    _savedBookmarks.clear();
    _bookmarkedItemIds.clear();
    await _box.clear();
    notifyListeners();
  }
}
