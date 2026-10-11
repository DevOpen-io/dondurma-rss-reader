import 'dart:math' show Random;

import '../utils/host_key.dart';
import 'article_preparation_service.dart';
import 'feed_service.dart';

/// One cooldown record.
///
/// [since] is the event time at which the failure created or last
/// refreshed the record; [until] is the instant the cooldown expires.
/// They answer different questions: ordering a *clear event* against an
/// *expiry* conflates the two and is what let stale snapshots resurrect
/// superseded cooldowns — correctness requires comparing like with
/// like (created-vs-cleared).
///
/// [serverMandated] marks a cooldown whose deadline came from a
/// server-issued `Retry-After`. A sibling feed's success does not
/// disprove it — the server restricted the whole origin, so only the
/// deadline itself ends the restriction.
class _Cooldown {
  const _Cooldown(this.since, this.until, {this.serverMandated = false});

  final DateTime since;
  final DateTime until;
  final bool serverMandated;
}

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
/// Persistence contract (`snapshot`/`load`): each isolate owns its own
/// Hive slot — the foreground writes `feedBackoffUntil`, the background
/// writes `feedBackoffUntil.bg` — and every reader merges all slots.
/// There is no shared read-modify-write register, so no isolate can
/// overwrite another's snapshot; records carry a creation timestamp so
/// a clear event reliably suppresses superseded entries regardless of
/// how far in the future their expiry sits.
class FeedBackoff {
  FeedBackoff({Random? jitter, DateTime Function()? now})
    : _jitter = jitter ?? Random(),
      _now = now ?? DateTime.now;

  final Map<String, _Cooldown> _feeds = {};
  final Map<String, _Cooldown> _hosts = {};
  final Map<String, int> _attempts = {};
  final Random _jitter;
  final DateTime Function() _now;

  /// Keys cleared by a success — the *event time* of the clear, matched
  /// against a record's [ _Cooldown.since ], never its expiry. One entry
  /// per key (overwritten, not appended), so growth is bounded by the
  /// number of distinct feeds/hosts ever seen.
  final Map<String, DateTime> _cleared = {};

  static String _authority(String url) => hostKey(url);

  /// Whether [url] is inside a cooldown — its own or its host's. Callers
  /// must skip the fetch and keep the feed's cached items and last
  /// recorded error.
  bool isBackedOff(String url, DateTime now) {
    final feed = _feeds[url];
    if (feed != null && feed.until.isAfter(now)) return true;
    final host = _hosts[_authority(url)];
    return host != null && host.until.isAfter(now);
  }

  /// Whether [url] is inside a cooldown that carries a server-issued
  /// deadline (`Retry-After`). Explicit user retries may bypass local
  /// estimates but must still respect this.
  bool isMandatedBackedOff(String url, DateTime now) {
    final feed = _feeds[url];
    if (feed != null && feed.serverMandated && feed.until.isAfter(now)) {
      return true;
    }
    final host = _hosts[_authority(url)];
    return host != null && host.serverMandated && host.until.isAfter(now);
  }

