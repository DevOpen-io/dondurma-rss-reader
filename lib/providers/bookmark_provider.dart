import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../models/feed_item.dart';

class BookmarkProvider extends ChangeNotifier {
  List<FeedItem> _savedBookmarks = [];
  Set<String> _bookmarkedItemIds = {};

  List<FeedItem> get bookmarkedItems => _savedBookmarks;
  Set<String> get bookmarkedItemIds => _bookmarkedItemIds;

  BookmarkProvider() {
    _loadBookmarks();
  }

  void _loadBookmarks() {
    final box = Hive.box('bookmarks');
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
    notifyListeners();
  }

  Future<void> _saveBookmarkStates() async {
    final box = Hive.box('bookmarks');
    final String data = jsonEncode(
      _savedBookmarks.map((b) => b.toJson()).toList(),
    );
    await box.put('bookmarkedItemsJson', data);
    await box.put('bookmarkedItemIds', _bookmarkedItemIds.toList());
  }

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
    _saveBookmarkStates();
  }

  bool isBookmarked(String id) {
    return _bookmarkedItemIds.contains(id);
  }
}
