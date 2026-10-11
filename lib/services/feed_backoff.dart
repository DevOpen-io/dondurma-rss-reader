import 'dart:math' show Random;

import 'article_preparation_service.dart';
import 'feed_service.dart';

/// Per-feed rate-limit backoff shared by the foreground refresher and the
/// background sync isolate.
///
/// A feed answering 429/503 — or carrying a `Retry-After` — is not
/// refetched until its wait passes. Without this a rate-limited feed
/// (Reddit answers 429 aggressively) is hit on every sync cycle, keeping
/// the limit permanently exhausted. Session state is in-memory; the
/// owning provider persists snapshots to Hive so a background isolate —
/// which has its own service instances — honors the same cooldowns.
class FeedBackoff {
  FeedBackoff({
    Map<String, DateTime>? retryAt,
    Map<String, int>? attempts,
    Random? jitter,
  }) : _retryAt = retryAt ?? {},
       _attempts = attempts ?? {},
       _jitter = jitter ?? Random();

  final Map<String, DateTime> _retryAt;
  final Map<String, int> _attempts;
  final Random _jitter;

  /// Whether [url] is inside a cooldown — callers must skip the fetch and
  /// keep the feed's cached items and last recorded error.
  bool isBackedOff(String url, DateTime now) {
    final until = _retryAt[url];
    return until != null && until.isAfter(now);
  }

  /// Records a fetch failure. Rate-limit signals (429, 503, or an explicit
  /// Retry-After) earn a backoff: server `Retry-After` is authoritative,
  /// otherwise a doubling local backoff with jitter applies. Other
  /// failures are not penalized — a single transient 500 should recover
  /// on the very next sync, not sit out a minute.
  ///
  /// Returns the deadline when one was set, null otherwise.
  DateTime? recordFailure(String url, Object error, DateTime now) {
    final serverWait = error is FeedFetchException ? error.retryAfter : null;
    final status = error is FeedFetchException ? error.statusCode : null;
    final isConnectivity =
        error is FeedFetchException &&
        error.kind == FeedFetchErrorKind.connectivity;
    if (isConnectivity ||
        (status != 429 && status != 503 && serverWait == null)) {
      return null;
    }
    final next = (_attempts[url] ?? 0) + 1;
    _attempts[url] = next;
    final until = serverWait != null && serverWait.isAfter(now)
        ? serverWait
        : now.add(
            Duration(
              milliseconds:
                  (ArticlePreparationService.backoffFor(next).inMilliseconds *
                          (0.5 + _jitter.nextDouble()))
                      .round(),
            ),
          );
    _retryAt[url] = until;
    return until;
  }

  /// A successful fetch clears the feed's failure history.
  void recordSuccess(String url) {
    _attempts.remove(url);
    _retryAt.remove(url);
  }

  /// JSON-encodable `{url: millisSinceEpochUtc}` snapshot for persistence.
  /// Attempt counters stay session-scoped — persisting them buys nothing:
  /// a restart already resets the sync rhythm.
  Map<String, int> snapshot() => {
    for (final e in _retryAt.entries)
      if (e.value.isAfter(DateTime.now()))
        e.key: e.value.millisecondsSinceEpoch,
  };

  /// Loads deadlines persisted by another isolate/session. Entries already
  /// in the past are dropped on read.
  void load(Map<String, dynamic> persisted) {
    final now = DateTime.now();
    for (final e in persisted.entries) {
      final ms = e.value is int ? e.value as int : int.tryParse('${e.value}');
      if (ms == null) continue;
      final until = DateTime.fromMillisecondsSinceEpoch(ms);
      if (until.isAfter(now)) _retryAt[e.key] = until;
    }
  }
}
