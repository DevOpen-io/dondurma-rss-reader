import 'package:flutter/foundation.dart' show debugPrint;

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import '../utils/async_semaphore.dart';
import 'feed_cache_policy.dart';
import 'feed_service.dart';
import 'observed_article_store.dart';

/// Result of one full refresh pass over all subscriptions.
typedef FeedRefreshResult = ({
  /// The merged item list to replace the provider's `_items` with.
  /// When offline this is the previous items plus any missing bookmarks.
  List<FeedItem> items,

  /// Articles claimed as new by the observed-history store this pass.
  List<FeedItem> claimedItems,

  /// At least one feed reached the network (HTTP 200 or 304).
  bool online,

  /// At least one feed returned an HTTP 200 body — worth persisting.
  bool anyFreshBody,

  /// Updated HTTP cache validators to persist (`feedValidators`).
  Map<String, dynamic> validators,

  /// Per-feed failure detail for feeds that failed this pass
  /// (`feedUrl` → error description). Successful feeds never appear here;
  /// the caller clears their stored error.
  Map<String, String> feedErrors,

  /// Feeds whose failure was connectivity-only while the whole pass was
  /// offline — the failure proves nothing about the feed, so a stored error
  /// is neither written nor cleared.
  Set<String> unprovenUrls,

  /// Updated learned-redirect map (canonical subscription URL → URL the
  /// fetch actually resolved to) to persist as `feedRedirects`.
  Map<String, String> redirects,
});

/// Single-pass feed refresh engine: bounded-concurrency fetches, HTTP 304
/// handling, observed-history claims, bookmark merge, and validator update.
///
/// Pure orchestration — persistence, timers, and notification delivery stay
/// with the owning provider.
class FeedRefresher {
  final FeedService _feedService;
  final ObservedArticleStore _observedArticleStore;

  /// Max concurrent feed HTTP requests. Limits socket/memory pressure on
  /// devices with constrained network stacks.
  static const _fetchConcurrency = 5;

  FeedRefresher({
    required FeedService feedService,
    required ObservedArticleStore observedArticleStore,
  }) : _feedService = feedService,
       _observedArticleStore = observedArticleStore;

