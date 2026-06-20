import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import 'feed_service.dart';
import 'notification_service.dart';

/// Entry-point for the foreground service isolate.
/// Must be a top-level function annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BgFetchTaskHandler());
}

/// Handles periodic background feed fetching inside the foreground service.
class BgFetchTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[FG] service started (starter: ${starter.name})');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    runBgFetch();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[FG] service destroyed (isTimeout: $isTimeout)');
  }
}

/// Fetches all subscribed feeds and fires a notification for new articles.
///
/// Safe to call from both the foreground service isolate and the main isolate
/// (Hive handles re-initialization and already-open boxes gracefully).
Future<void> runBgFetch() async {
  try {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox('settings'),
      Hive.openBox('feeds'),
    ]);
    await NotificationService.instance.init();

    final settingsBox = Hive.box('settings');
    final feedsBox = Hive.box('feeds');

    debugPrint('[BG] task started');

    // Master toggle
    final bool notificationsEnabled =
        settingsBox.get('notificationsEnabled', defaultValue: true);
    if (!notificationsEnabled) {
      debugPrint('[BG] notifications disabled, skip');
      return;
    }

    // Only instant mode fires background notifications
    final String digestMode =
        settingsBox.get('digestMode', defaultValue: 'instant');
    if (digestMode != 'instant') {
      debugPrint('[BG] digestMode=$digestMode, skip');
      return;
    }

    // Quiet hours
    final bool quietHoursEnabled =
        settingsBox.get('quietHoursEnabled', defaultValue: true);
    if (quietHoursEnabled) {
      final int quietStart =
          settingsBox.get('quietHoursStart', defaultValue: 22);
      final int quietEnd = settingsBox.get('quietHoursEnd', defaultValue: 7);
      if (NotificationService.isInQuietHours(
        DateTime.now().hour,
        quietStart,
        quietEnd,
      )) {
        debugPrint('[BG] quiet hours active, skip');
        return;
      }
    }

    // Read subscriptions
    final String? subsData = feedsBox.get('subscriptions');
    if (subsData == null) return;
    final List<dynamic> subsList = jsonDecode(subsData);
    final subscriptions =
        subsList.map((e) => FeedSubscription.fromJson(e)).toList();
    if (subscriptions.isEmpty) return;

    // Previously seen item IDs (persisted across bg runs)
    final List<dynamic>? knownIdsList = feedsBox.get('bgKnownItemIds');
    final Set<String> knownIds = knownIdsList?.cast<String>().toSet() ?? {};

    // Feed URLs where notifications are muted
    final mutedUrls = subscriptions
        .where((s) => !s.notificationsEnabled)
        .map((s) => s.url)
        .toSet();

    // Fetch all feeds
    final feedService = FeedService();
    final results = await Future.wait(
      subscriptions.map((sub) async {
        try {
          return await feedService.fetchFeed(sub.url, sub.category);
        } catch (_) {
          return <FeedItem>[];
        }
      }),
    );

    final allItems = results.expand((i) => i).toList();
    debugPrint('[BG] fetched ${allItems.length} items total');

    // Always persist the full ID set so the next run has a baseline
    await feedsBox.put('bgKnownItemIds', allItems.map((i) => i.id).toList());

    // On first ever bg run knownIds is empty — skip notification to avoid
    // flooding the user with every currently-fetched article.
    if (knownIds.isEmpty) {
      debugPrint('[BG] first run, saved ${allItems.length} IDs, skip notify');
      return;
    }

    // Recency guard: only notify for articles published in the last 48 hours
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));

    final newItems = allItems
        .where(
          (item) =>
              !knownIds.contains(item.id) &&
              !mutedUrls.contains(item.feedUrl) &&
              item.pubDate != null &&
              item.pubDate!.isAfter(cutoff),
        )
        .toList();

    debugPrint('[BG] ${newItems.length} new items, sending notification');
    if (newItems.isEmpty) return;

    final latestJson = jsonEncode(newItems.first.toJson());
    await NotificationService.instance.showNewArticlesNotification(
      newItems: newItems,
      notificationsEnabled: true,
      digestMode: 'instant',
      quietHoursEnabled: false, // already checked above
      quietHoursStart: 0,
      quietHoursEnd: 0,
      latestItemJson: latestJson,
    );
  } catch (e) {
    debugPrint('Background fetch error: $e');
  }
}
