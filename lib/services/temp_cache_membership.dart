import '../models/feed_item.dart';
import 'article_identity.dart';
import 'article_preparation_service.dart';
import 'article_record_store.dart';
import 'feed_list_filter.dart';

/// Temporary-cache membership (#37): the transient offline collection is the
/// globally newest ≤limit unique, non-bookmarked, keyword-clean articles
/// from active subscriptions — no per-feed fair share, and readiness never
/// protects an older item against a newer one.
///
/// Membership lives on durable records as the `'tempCache'` owner. This
/// class recomputes the owner set: selected candidates are registered
/// durable-first (pending manifest before any byte), dropped members lose
/// only this owner — bookmark ownership and record contents are untouched.
/// Physical cleanup of what the owner released is the S5 lifecycle's job.
///
/// Candidates are the caller's items plus existing `tempCache` records that
/// vanished from still-subscribed feeds — an article leaves when newer
/// candidates push it past the limit or its feed is unsubscribed, never
/// merely because a feed stopped sending it.
/// Persisted reset epoch in the `'feeds'` box: bumped on every cache wipe
/// so a background-isolate write racing the reset can fence itself — an
/// in-memory generation counter can't cross isolates.
const String tempCacheEpochKey = 'cacheEpoch';

class TempCacheMembership {
  TempCacheMembership({
    required ArticleRecordStore records,
    required ArticlePreparationService preparation,
  }) : _records = records,
       _preparation = preparation;

  static const String owner = 'tempCache';

  final ArticleRecordStore _records;
  final ArticlePreparationService _preparation;

  /// Recomputes temp membership and returns the selected article ids.
  ///
  /// [items] is the raw candidate list (view filters never apply here;
  /// permanent keyword exclusions do). [fullTextFor] resolves each feed's
  /// effective extraction preference (`fullTextEnabled ?? autoFullText`).
  /// [epoch] is the record store's lifecycle epoch captured by the caller
  /// before this pass began — every mutation carries it, so a factory reset
  /// landing mid-reconcile rejects the rest of the writes instead of
  /// resurrecting members the reset just wiped (#40).
  Future<Set<String>> reconcile({
    required List<FeedItem> items,
    required Set<String> bookmarkedIds,
    required Iterable<String> subscribedFeedUrls,
    required List<String> globalKeywords,
    required Map<String, List<String>> feedKeywordsMap,
    required int limit,
    required bool Function(String feedUrl) fullTextFor,
    DateTime? now,
    int? epoch,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final subscribed = subscribedFeedUrls.toSet();
    final excluder = KeywordExcluder(
      globalKeywords: globalKeywords,
      feedKeywordsMap: feedKeywordsMap,
    );
    // The record store keys everything on canonical ids — comparisons must
    // use the same normalization or a non-canonical guid misses every pass.
    String canon(String id) => ArticleIdentity.normalizeItemId(id) ?? id;
    final bookmarkedCanon = bookmarkedIds.map(canon).toSet();
    final firstSeen = await _records.allFirstSeen();
    final records = await _records.listRecords();

    // 1. Live candidates: subscribed feeds, keyword-clean, not bookmarked.
    final candidates = <String, _Candidate>{};
    final presentIds = <String>{};
    for (final item in items) {
      final id = canon(item.id);
      presentIds.add(id);
      if (!subscribed.contains(item.feedUrl)) continue;
      if (bookmarkedCanon.contains(id)) continue;
      if (excluder.excludes(
        title: item.title,
        description: item.description,
        feedUrl: item.feedUrl,
      )) {
        continue;
      }
      // Dateless articles rank by their stable first-observation time —
      // stamped once and recorded so refetches/restarts never reshuffle.
      var sortTime = item.pubDate?.toUtc();
      if (sortTime == null) {
        sortTime = firstSeen[id];
        if (sortTime == null) {
          sortTime = at;
          firstSeen[id] = at;
          await _records.recordFirstSeen(item.id, at, expectedEpoch: epoch);
        }
      }
      candidates[id] = _Candidate(
        id: id,
        link: item.link,
        feedUrl: item.feedUrl,
        sortTime: sortTime,
        item: item,
      );
    }

    // 2. Already-owned records that vanished from feeds stay candidates;
    // they leave only when the global newest-N pushes them out. A member
    // whose feed was unsubscribed loses the slot immediately — membership
    // is scoped to active subscriptions (#37). A member still present in
    // the live list was already judged by step 1 — never re-admit it here.
    final ownedIds = <String>{};
    for (final record in records) {
      if (record.tombstoned || !record.owners.contains(owner)) continue;
      ownedIds.add(record.id);
      if (!subscribed.contains(record.feedUrl)) continue;
      if (presentIds.contains(record.id)) continue;
      if (bookmarkedCanon.contains(record.id)) continue;
      if (excluder.excludes(
        title: record.title ?? '',
        description: '',
        feedUrl: record.feedUrl,
      )) {
        continue;
      }
      candidates[record.id] = _Candidate(
        id: record.id,
        link: record.link.isEmpty ? null : record.link,
        feedUrl: record.feedUrl,
        sortTime:
            record.publishedAt?.toUtc() ??
            firstSeen[record.id] ??
            record.savedAt?.toUtc() ??
            at,
      );
    }

    // 3. Global newest-N: effective time desc, id asc — deterministic, so
    //    normal refreshes never reshuffle equal-ranked membership.
    final ranked = candidates.values.toList()
      ..sort((a, b) {
        final t = b.sortTime.compareTo(a.sortTime);
        return t != 0 ? t : a.id.compareTo(b.id);
      });
    final selectedIds = <String>{};
    final selectedKeys = <String>{};
    for (final c in ranked) {
      if (selectedIds.length >= limit) break;
      final key = dedupeKey(link: c.link, id: c.id);
      if (!selectedKeys.add(key)) continue;
      selectedIds.add(c.id);
    }

    // 4. Durable-first registration for selected live items. A failed
    //    registration still lands in the snapshot — the next reconcile
    //    retries it (self-healing), so per-item results aren't inspected.
    for (final c in ranked) {
      final item = c.item;
      if (item == null || !selectedIds.contains(c.id)) continue;
      await _preparation.registerArticle(
        item,
        const {owner},
        fullText: fullTextFor(item.feedUrl),
        expectedEpoch: epoch,
      );
    }

    // 5. Members pushed out lose only the tempCache owner — other owners
    //    (e.g. bookmark) and all content are preserved for S5 to evaluate.
    //    A failed strip likewise self-heals on the next pass. Strips ride
    //    the same register queue as step 4 so queued registrations can
    //    never re-add an owner this step just removed.
    for (final id in ownedIds.difference(selectedIds)) {
      await _preparation.mutateRecord(id, expectedEpoch: epoch, (current) {
        if (current == null || !current.owners.contains(owner)) {
          return current;
        }
        final owners = {...current.owners}..remove(owner);
        return owners.length == current.owners.length
            ? current
            : current.copyWith(owners: owners);
      });
    }

    return selectedIds;
  }
}

class _Candidate {
  _Candidate({
    required this.id,
    required this.link,
    required this.feedUrl,
    required this.sortTime,
    this.item,
  });

  final String id;
  final String? link;
  final String feedUrl;
  final DateTime sortTime;
  final FeedItem? item;
}