  Future<FeedRefreshResult> refresh({
    required List<FeedSubscription> subscriptions,
    required List<FeedItem> existingItems,
    required Map<String, dynamic> validators,
    required List<FeedItem> bookmarkedItems,
    required Map<String, String> redirects,
  }) async {
    // Snapshot current items per feed so a 304 — or a transient error — reuses
    // the feed's existing articles instead of dropping them this cycle.
    final existingByFeed = <String, List<FeedItem>>{};
    for (final it in existingItems) {
      (existingByFeed[it.feedUrl] ??= []).add(it);
    }

    // Rate-limit concurrent HTTP requests to avoid network/memory saturation.
    // With 30+ feeds, unbounded Future.wait exhausts connection pools and causes
    // TCP resets on constrained devices.
    final semaphore = AsyncSemaphore(_fetchConcurrency);
    final futures = subscriptions.map((sub) async {
      await semaphore.acquire();
      final v = validators[sub.url];
      // Fetch at the learned redirect URL when one exists — skips a hop.
      final fetchUrl = redirects[sub.url] ?? sub.url;
      try {
        final etag = v?['etag'] as String?;
        final lastModified = v?['lastModified'] as String?;
        var result = await _feedService.fetchFeed(
          fetchUrl,
          sub.category,
          etag: etag,
          lastModified: lastModified,
        );
        final hasTrustworthyCache = existingByFeed[sub.url]?.isNotEmpty == true;
        final usedValidator = etag != null || lastModified != null;
        var dropValidator = false;
        if (result.notModified && usedValidator && !hasTrustworthyCache) {
          // A 304 carries no body. Without local articles it is unusable, so
          // retry once unconditionally. Any failure is handled by the outer
          // catch and never starts another retry.
          result = await _feedService.fetchFeed(fetchUrl, sub.category);
          if (result.notModified) {
            // Server insists on 304 even without validators — drop our copy
            // so the next request is a plain GET instead of a forever-loop
            // of validator fetch + unconditional retry.
            dropValidator = true;
          }
        }
        return (
          url: sub.url,
          observationEpoch: sub.notificationEpoch,
          items: result.notModified
              ? (existingByFeed[sub.url] ?? const <FeedItem>[])
              // Items parsed at a learned redirect URL carry the resolved URL
              // as feedUrl — re-tag to canonical so cache/filter/prefetch
              // lookups keyed by sub.url keep matching.
              : fetchUrl == sub.url
              ? result.items
              : result.items.map((i) => i.copyWith(feedUrl: sub.url)).toList(),
          succeeded: true,
          fresh: !result.notModified,
          etag: result.etag,
          lastModified: result.lastModified,
          dropValidator: dropValidator,
          finalUrl: result.finalUrl,
          fetchUrl: fetchUrl,
          error: null as String?,
          connectivity: false,
        );
      } catch (e) {
        debugPrint('Error fetching feed ${sub.url}: $e');
        // Transient failure: keep the feed's existing items so one error doesn't
        // blank it out, and leave its validators untouched.
        return (
          url: sub.url,
          observationEpoch: sub.notificationEpoch,
          items: existingByFeed[sub.url] ?? const <FeedItem>[],
          succeeded: false,
          fresh: false,
          etag: null as String?,
          lastModified: null as String?,
          dropValidator: false,
          finalUrl: null as String?,
          fetchUrl: fetchUrl,
          error: e.toString(),
          connectivity:
              e is FeedFetchException &&
              e.kind == FeedFetchErrorKind.connectivity,
        );
      } finally {
        semaphore.release();
      }
    });

    final outcomes = await Future.wait(futures);

    // Observation is independent from delivery. A fresh 200 response may
    // initialize or advance history. A 304 may only refresh identities in an
    // already-initialized namespace; cached items cannot initialize one.
    // Failed feeds never touch their history.
    final claimedItems = <FeedItem>[];
    for (final outcome in outcomes) {
      if (!outcome.succeeded) continue;
      final claim = await _observedArticleStore.claimFeedBatch(
        feedUrl: outcome.url,
        observationEpoch: outcome.observationEpoch,
        items: outcome.items,
        allowInitialization: outcome.fresh,
      );
      claimedItems.addAll(claim.claimedItems);
    }

    // online: reached the network on at least one feed (200 or 304).
    // anyFreshBody: at least one feed returned a 200 body → content changed, so
    // it's worth re-sorting, persisting, notifying, and updating widgets.
    bool online = false;
    bool anyFreshBody = false;
    final List<FeedItem> freshItems = [];
    final newValidators = Map<String, dynamic>.from(validators);
    for (final o in outcomes) {
      freshItems.addAll(o.items);
      if (o.succeeded) online = true;
      if (o.fresh) {
        anyFreshBody = true;
        if (o.etag != null || o.lastModified != null) {
          newValidators[o.url] = {
            'etag': o.etag,
            'lastModified': o.lastModified,
          };
        } else {
          // Server offered no validators — force a full fetch next time.
          newValidators.remove(o.url);
        }
      } else if (o.dropValidator) {
        // Server answered 304 even without validators — drop ours so the
        // next request is unconditional instead of retry-looping.
        newValidators.remove(o.url);
      }
    }

    // Learned redirects: update on a differing final URL, and self-heal by
    // dropping a learned entry whose fetch failed (the target may be stale).
    final newRedirects = Map<String, String>.from(redirects);
    for (final o in outcomes) {
      if (o.finalUrl != null) {
        newRedirects[o.url] = o.finalUrl!;
      } else if (!o.succeeded && o.fetchUrl != o.url) {
        newRedirects.remove(o.url);
      }
    }

    final List<FeedItem> items;
    if (online) {
      // A fresh parse drops prefetched bodies — carry them over so offline
      // content survives refresh cycles (as read/bookmark flags do).
      FeedCachePolicy.carryOverPrefetchedText(
        existingItems: existingItems,
        freshItems: freshItems,
      );

      // Merge bookmarks into the list so they are always visible.
      // Use a Set for O(1) lookup — avoids O(bookmarks × items) scan.
      final freshIds = freshItems.map((i) => i.id).toSet();
      for (final saved in bookmarkedItems) {
        if (!freshIds.contains(saved.id)) {
          freshItems.add(saved);
          freshIds.add(saved.id);
        }
      }

      freshItems.sort((a, b) {
        if (a.pubDate == null && b.pubDate == null) return 0;
        if (a.pubDate == null) return 1;
        if (b.pubDate == null) return -1;
        return b.pubDate!.compareTo(a.pubDate!);
      });
      items = freshItems;
    } else {
      // Offline: keep existing items but still ensure bookmarks are present.
      final merged = List<FeedItem>.of(existingItems);
      final existingIds = merged.map((i) => i.id).toSet();
      for (final saved in bookmarkedItems) {
        if (!existingIds.contains(saved.id)) {
          merged.add(saved);
          existingIds.add(saved.id);
        }
      }
      debugPrint('FeedRefresher: all fetches failed — keeping cached items.');
      items = merged;
    }

    // Recorded feed errors: definitive failures (HTTP status, parse) always
    // count; connectivity failures only count when some other feed reached
    // the network — otherwise the device is offline and the feed is unproven.
    final feedErrors = <String, String>{};
    final unprovenUrls = <String>{};
    for (final o in outcomes) {
      if (o.succeeded || o.error == null) continue;
      if (o.connectivity && !online) {
        unprovenUrls.add(o.url);
      } else {
        feedErrors[o.url] = o.error!;
      }
    }

    return (
      items: items,
      claimedItems: claimedItems,
      online: online,
      anyFreshBody: anyFreshBody,
      validators: newValidators,
      feedErrors: feedErrors,
      unprovenUrls: unprovenUrls,
      redirects: newRedirects,
    );
  }
}
