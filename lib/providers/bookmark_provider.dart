import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_item.dart';
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
        unawaited(() async {
          var result = await prep.registerArticle(updatedItem, const {
            'bookmark',
          });
          // One immediate retry on storage failure — a rejected/failed
          // register would otherwise leave a bookmark with no durable
          // record and no later reconciliation.
          if (result == StoreWriteResult.failed) {
            result = await prep.registerArticle(updatedItem, const {
              'bookmark',
            });
          }
          if (result == StoreWriteResult.applied) {
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
