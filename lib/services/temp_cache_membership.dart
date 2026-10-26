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

  /// Recomputes temp membership and returns the selected source instances.
  ///
  /// [items] is the raw candidate list (view filters never apply here;
  /// permanent keyword exclusions do). [fullTextFor] resolves each feed's
  /// effective extraction preference (`fullTextEnabled ?? autoFullText`).
  /// [epoch] is the record store's lifecycle epoch captured by the caller
  /// before this pass began — every mutation carries it, so a factory reset
  /// landing mid-reconcile rejects the rest of the writes instead of
  /// resurrecting members the reset just wiped (#40).
  /// [isBookmarked] is the caller's bookmark verdict per instance —
  /// bookmarked articles never consume a temp slot.
  Future<Set<ArticleRef>> reconcile({
    required List<FeedItem> items,
    required bool Function(ArticleRef ref) isBookmarked,
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
    // The record store keys everything on source instances ([ArticleRef],
    // canonical ids) — two feeds sharing a GUID are two candidates.
    final firstSeen = await _records.allFirstSeen();
    final records = await _records.listRecords();

    // 1. Live candidates: subscribed feeds, keyword-clean, not bookmarked.
    final candidates = <ArticleRef, _Candidate>{};
    final presentRefs = <ArticleRef>{};
    for (final item in items) {
      final ref = ArticleRef.of(item);
      presentRefs.add(ref);
      if (!subscribed.contains(item.feedUrl)) continue;
      if (isBookmarked(ref)) continue;
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
        sortTime = firstSeen[ref];
        if (sortTime == null) {
          sortTime = at;
          firstSeen[ref] = at;
          await _records.recordFirstSeen(ref, at, expectedEpoch: epoch);
        }
      }
      candidates[ref] = _Candidate(
        ref: ref,
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
    final ownedRefs = <ArticleRef>{};
    for (final record in records) {
      if (record.tombstoned || !record.owners.contains(owner)) continue;
      final ref = ArticleRef(record.feedUrl, record.id);
      ownedRefs.add(ref);
      if (!subscribed.contains(record.feedUrl)) continue;
      if (presentRefs.contains(ref)) continue;
      if (isBookmarked(ref)) continue;
      if (excluder.excludes(
        title: record.title ?? '',
        description: '',
        feedUrl: record.feedUrl,
      )) {
        continue;
      }
      candidates[ref] = _Candidate(
        ref: ref,
        link: record.link.isEmpty ? null : record.link,
        feedUrl: record.feedUrl,
        sortTime:
            record.publishedAt?.toUtc() ??
            firstSeen[ref] ??
            record.savedAt?.toUtc() ??
            at,
      );
    }

    // 3. Global newest-N: effective time desc, instance key asc —
    //    deterministic, so normal refreshes never reshuffle equal-ranked
    //    membership.
    final ranked = candidates.values.toList()
      ..sort((a, b) {
        final t = b.sortTime.compareTo(a.sortTime);
        return t != 0 ? t : a.ref.key.compareTo(b.ref.key);
      });
    final selected = <ArticleRef>{};
    final selectedKeys = <String>{};
    for (final c in ranked) {
      if (selected.length >= limit) break;
      // Without a usable link only the same instance is a duplicate.
      final key = dedupeKey(link: c.link, id: c.ref.key);
      if (!selectedKeys.add(key)) continue;
      selected.add(c.ref);
    }

    // 4. Durable-first registration for selected live items. A failed
    //    registration still lands in the snapshot — the next reconcile
    //    retries it (self-healing), so per-item results aren't inspected.
    for (final c in ranked) {
      final item = c.item;
      if (item == null || !selected.contains(c.ref)) continue;
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
    for (final ref in ownedRefs.difference(selected)) {
      await _preparation.mutateRecord(ref, expectedEpoch: epoch, (current) {
        if (current == null || !current.owners.contains(owner)) {
          return current;
        }
        final owners = {...current.owners}..remove(owner);
        return owners.length == current.owners.length
            ? current
            : current.copyWith(owners: owners);
      });
    }

    return selected;
  }
}

class _Candidate {
  _Candidate({
    required this.ref,
    required this.link,
    required this.feedUrl,
    required this.sortTime,
    this.item,
  });

  final ArticleRef ref;
  final String? link;
  final String feedUrl;
  final DateTime sortTime;
  final FeedItem? item;
}
