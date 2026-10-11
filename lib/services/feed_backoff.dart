import 'dart:math' show Random;

import 'article_preparation_service.dart';
import 'feed_service.dart';

/// Rate-limit backoff shared by the foreground refresher and the
/// background sync isolate.
///
/// Two scopes:
///
/// * **Feed** — every rate-limit failure cools the individual feed.
/// * **Host** — a 429/503/Retry-After answers for the whole origin: when
///   `reddit.com/r/a/.rss` is limited, `reddit.com/r/b/.rss` is hit just
///   as hard. The host entry only earns cooldowns from rate-limit
///   signals; a feed-specific failure (404, parse) never penalizes its
///   siblings.
///
/// Without this a rate-limited feed is hit on every sync cycle, keeping
/// the limit permanently exhausted. Session state is in-memory; the
/// owning provider persists snapshots to Hive so a background isolate —
/// which has its own service instances — honors the same cooldowns.
class FeedBackoff {
  FeedBackoff({
    Map<String, DateTime>? retryAt,
    Map<String, DateTime>? hostRetryAt,
    Map<String, int>? attempts,
    Random? jitter,
  }) : _retryAt = retryAt ?? {},
       _hostRetryAt = hostRetryAt ?? {},
       _attempts = attempts ?? {},
       _jitter = jitter ?? Random();

  final Map<String, DateTime> _retryAt;
  final Map<String, DateTime> _hostRetryAt;
  final Map<String, int> _attempts;
  final Random _jitter;

  static String _authority(String url) => Uri.tryParse(url)?.authority ?? '';

  /// Whether [url] is inside a cooldown — its own or its host's. Callers
  /// must skip the fetch and keep the feed's cached items and last
  /// recorded error.
  bool isBackedOff(String url, DateTime now) {
    final until = _retryAt[url];
    if (until != null && until.isAfter(now)) return true;
    final hostUntil = _hostRetryAt[_authority(url)];
    return hostUntil != null && hostUntil.isAfter(now);
  }

  /// Records a fetch failure. Rate-limit signals (429, 503, or an explicit
  /// Retry-After) earn a backoff — on the feed AND its host. Server
  /// `Retry-After` is authoritative; otherwise a doubling local backoff
  /// with jitter applies. Other failures are not penalized — a single
  /// transient 500 should recover on the very next sync, not sit out a
  /// minute, and it must not cool the whole host down.
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
    final host = _authority(url);
    if (host.isNotEmpty) {
      final existing = _hostRetryAt[host];
      if (existing == null || existing.isBefore(until)) {
        _hostRetryAt[host] = until;
      }
    }
    return until;
  }

  /// Keys cleared by a success — timestamps remembered so a stale
  /// persisted snapshot can't resurrect a cooldown after merge-on-load.
  final Map<String, DateTime> _cleared = {};

  /// A successful fetch clears the feed's failure history — and its
  /// host's, since a 200 proves the origin accepts requests again.
  void recordSuccess(String url) {
    _attempts.remove(url);
    _retryAt.remove(url);
    _hostRetryAt.remove(_authority(url));
    final now = DateTime.now();
    _cleared[url] = now;
    _cleared[_authority(url)] = now;
  }

  /// JSON-encodable snapshot for persistence:
  /// `{"feeds": {url: ms}, "hosts": {authority: ms}}`.
  /// Attempt counters stay session-scoped — persisting them buys nothing:
  /// a restart already resets the sync rhythm.
  Map<String, dynamic> snapshot() {
    final now = DateTime.now();
    return {
      'feeds': {
        for (final e in _retryAt.entries)
          if (e.value.isAfter(now)) e.key: e.value.millisecondsSinceEpoch,
      },
      'hosts': {
        for (final e in _hostRetryAt.entries)
          if (e.value.isAfter(now)) e.key: e.value.millisecondsSinceEpoch,
      },
    };
  }

  /// Merges deadlines persisted by another isolate/session — the later
  /// deadline always wins, so a fresh snapshot never shortens a cooldown
  /// this isolate already knows about. Accepts both the v2
  /// `{feeds, hosts}` shape and the legacy flat `{url: ms}` map.
  void load(Map<String, dynamic> persisted) {
    final now = DateTime.now();
    Map<String, DateTime> targetFor(String key) =>
        key == 'hosts' ? _hostRetryAt : _retryAt;
    for (final section in persisted.entries) {
      final entries = section.value is Map
          ? (section.value as Map).entries
          : [section];
      for (final e in entries) {
        final ms = e.value is int ? e.value as int : int.tryParse('${e.value}');
        if (ms == null) continue;
        final until = DateTime.fromMillisecondsSinceEpoch(ms);
        if (!until.isAfter(now)) continue;
        final target = targetFor(section.key);
        final key = e.key.toString();
        final clearedAt = _cleared[key];
        // A success that postdates the persisted deadline already proved
        // the cooldown obsolete — don't resurrect it.
        if (clearedAt != null && !clearedAt.isBefore(until)) continue;
        final existing = target[key];
        if (existing == null || existing.isBefore(until)) {
          target[key] = until;
        }
      }
    }
  }
}
