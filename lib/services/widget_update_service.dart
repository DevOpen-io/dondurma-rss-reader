import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/feed_item.dart';

/// Saves app data into HomeWidget shared storage so Android/iOS home screen
/// widgets can read and display the latest state.
class WidgetUpdateService {
  static const _appGroupId = 'group.io.devopen.dondurma';
  static bool _initialized = false;

  static void initialize() {
    HomeWidget.setAppGroupId(_appGroupId);
    _initialized = true;
  }

  /// Updates the feed-based widgets (Latest, Trending, Category).
  static Future<void> updateFeedWidgets(List<FeedItem> allItems) async {
    if (!_initialized) initialize();
    try {
      final sorted = allItems.toList()
        ..sort((a, b) {
          if (a.pubDate == null) return 1;
          if (b.pubDate == null) return -1;
          return b.pubDate!.compareTo(a.pubDate!);
        });

      await Future.wait([
        _saveLatest(sorted),
        _saveTrending(sorted),
        _saveCategory(sorted),
      ]);
      await Future.wait([
        HomeWidget.updateWidget(
          androidName: 'LatestNewsWidgetReceiver',
          iOSName: 'LatestNewsWidget',
        ),
        HomeWidget.updateWidget(
          androidName: 'TrendingWidgetReceiver',
          iOSName: 'TrendingWidget',
        ),
        HomeWidget.updateWidget(
          androidName: 'CategoryWidgetReceiver',
          iOSName: 'CategoryWidget',
        ),
      ]);
    } catch (e) {
      debugPrint('WidgetUpdateService.updateFeedWidgets: $e');
    }
  }

  /// Updates the Read Later (bookmarks) widget.
  static Future<void> updateBookmarkWidget(List<FeedItem> bookmarked) async {
    if (!_initialized) initialize();
    try {
      final items = bookmarked.take(5).map(_toMap).toList();
      await HomeWidget.saveWidgetData<String>(
        'widget_bookmarks',
        jsonEncode(items),
      );
      await HomeWidget.updateWidget(
        androidName: 'ReadLaterWidgetReceiver',
        iOSName: 'ReadLaterWidget',
      );
    } catch (e) {
      debugPrint('WidgetUpdateService.updateBookmarkWidget: $e');
    }
  }

  static Future<void> _saveLatest(List<FeedItem> sorted) async {
    final items = sorted.take(5).map(_toMap).toList();
    await HomeWidget.saveWidgetData<String>(
      'widget_latest',
      jsonEncode(items),
    );
  }

  static Future<void> _saveTrending(List<FeedItem> sorted) async {
    if (sorted.isEmpty) return;
    final t = sorted.first;
    final desc = t.description.length > 120
        ? '${t.description.substring(0, 120)}...'
        : t.description;
    await HomeWidget.saveWidgetData<String>('widget_trending', jsonEncode({
      'title': t.title,
      'siteName': t.siteName,
      'description': desc,
      'link': t.link,
      'timeAgo': _formatTime(t.pubDate),
    }));
  }

  static Future<void> _saveCategory(List<FeedItem> sorted) async {
    if (sorted.isEmpty) return;
    final counts = <String, int>{};
    for (final item in sorted) {
      if (item.category != 'Uncategorized') {
        counts[item.category] = (counts[item.category] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return;
    final topCat =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final catItems =
        sorted.where((i) => i.category == topCat).take(5).map(_toMap).toList();
    await HomeWidget.saveWidgetData<String>('widget_category', jsonEncode({
      'name': topCat,
      'articles': catItems,
    }));
  }

  static Map<String, String> _toMap(FeedItem item) => {
    'title': item.title,
    'siteName': item.siteName,
    'timeAgo': _formatTime(item.pubDate),
    'link': item.link,
  };

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }
}
