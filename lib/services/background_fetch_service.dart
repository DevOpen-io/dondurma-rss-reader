import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import 'feed_service.dart';
import 'notification_service.dart';

const bgFetchTaskName = 'bgFetchFeeds';

/// WorkManager callback dispatcher. Must be a top-level function.
/// The @pragma annotation prevents tree-shaking in release builds.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
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
        return true;
      }

      // Only instant mode supported in background
      final String digestMode =
          settingsBox.get('digestMode', defaultValue: 'instant');
      if (digestMode != 'instant') {
        debugPrint('[BG] digestMode=$digestMode, skip');
        return true;
      }

      // Quiet hours
      final bool quietHoursEnabled =
          settingsBox.get('quietHoursEnabled', defaultValue: true);
      if (quietHoursEnabled) {
        final int quietStart =
            settingsBox.get('quietHoursStart', defaultValue: 22);
        final int quietEnd =
            settingsBox.get('quietHoursEnd', defaultValue: 7);
        if (NotificationService.isInQuietHours(
          DateTime.now().hour,
          quietStart,
          quietEnd,
        )) {
          debugPrint('[BG] quiet hours active, skip');
          return true;
        }
      }

      // Read subscriptions
      final String? subsData = feedsBox.get('subscriptions');
      if (subsData == null) return true;
      final List<dynamic> subsList = jsonDecode(subsData);
      final subscriptions =
          subsList.map((e) => FeedSubscription.fromJson(e)).toList();
      if (subscriptions.isEmpty) return true;

      // Previously seen item IDs (persisted across bg runs)
      final List<dynamic>? knownIdsList = feedsBox.get('bgKnownItemIds');
      final Set<String> knownIds =
          knownIdsList?.cast<String>().toSet() ?? {};

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
      await feedsBox.put(
        'bgKnownItemIds',
        allItems.map((i) => i.id).toList(),
      );

      // On first ever bg run knownIds is empty — skip notification to avoid
      // flooding the user with every currently-fetched article.
      if (knownIds.isEmpty) {
        debugPrint('[BG] first run, saved ${allItems.length} IDs, skip notify');
        return true;
      }

      // Recency guard: only notify for articles published in the last 48 hours.
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

      if (newItems.isEmpty) return true;

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

      return true;
    } catch (e) {
      debugPrint('Background fetch error: $e');
      return false;
    }
  });
}
