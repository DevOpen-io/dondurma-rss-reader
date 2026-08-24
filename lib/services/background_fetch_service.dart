import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import 'feed_service.dart';
import 'notification_delivery_policy.dart';
import 'notification_service.dart';
import 'observed_article_store.dart';
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
    await Future.wait([Hive.openBox('settings'), Hive.openBox('feeds')]);
    await NotificationService.instance.init();

    final settingsBox = Hive.box('settings');
    final feedsBox = Hive.box('feeds');

    debugPrint('[BG] task started');

    // Delivery settings never short-circuit observation/synchronization.
    final bool notificationsEnabled = settingsBox.get(
      'notificationsEnabled',
      defaultValue: true,
    );
    final String digestMode = settingsBox.get(
      'digestMode',
      defaultValue: 'instant',
    );
    final bool quietHoursEnabled = settingsBox.get(
      'quietHoursEnabled',
      defaultValue: true,
    );
    final int quietStart = settingsBox.get('quietHoursStart', defaultValue: 22);
    final int quietEnd = settingsBox.get('quietHoursEnd', defaultValue: 7);

    // Read subscriptions
    final String? subsData = feedsBox.get('subscriptions');
    if (subsData == null) return;
    final List<dynamic> subsList = jsonDecode(subsData);
    final subscriptions = subsList
        .map((e) => FeedSubscription.fromJson(e))
        .toList();
    if (subscriptions.isEmpty) return;

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
          return (
            subscription: sub,
            items: result.items,
            succeeded: true,
            allowInitialization: !result.notModified,
          );
        } catch (_) {
          return (
            subscription: sub,
            items: <FeedItem>[],
            succeeded: false,
            allowInitialization: false,
          );
        }
      }),
    );
    feedService.dispose();

    final allItems = results.expand((result) => result.items).toList();
    debugPrint('[BG] fetched ${allItems.length} items total');

    final observedStore = ObservedArticleStore.forBox(feedsBox);
    final claimedItems = <FeedItem>[];
    for (final result in results) {
      if (!result.succeeded) continue;
      final claim = await observedStore.claimFeedBatch(
        feedUrl: result.subscription.url,
        observationEpoch: result.subscription.notificationEpoch,
        items: result.items,
        allowInitialization: result.allowInitialization,
      );
      claimedItems.addAll(claim.claimedItems);
    }

    // Persist fresh items into the main cache + home-screen widgets so the next
    // app launch (and the widgets) show up-to-date news without waiting for an
    // in-app refresh. Runs on every successful fetch, including the first run
    // and runs with no new items (which short-circuit notification below).
    if (allItems.isNotEmpty) {
      await _persistBgCache(feedsBox, settingsBox, allItems);
      await WidgetUpdateService.updateFeedWidgets(allItems);
    }

    final newItems = NotificationDeliveryPolicy.eligibleItems(
      claimedItems: claimedItems,
      notificationsEnabled: notificationsEnabled,
      digestMode: digestMode,
      quietHoursEnabled: quietHoursEnabled,
      quietHoursStart: quietStart,
      quietHoursEnd: quietEnd,
      mutedFeedUrls: mutedUrls,
    );

    debugPrint('[BG] ${newItems.length} new items, sending notification');
    if (newItems.isEmpty) return;

    // Sort newest-first so the notification headline and its tap target are the
    // most recent article — `allItems` arrives in feed-iteration order, not by
    // date, so `.first` would otherwise be an arbitrary new item.
    newItems.sort((a, b) => b.pubDate!.compareTo(a.pubDate!));

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
