import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import 'article_identity.dart';
import 'article_preparation_service.dart';
import 'feed_backoff.dart';
import 'article_record_store.dart';
import 'temp_cache_membership.dart';
import 'feed_cache_policy.dart';
import 'feed_service.dart';
import '../utils/async_semaphore.dart';
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
    await Future.wait([
      Hive.openBox('settings'),
      Hive.openBox('feeds'),
      Hive.openBox('bookmarks'),
    ]);
    await NotificationService.instance.init();

    final settingsBox = Hive.box('settings');
    final feedsBox = Hive.box('feeds');
    // Read-only in this isolate — bookmark ids exclude articles from temp
    // slots so a saved article never consumes a transient one (#37).
    final bookmarksBox = Hive.box('bookmarks');
    final bookmarkedIds =
        (bookmarksBox.get('bookmarkedItemIds') as List<dynamic>?)
            ?.cast<String>()
            .toSet() ??
        const <String>{};
    // Bookmarked articles ride the transient snapshot uncounted — including
    // ones whose feeds are no longer subscribed, which the merge below would
    // otherwise evict (#37).
    var bookmarkedItems = const <FeedItem>[];
    try {
      bookmarkedItems = <FeedItem>[
        for (final entry
            in (jsonDecode(
                  bookmarksBox.get('bookmarkedItemsJson') as String? ?? '[]',
                )
                as List<dynamic>))
          FeedItem.fromJson(entry as Map<String, dynamic>),
      ];
    } catch (_) {
      // Malformed persisted bookmarks degrade to none rather than failing
      // the whole background pass.
    }

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

    // Fetch all feeds — at learned redirect URLs when the foreground learned
    // one, so background passes skip the 301 hop too.
    final rawRedirects = feedsBox.get('feedRedirects');
    final redirects = <String, String>{};
    if (rawRedirects is String && rawRedirects.isNotEmpty) {
      try {
        for (final e in (jsonDecode(rawRedirects) as Map).entries) {
          redirects[e.key.toString()] = e.value.toString();
        }
      } catch (_) {}
    }
    // Shared cooldown policy — deadlines written by the foreground refresher
    // are honored here, and limits hit here are persisted back so the next
    // foreground pass does not re-hammer a rate-limited feed either.
    final backoff = FeedBackoff();
    try {
      final rawBackoff = feedsBox.get('feedBackoffUntil');
      if (rawBackoff is String && rawBackoff.isNotEmpty) {
        backoff.load(jsonDecode(rawBackoff) as Map<String, dynamic>);
      }
    } catch (_) {}
    final validators = <String, dynamic>{};
    try {
      final rawValidators = feedsBox.get('feedValidators');
      if (rawValidators is String && rawValidators.isNotEmpty) {
        validators.addAll(jsonDecode(rawValidators) as Map<String, dynamic>);
      }
    } catch (_) {}

    final feedService = FeedService();
    // Same bounded concurrency as the foreground refresher — an unbounded
    // fan-out on constrained devices trips TCP resets and rate limiters.
    final semaphore = AsyncSemaphore(5);
    final results = await Future.wait(
      subscriptions.map((sub) async {
        // A feed inside its cooldown keeps its durable articles — the merge
        // only replaces feeds with an authoritative fresh response anyway.
        if (backoff.isBackedOff(sub.url, DateTime.now())) {
          return (
            subscription: sub,
            items: <FeedItem>[],
            succeeded: false,
            fresh: false,
            allowInitialization: false,
          );
        }
        await semaphore.acquire();
        final fetchUrl = redirects[sub.url] ?? sub.url;
        try {
          final v = validators[sub.url];
          final result = await feedService.fetchFeed(
            fetchUrl,
            sub.category,
            etag: v?['etag'] as String?,
            lastModified: v?['lastModified'] as String?,
          );
          backoff.recordSuccess(sub.url);
          if (result.etag != null || result.lastModified != null) {
            validators[sub.url] = {
              'etag': result.etag,
              'lastModified': result.lastModified,
            };
          } else if (!result.notModified) {
            validators.remove(sub.url);
          }
          return (
            subscription: sub,
            items: fetchUrl == sub.url
                ? result.items
                // Re-tag learned-URL items to canonical — the merge below is
                // keyed by subscription URL.
                : result.items
                      .map((i) => i.copyWith(feedUrl: sub.url))
                      .toList(),
            succeeded: true,
            fresh: !result.notModified,
            allowInitialization: !result.notModified,
          );
        } catch (e) {
          backoff.recordFailure(sub.url, e, DateTime.now());
          return (
            subscription: sub,
            items: <FeedItem>[],
            succeeded: false,
            fresh: false,
            allowInitialization: false,
          );
        } finally {
          semaphore.release();
        }
      }),
    );
    feedService.dispose();
    try {
      await feedsBox.put('feedValidators', jsonEncode(validators));
      await feedsBox.put('feedBackoffUntil', jsonEncode(backoff.snapshot()));
    } catch (_) {}

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

    // Replace only feeds with an authoritative fresh response. Failed and 304
    // feeds retain their durable articles.
    final freshItemsByFeed = <String, List<FeedItem>>{
      for (final result in results)
        if (result.succeeded && result.fresh)
          result.subscription.url: result.items,
    };
    if (freshItemsByFeed.isNotEmpty) {
      final merged = FeedCachePolicy.mergeFreshFeeds(
        existingItems: _readBgCache(feedsBox),
        freshItemsByFeed: freshItemsByFeed,
        subscribedFeedUrls: subscriptions.map((sub) => sub.url),
      );
      final persisted = await _persistBgCache(
        feedsBox,
        settingsBox,
        merged,
        subscriptions,
        bookmarkedIds,
        bookmarkedItems,
      );
      await WidgetUpdateService.updateFeedWidgets(persisted);
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

    // Deliver claimed notifications BEFORE any long-running work — a task
    // killed mid-preparation must not lose articles the durable claim already
    // marked as delivered.
    debugPrint('[BG] ${newItems.length} new items, sending notification');
    if (newItems.isNotEmpty) {
      // Sort newest-first so the notification headline and its tap target are
      // the most recent article — `allItems` arrives in feed-iteration order,
      // not by date, so `.first` would otherwise be an arbitrary new item.
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
    }

    // Permitted background opportunity: prepare durable offline work, but
    // only when the current transport is unmetered — Workmanager's plain
    // `connected` constraint does not distinguish transport cost. Progress is
    // durable, so a task killed mid-sweep simply resumes next time.
    final connectivity = await Connectivity().checkConnectivity();
    if (ArticlePreparationService.unmeteredNetwork(connectivity)) {
      final preparation = ArticlePreparationService(
        recordStore: ArticleRecordStore.forBox(feedsBox),
      );
      try {
        await preparation.preparePending(unmetered: true);
      } finally {
        preparation.dispose();
      }
    }
  } catch (e) {
    debugPrint('Background fetch error: $e');
  }
}

