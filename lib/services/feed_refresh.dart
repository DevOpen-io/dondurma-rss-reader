import 'package:flutter/foundation.dart' show debugPrint;

import '../models/feed_item.dart';
import '../models/feed_subscription.dart';
import '../utils/async_semaphore.dart';
import '../utils/host_pacer.dart';
import 'feed_backoff.dart';
import 'feed_schedule.dart';
import 'feed_cache_policy.dart';
import 'feed_service.dart';
import 'lifecycle_gate.dart';
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

/// Per-feed progress snapshot emitted as each subscription reaches a
/// terminal outcome during [FeedRefresher.refresh].
typedef FeedProgressCallback =
    void Function({
      required int total,
      required int completed,
      required int succeeded,
      required int failed,
      required int skipped,
      required int inFlight,
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
    FeedBackoff? backoff,
    FeedSchedule? schedule,
    Duration hostGap = const Duration(milliseconds: 500),
    HostPacer? hostPacer,
  }) : _feedService = feedService,
       _observedArticleStore = observedArticleStore,
       backoff = backoff ?? FeedBackoff(),
       schedule = schedule ?? FeedSchedule(),
       _hostPacer = hostPacer ?? HostPacer(minGap: hostGap);

  /// Shared rate-limit policy — the provider preloads persisted deadlines
  /// so cooldowns survive process/isolate boundaries.
  final FeedBackoff backoff;

  /// Last fetch per feed, for per-feed refresh intervals; the provider
  /// preloads and persists it like [backoff].
  final FeedSchedule schedule;

  /// Several subscriptions on one host (e.g. multiple subreddits) must
  /// not fan out under the global concurrency cap — same-host fetches
  /// serialize with a small gap. The provider injects the pacer it
  /// shares with the extraction/preparation pipeline so all same-host
  /// traffic coordinates through one schedule.
  final HostPacer _hostPacer;

  /// Per-feed progress snapshot emitted as each subscription reaches a
  /// terminal outcome. Invoked from async closures — always on the calling
  /// isolate's event loop, so plain counters stay consistent.

  Future<FeedRefreshResult> refresh({
    required List<FeedSubscription> subscriptions,
    required List<FeedItem> existingItems,
    required Map<String, dynamic> validators,
    required List<FeedItem> bookmarkedItems,
    required Map<String, String> redirects,
    FeedProgressCallback? onProgress,
    void Function(String feedUrl, List<FeedItem> items)? onFreshFeed,
    bool Function(String feedUrl, String observationEpoch)? canObserve,
    LifecycleTicket? ticket,
    // Automatic passes leave a feed alone until its own interval is up; a
    // user's refresh fetches everything.
    bool honorIntervals = false,
  }) async {
    // Snapshot current items per feed so a 304 — or a transient error — reuses
    // the feed's existing articles instead of dropping them this cycle.
    final existingByFeed = <String, List<FeedItem>>{};
    for (final it in existingItems) {
      (existingByFeed[it.feedUrl] ??= []).add(it);
    }

    // Live counters for incremental progress reporting. The callback is
    // invoked synchronously as each feed settles so the UI can show real
    // per-feed advancement instead of an ambiguous spinning boolean.
    var completed = 0;
    var succeeded = 0;
    var failed = 0;
    var skipped = 0;
    var inFlight = 0;
    void emit() {
      if (onProgress == null) return;
      onProgress(
        total: subscriptions.length,
        completed: completed,
        succeeded: succeeded,
        failed: failed,
        skipped: skipped,
        inFlight: inFlight,
      );
    }

    // Rate-limit concurrent HTTP requests to avoid network/memory saturation.
    // With 30+ feeds, unbounded Future.wait exhausts connection pools and causes
    // TCP resets on constrained devices.
    final semaphore = AsyncSemaphore(_fetchConcurrency);
    final futures = subscriptions.map((sub) async {
      // A backed-off feed — or one whose own interval is not up — keeps its
      // cached items and its last error without touching the network, the
      // same treatment as an unproven failure.
      if (backoff.isBackedOff(sub.url, DateTime.now()) ||
          (honorIntervals && !schedule.isDue(sub, DateTime.now()))) {
        skipped++;
        completed++;
        emit();
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
          fetchUrl: sub.url,
          error: null as String?,
          connectivity: false,
          skipped: true,
        );
      }
      await semaphore.acquire();
      inFlight++;
      emit();
      final v = validators[sub.url];
      // Fetch at the learned redirect URL when one exists — skips a hop.
      final fetchUrl = redirects[sub.url] ?? sub.url;
      await _hostPacer.pace(fetchUrl);
      try {
        // Recheck after the queue wait: a same-host sibling may have
        // learned a 429 while this request waited its turn — a spacing
        // gap alone does not mean the previous request finished.
        if (backoff.isBackedOff(sub.url, DateTime.now())) {
          skipped++;
          completed++;
          inFlight--;
          emit();
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
            error: null as String?,
            connectivity: false,
            skipped: true,
          );
        }
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
        final canonicalItems = result.notModified
            ? (existingByFeed[sub.url] ?? const <FeedItem>[])
            : fetchUrl == sub.url
            ? result.items
            : result.items.map((i) => i.copyWith(feedUrl: sub.url)).toList();
        if (!result.notModified) onFreshFeed?.call(sub.url, canonicalItems);
        backoff.recordSuccess(sub.url);
        schedule.recordFetch(sub.url, DateTime.now());
        succeeded++;
        completed++;
        inFlight--;
        emit();
        return (
          url: sub.url,
          observationEpoch: sub.notificationEpoch,
          // Learned redirects must still use the subscription's identity.
          items: canonicalItems,
          succeeded: true,
          fresh: !result.notModified,
          etag: result.etag,
          lastModified: result.lastModified,
          dropValidator: dropValidator,
          finalUrl: result.finalUrl,
          fetchUrl: fetchUrl,
          error: null as String?,
          connectivity: false,
          skipped: false,
        );
      } catch (e) {
        debugPrint('Error fetching feed ${sub.url}: $e');
        // Rate-limit signals earn a cooldown; a plain transient failure
        // recovers on the next natural sync (see FeedBackoff for the rule).
        backoff.recordFailure(sub.url, e, DateTime.now());
        failed++;
        completed++;
        inFlight--;
        emit();
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
          skipped: false,
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
        claimCheck: canObserve == null
            ? null
            : () => canObserve(outcome.url, outcome.observationEpoch),
        ticket: ticket,
      );
      claimedItems.addAll(claim.claimedItems);
    }

    // online: reached the network on at least one feed (200 or 304).
    // anyFreshBody: at least one feed returned a 200 body → content changed, so
    // it's worth re-sorting, persisting, notifying, and updating widgets.
    bool online = false;
    bool anyFreshBody = false;
    final newValidators = Map<String, dynamic>.from(validators);
    for (final o in outcomes) {
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

    final items = FeedCachePolicy.mergeVisibleFeeds(
      existingItems: existingItems,
      freshItemsByFeed: {
        for (final o in outcomes)
          if (o.fresh) o.url: o.items,
      },
      subscribedFeedUrls: subscriptions.map((s) => s.url),
      bookmarkedItems: bookmarkedItems,
      now: DateTime.now(),
    );

    // Recorded feed errors: definitive failures (HTTP status, parse) always
    // count; connectivity failures only count when some other feed reached
    // the network — otherwise the device is offline and the feed is unproven.
    final feedErrors = <String, String>{};
    final unprovenUrls = <String>{};
    for (final o in outcomes) {
      if (o.skipped) {
        // Backed off before the network — the stored verdict stays as-is.
        unprovenUrls.add(o.url);
        continue;
      }
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
