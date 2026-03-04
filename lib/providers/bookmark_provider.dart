import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_item.dart';

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

  BookmarkProvider() {
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
    }

    notifyListeners();
    // Fire-and-forget: persist asynchronously without blocking the UI.
    _saveBookmarkStates();
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
