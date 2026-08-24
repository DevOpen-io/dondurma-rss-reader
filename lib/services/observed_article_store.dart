import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/feed_item.dart';
import 'article_identity.dart';
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
  ObservedArticleStore.forBox(Box box)
    : this(persistence_factory.createObservedArticlePersistence(box));

  ObservedArticleStore(
    this._persistence, {
    this.retention = const Duration(days: 14),
  });

  static const int schemaVersion = 1;

  final ObservedArticlePersistence _persistence;
  final Duration retention;

  Future<ObservedClaimResult> claimFeedBatch({
    required String feedUrl,
    String observationEpoch = 'legacy-v1',
    required Iterable<FeedItem> items,
    bool allowInitialization = true,
    DateTime? observedAt,
  }) async {
    final now = (observedAt ?? DateTime.now()).toUtc();
    try {
      final exclusive = await _persistence.runExclusive(() async {
        final state = _decodeState(await _persistence.read());
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