/// Recomputes temp membership and persists the transient snapshot under the
/// same contract as the foreground (#37): global newest-N unique,
/// non-bookmarked, keyword-clean members; bookmarked items ride along
/// uncounted so they stay browsable offline.
Future<List<FeedItem>> _persistBgCache(
  Box feedsBox,
  Box settingsBox,
  List<FeedItem> items,
  List<FeedSubscription> subscriptions,
  Set<String> bookmarkedIds,
  List<FeedItem> bookmarkedItems,
) async {
  final int limit = settingsBox.get('offlineCacheLimit', defaultValue: 50);
  final autoFullText = settingsBox.get('autoFullText', defaultValue: false);
  final globalKeywords =
      (settingsBox.get('globalExcludedKeywords') as List<dynamic>?)
          ?.cast<String>() ??
      const <String>[];

  final store = ArticleRecordStore.forBox(feedsBox);
  final preparation = ArticlePreparationService(recordStore: store);
  final membership = TempCacheMembership(
    records: store,
    preparation: preparation,
  );
  // Fenced against a foreground cache wipe: the epoch key changes under
  // clearCache/factoryReset, so a write started before the wipe must not
  // land after it (the foreground's in-memory generation can't reach here).
  final cacheEpoch = feedsBox.get(tempCacheEpochKey);
  // The record store carries its own lifecycle epoch — every mutation this
  // isolate issues is fenced to it, so a factory reset landing mid-pass
  // rejects the rest of the record writes, not just the snapshot put.
  final recordEpoch = await store.currentEpoch();

  final Set<String> selectedIds;
  try {
    selectedIds = await membership.reconcile(
      items: items,
      bookmarkedIds: bookmarkedIds,
      subscribedFeedUrls: subscriptions.map((s) => s.url),
      globalKeywords: globalKeywords,
      feedKeywordsMap: {
        for (final sub in subscriptions)
          if (sub.excludedKeywords.isNotEmpty) sub.url: sub.excludedKeywords,
      },
      limit: limit,
      fullTextFor: (feedUrl) {
        for (final sub in subscriptions) {
          if (sub.url == feedUrl) {
            return sub.fullTextEnabled ?? autoFullText;
          }
        }
        return autoFullText;
      },
      epoch: recordEpoch,
    );
    // Same lifecycle hygiene as the foreground pass — dropped members'
    // bytes are collected here too. The bookmark reconcile is deliberately
    // NOT run here: this isolate's bookmarkedIds is stale at box-open
    // granularity, and a wrongly-stripped live claim loses user data while
    // a wrongly-kept stale one self-heals on the next foreground sweep.
    await preparation.sweepCleanup();
  } finally {
    preparation.dispose();
  }

  // Snapshot candidates = fresh merge plus bookmarked articles the merge
  // dropped (unsubscribed feeds) — bookmarks ride along uncounted (#37).
  // selectedIds are canonical; item.id is raw — compare on the same side.
  final inMerge = items.map((e) => e.id).toSet();
  final selected = [
    for (final item in items)
      if (selectedIds.contains(
            ArticleIdentity.normalizeItemId(item.id) ?? item.id,
          ) ||
          bookmarkedIds.contains(item.id))
        item,
    for (final item in bookmarkedItems)
      if (!inMerge.contains(item.id)) item,
  ];
  // Two fences before the snapshot write: the persisted cache epoch is a
  // best-effort check (this isolate's box view may be stale), so the
  // record lifecycle epoch — always a fresh disk read — is the real one.
  // A mismatch means a clear/reset landed mid-task: return EMPTY, not the
  // wiped-era snapshot — the caller publishes this to the widget and must
  // not resurrect articles the reset just removed.
  if (feedsBox.get(tempCacheEpochKey) != cacheEpoch ||
      await store.currentEpoch() != recordEpoch) {
    return const <FeedItem>[];
  }
  final maps = selected.map((e) => e.toJson()).toList();
  await feedsBox.put('cachedItemsJson', jsonEncode(maps));
  return selected;
}

List<FeedItem> _readBgCache(Box feedsBox) {
  final raw = feedsBox.get('cachedItemsJson');
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => FeedItem.fromJson(entry as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return const [];
  }
}
