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

  /// Updates the feed-based widgets (Latest, Category).
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
        _saveCategory(sorted),
      ]);
      await Future.wait([
        HomeWidget.updateWidget(
          androidName: 'widgets.LatestNewsWidgetReceiver',
          iOSName: 'LatestNewsWidget',
        ),
        HomeWidget.updateWidget(
          androidName: 'widgets.CategoryWidgetReceiver',
          iOSName: 'CategoryWidget',
        ),
      ]);
    } catch (e) {
      debugPrint('WidgetUpdateService.updateFeedWidgets: $e');
    }
  }

  static Future<void> _saveLatest(List<FeedItem> sorted) async {
    final items = sorted.take(50).map(_toMap).toList();
    await HomeWidget.saveWidgetData<String>(
      'widget_latest',
      jsonEncode(items),
    );
  }

  /// Writes per-category article buckets so the native category widget can
  /// render whichever category the user picked at configuration time.
  static Future<void> _saveCategory(List<FeedItem> sorted) async {
    if (sorted.isEmpty) return;
    final byCategory = <String, List<Map<String, String>>>{};
    for (final item in sorted) {
      if (item.category == 'Uncategorized') continue;
      final bucket = byCategory.putIfAbsent(item.category, () => []);
      if (bucket.length < 50) bucket.add(_toMap(item));
    }
    if (byCategory.isEmpty) return;
    await HomeWidget.saveWidgetData<String>(
      'widget_category_list',
      jsonEncode(byCategory.keys.toList()),
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_category_data',
      jsonEncode(byCategory),
    );
  }

  static Map<String, String> _toMap(FeedItem item) => {
    'id': item.id,
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