  /// Records a fetch failure. Rate-limit signals (429, 503, or an explicit
  /// Retry-After) earn a backoff — on the feed AND its host. Server
  /// `Retry-After` is authoritative for the deadline AND marks the record
  /// server-mandated; otherwise a doubling local backoff with jitter
  /// applies. Other failures are not penalized — a single transient 500
  /// should recover on the very next sync, not sit out a minute, and it
  /// must not cool the whole host down.
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
    final mandated = serverWait != null;
    final until = mandated && serverWait.isAfter(now)
        ? serverWait
        : now.add(
            Duration(
              milliseconds:
                  (ArticlePreparationService.backoffFor(next).inMilliseconds *
                          (0.5 + _jitter.nextDouble()))
                      .round(),
            ),
          );
    _upsert(_feeds, url, now, until, mandated);
    final host = _authority(url);
    if (host.isNotEmpty) _upsert(_hosts, host, now, until, mandated);
    return until;
  }

  /// A successful fetch clears the feed's own failure history — the
  /// server just answered it. The host cooldown is NEVER touched: a
  /// sibling's 200 — even one whose request started before the 429 —
  /// cannot disprove an origin-wide restriction, whether it was
  /// server-mandated or a local estimate. Host cooldowns end at expiry.
  void recordSuccess(String url, {DateTime? at}) {
    final now = at ?? _now();
    _attempts.remove(url);
    _feeds.remove(url);
    _cleared[url] = now;
  }

  /// Merges [until] into [key]'s record. `since` is always the event
  /// time of this call — a record represents the newest failure, so a
  /// clear that predates it correctly loses, and a clear that postdates
  /// it correctly wins. A deadline in place is never shortened; the
  /// mandated flag is sticky while the entry is alive so a server
  /// restriction that got extended by a local estimate can't be cut by
  /// a sibling success either.
  void _upsert(
    Map<String, _Cooldown> map,
    String key,
    DateTime now,
    DateTime until,
    bool mandated,
  ) {
    final existing = map[key];
    if (existing != null && existing.until.isAfter(now)) {
      map[key] = _Cooldown(
        now,
        existing.until.isAfter(until) ? existing.until : until,
        serverMandated: existing.serverMandated || mandated,
      );
    } else {
      map[key] = _Cooldown(now, until, serverMandated: mandated);
    }
  }

  /// JSON-encodable snapshot for persistence:
  /// `{feeds: {url: {u, s, m}}, hosts: {...}, cleared: {key: ms}}` where
  /// `u`/`s` are epoch-ms for until/since and `m` the mandated flag.
  /// Expired records are dropped here (they cannot block anything), and
  /// attempt counters stay session-scoped — persisting them buys nothing.
  Map<String, dynamic> snapshot() {
    final now = _now();
    Map<String, dynamic> encode(Map<String, _Cooldown> map) {
      final out = <String, dynamic>{};
      map.removeWhere((key, cd) {
        if (cd.until.isAfter(now)) {
          out[key] = {
            'u': cd.until.millisecondsSinceEpoch,
            's': cd.since.millisecondsSinceEpoch,
            if (cd.serverMandated) 'm': true,
          };
          return false;
        }
        return true;
      });
      return out;
    }

    return {
      'feeds': encode(_feeds),
      'hosts': encode(_hosts),
      'cleared': {
        for (final e in _cleared.entries) e.key: e.value.millisecondsSinceEpoch,
      },
    };
  }

  /// Merges a persisted snapshot — another isolate's slot or a restart's
  /// stored state. Ordering rules, in order:
  ///
  /// 1. `cleared` markers merge by *latest event time* — a clear is an
  ///    event, so the newest one wins.
  /// 2. A record whose [ _Cooldown.since ] is not after the merged clear
  ///    time is skipped: whatever created it was already superseded.
  ///    This comparison is event-vs-event, never event-vs-expiry.
  /// 3. Records merge by *latest expiry* — a snapshot never shortens a
  ///    deadline this isolate already holds.
  /// 4. Finally the merged clears are applied to in-memory records, so a
  ///    clear learned from another isolate drops superseded local state
  ///    too — the propagation is symmetric.
  ///
  /// Legacy shapes are still accepted: the v2 `{feeds: {url: ms}}` map
  /// and the flat `{url: ms}` map read as records with `since = epoch`
  /// and `serverMandated = false` — without a creation time they yield
  /// to any recorded clear, which is the safe interpretation for state
  /// written before this versioning existed.
  void load(Map<String, dynamic> persisted) {
    final now = _now();

    final clearedSection = persisted['cleared'];
    if (clearedSection is Map) {
      for (final e in clearedSection.entries) {
        final ms = e.value is int ? e.value as int : int.tryParse('${e.value}');
        if (ms == null) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(ms);
        final existing = _cleared[e.key.toString()];
        if (existing == null || existing.isBefore(at)) {
          _cleared[e.key.toString()] = at;
        }
      }
    }

    for (final section in persisted.entries) {
      if (section.key == 'cleared') continue;
      final target = section.key == 'hosts' ? _hosts : _feeds;
      final entries = section.value is Map
          ? (section.value as Map).entries
          : [section];
      for (final e in entries) {
        if (e.value is Map) {
          final rec = e.value as Map;
          final until = _ms(rec['u']);
          if (until == null || !until.isAfter(now)) continue;
          final since = _ms(rec['s']) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final clearedAt = _cleared[e.key.toString()];
          final mandated = rec['m'] == true;
          // A success suppresses superseded records — except host-level
          // server mandates, which a sibling 200 cannot disprove. Feed
          // keys always yield: the feed's own success clears it.
          if (clearedAt != null &&
              !since.isAfter(clearedAt) &&
              !(section.key == 'hosts' && mandated)) {
            continue;
          }
          _mergeIn(target, e.key.toString(), since, until, mandated);
        } else {
          final until = _ms(e.value);
          if (until == null || !until.isAfter(now)) continue;
          final clearedAt = _cleared[e.key.toString()];
          // No creation time on record → a recorded clear supersedes it.
          if (clearedAt != null) continue;
          _mergeIn(
            target,
            e.key.toString(),
            DateTime.fromMillisecondsSinceEpoch(0),
            until,
            false,
          );
        }
      }
    }

    // Propagate clears to in-memory records: a clear learned from another
    // isolate's slot retires the superseded local cooldowns as well.
    // Host-level server mandates are exempt — same rule as on merge.
    _feeds.removeWhere((key, cd) {
      final clearedAt = _cleared[key];
      return clearedAt != null && !cd.since.isAfter(clearedAt);
    });
    _hosts.removeWhere((key, cd) {
      final clearedAt = _cleared[key];
      return clearedAt != null &&
          !cd.since.isAfter(clearedAt) &&
          !cd.serverMandated;
    });
  }

  void _mergeIn(
    Map<String, _Cooldown> map,
    String key,
    DateTime since,
    DateTime until,
    bool mandated,
  ) {
    final existing = map[key];
    if (existing == null) {
      map[key] = _Cooldown(since, until, serverMandated: mandated);
    } else {
      map[key] = _Cooldown(
        existing.since.isAfter(since) ? existing.since : since,
        existing.until.isAfter(until) ? existing.until : until,
        serverMandated: existing.serverMandated || mandated,
      );
    }
  }

  static DateTime? _ms(Object? v) {
    final ms = v is int ? v : int.tryParse('$v');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
