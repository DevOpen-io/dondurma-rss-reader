import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/feed_item.dart';
import 'article_identity.dart';
import 'lifecycle_gate.dart';
import 'observed_article_persistence.dart';
import 'observed_article_persistence_stub.dart'
    if (dart.library.io) 'observed_article_persistence_io.dart'
    as persistence_factory;

class ObservedClaimResult {
  const ObservedClaimResult({
    required this.claimedItems,
    required this.initializedFeed,
    required this.lockTimedOut,
  });

  const ObservedClaimResult.timeout()
    : claimedItems = const [],
      initializedFeed = false,
      lockTimedOut = true;

  final List<FeedItem> claimedItems;
  final bool initializedFeed;
  final bool lockTimedOut;
}

class ObservedArticleStore {
  ObservedArticleStore.forBox(Box box, {LifecycleGate? gate})
    : this(
        persistence_factory.createObservedArticlePersistence(box),
        gate: gate,
      );

  ObservedArticleStore(
    this._persistence, {
    this.retention = const Duration(days: 14),
    LifecycleGate? gate,
  }) : _gate = gate ?? LifecycleGate.current;

  static const int schemaVersion = 1;

  /// Max articles one batch can claim as newly-observed per feed — bounds
  /// the post-gap notification burst. Daily churn never approaches this.
  static const int maxClaimsPerBatch = 10;

  static int _newestFirst(FeedItem a, FeedItem b) {
    if (a.pubDate == null && b.pubDate == null) return 0;
    if (a.pubDate == null) return 1;
    if (b.pubDate == null) return -1;
    return b.pubDate!.compareTo(a.pubDate!);
  }

  final ObservedArticlePersistence _persistence;
  final Duration retention;
  final LifecycleGate? _gate;

  static const _rejected = ObservedClaimResult(
    claimedItems: [],
    initializedFeed: false,
    lockTimedOut: false,
  );

  /// [ticket] is the lifecycle ticket captured when the caller's work began
  /// (before HTTP). With a gate, the claim — including namespace
  /// initialization — publishes only while that era is current.
  Future<ObservedClaimResult> claimFeedBatch({
    required String feedUrl,
    String observationEpoch = 'legacy-v1',
    required Iterable<FeedItem> items,
    bool allowInitialization = true,
    DateTime? observedAt,
    bool Function()? claimCheck,
    LifecycleTicket? ticket,
  }) async {
    Future<ObservedClaimResult> claim() => _claimFeedBatch(
      feedUrl: feedUrl,
      observationEpoch: observationEpoch,
      items: items,
      allowInitialization: allowInitialization,
      observedAt: observedAt,
      claimCheck: claimCheck,
    );
    final gate = _gate;
    if (gate == null) return claim();
    // No ticket means no proof of era: fail closed, never initialize.
    if (ticket == null) return _rejected;
    try {
      return await gate.withPublication(ticket, claim);
    } on StaleLifecycleTicket {
      return _rejected;
    } on LifecycleResetPending {
      return _rejected;
    } on TimeoutException {
      return const ObservedClaimResult.timeout();
    }
  }

  Future<ObservedClaimResult> _claimFeedBatch({
    required String feedUrl,
    required String observationEpoch,
    required Iterable<FeedItem> items,
    required bool allowInitialization,
    DateTime? observedAt,
    bool Function()? claimCheck,
  }) async {
    final now = (observedAt ?? DateTime.now()).toUtc();
    try {
      final exclusive = await _persistence.runExclusive(() async {
        final state = _decodeState(await _persistence.read());
        // Recheck inside the lock, after disk IO: a reset/unsubscribe may
        // have invalidated the caller while it waited for another writer.
        if (claimCheck != null && !claimCheck()) return _rejected;
        _prune(state, now);

        final feedKey =
            '${ArticleIdentity.normalizeFeedUrl(feedUrl)}\u0000$observationEpoch';
        final feeds = state['feeds'] as Map<String, dynamic>;
        final existingFeed = feeds[feedKey];
        final initialized =
            existingFeed is Map && existingFeed['initialized'] == true;
        if (!initialized && !allowInitialization) {
          return const ObservedClaimResult(
            claimedItems: [],
            initializedFeed: false,
            lockTimedOut: false,
          );
        }
        final feedState = existingFeed is Map
            ? Map<String, dynamic>.from(existingFeed)
            : <String, dynamic>{};
        final rawArticles = feedState['articles'];
        final articles = rawArticles is Map
            ? rawArticles.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
            : <String, String>{};

        final uniqueItems = <String, FeedItem>{};
        for (final item in items) {
          final identity = ArticleIdentity.normalizeItemId(item.id);
          if (identity != null) uniqueItems.putIfAbsent(identity, () => item);
        }

        final claimed = <FeedItem>[];
        final timestamp = now.toIso8601String();
        for (final entry in uniqueItems.entries) {
          if (articles.containsKey(entry.key)) {
            // Refresh last-observed time while an article remains in the feed.
            articles[entry.key] = timestamp;
          } else if (allowInitialization) {
            if (initialized) claimed.add(entry.value);
            articles[entry.key] = timestamp;
          }
        }

        // Cap claims per batch: after a >retention gap the prune empties
        // `articles` while `initialized` stays true, so a refilled feed would
        // otherwise claim its entire backlog as "new" in one pass — a
        // notification flood. Observation is still recorded for every item
        // above, so the un-claimed remainder won't re-claim next pass.
        if (claimed.length > maxClaimsPerBatch) {
          claimed.sort(_newestFirst);
          claimed.length = maxClaimsPerBatch;
        }

        feeds[feedKey] = {'initialized': true, 'articles': articles};
        await _persistence.write(jsonEncode(state));
        return ObservedClaimResult(
          claimedItems: initialized ? claimed : const [],
          initializedFeed: !initialized,
          lockTimedOut: false,
        );
      });
      return exclusive.acquired
          ? exclusive.value!
          : const ObservedClaimResult.timeout();
    } catch (_) {
      // Corrupt/unwritable state fails closed: never deliver an unclaimed item.
      return const ObservedClaimResult.timeout();
    }
  }

  /// Erases all observation history — the factory-reset boundary (#40):
  /// wiped articles must never re-observe as if claimed before.
  /// Returns false when the locked write could not complete.
  Future<bool> wipeAll() async {
    try {
      final result = await _persistence.runExclusive(() async {
        await _persistence.write(
          jsonEncode({'schema': schemaVersion, 'feeds': <String, dynamic>{}}),
        );
        return true;
      });
      return result.acquired;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _decodeState(String? raw) {
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['schema'] == schemaVersion) {
          final feeds = decoded['feeds'];
          return {
            'schema': schemaVersion,
            'feeds': feeds is Map
                ? feeds.map((key, value) => MapEntry(key.toString(), value))
                : <String, dynamic>{},
          };
        }
      } catch (_) {}
    }
    return {'schema': schemaVersion, 'feeds': <String, dynamic>{}};
  }

  void _prune(Map<String, dynamic> state, DateTime now) {
    final cutoff = now.subtract(retention);
    final feeds = state['feeds'] as Map<String, dynamic>;
    for (final feedEntry in feeds.entries) {
      final rawFeed = feedEntry.value;
      if (rawFeed is! Map) continue;
      final rawArticles = rawFeed['articles'];
      if (rawArticles is! Map) continue;
      rawArticles.removeWhere((_, value) {
        final observed = DateTime.tryParse(value.toString())?.toUtc();
        return observed == null || observed.isBefore(cutoff);
      });
    }
  }
}
