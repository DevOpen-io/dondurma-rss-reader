import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import 'feed_service.dart';
import 'notification_service.dart';
import 'widget_update_service.dart';

/// Unique name of the periodic background fetch task.
const String _bgTaskName = 'rss_bg_fetch';

/// WorkManager dispatcher entry-point. Runs in a background isolate, so it must
/// be a top-level function annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBgFetch();
    } catch (e) {
      debugPrint('[WM] task error: $e');
    }
    // Always report success — a failed fetch shouldn't trigger WorkManager's
    // exponential backoff retry; the next periodic run will try again.
    return true;
  });
}

/// Registers the periodic background fetch task. Idempotent — `keep` policy
/// means re-registering on every launch never resets an existing schedule.
Future<void> registerBgFetch() async {
  await Workmanager().registerPeriodicTask(
    _bgTaskName,
    _bgTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
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
          final result = await feedService.fetchFeed(sub.url, sub.category);
          return result.items;
        } catch (_) {
          return <FeedItem>[];
        }
      }),
    );

    final allItems = results.expand((i) => i).toList();
    debugPrint('[BG] fetched ${allItems.length} items total');

    // Always persist the full ID set so the next run has a baseline
    await feedsBox.put('bgKnownItemIds', allItems.map((i) => i.id).toList());

    // Persist fresh items into the main cache + home-screen widgets so the next
    // app launch (and the widgets) show up-to-date news without waiting for an
    // in-app refresh. Runs on every successful fetch, including the first run
    // and runs with no new items (which short-circuit notification below).
    if (allItems.isNotEmpty) {
      await _persistBgCache(feedsBox, settingsBox, allItems);
      await WidgetUpdateService.updateFeedWidgets(allItems);
    }

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

/// Writes the freshly fetched items into the `'feeds'` box `cachedItemsJson`
/// key, sorted newest-first and capped to the user's offline cache limit, using
/// the same format [FeedProvider] reads on startup.
Future<void> _persistBgCache(
  Box feedsBox,
  Box settingsBox,
  List<FeedItem> items,
) async {
  final int limit = settingsBox.get('offlineCacheLimit', defaultValue: 50);
  if (limit == 0) return; // offline cache disabled

  final sorted = items.toList()
    ..sort((a, b) {
      if (a.pubDate == null && b.pubDate == null) return 0;
      if (a.pubDate == null) return 1;
      if (b.pubDate == null) return -1;
      return b.pubDate!.compareTo(a.pubDate!);
    });

  final maps = sorted.take(limit).map((e) => e.toJson()).toList();
  await feedsBox.put('cachedItemsJson', jsonEncode(maps));
}
