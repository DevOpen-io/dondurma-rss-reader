import 'dart:async';

import 'article_identity.dart';
import 'article_media_store.dart';
import 'article_record_store.dart';
import 'lifecycle_gate.dart';

/// Outcome of one [ArticleCleanupService.sweep] pass. [failed] means the
/// pass could not prove the full lifecycle ran — the store was unreadable,
/// a tombstone write failed, or deletions hit errors — so callers must not
/// report reclaimed space as if everything succeeded.
class CleanupResult {
  const CleanupResult({
    required this.tombstoned,
    required this.deletedFiles,
    required this.prunedSeen,
    required this.failed,
  });

  final int tombstoned;
  final int deletedFiles;
  final int prunedSeen;
  final bool failed;
}

/// Lifecycle cleanup for durable article storage (#40).
///
/// One [sweep] pass runs the ownership lifecycle end to end:
///
/// 1. **Logical removal** — a live record with no owners is tombstoned, not
///    deleted: the tombstone keeps fencing stale writes at its generation,
///    and its content fields (body, media manifest, owners) drop away.
/// 2. **Physical release** — files no remaining record manifest references
///    are deleted, but only ones older than [_orphanGrace]: a file renamed
///    into place moments ago may be racing its manifest commit on another
///    queue. Shared files survive while ANY record still lists them.
/// 3. **Observation pruning** — `seen` entries whose id resolves to a
///    tombstoned article are forgotten; a fresh encounter may then start
///    a new first-observation era. Stamps for ids with no record at all —
///    the dateless candidates reconcile marks before membership — are
///    kept while their subscription may still carry them (#40 §5).
///
/// The pass is fail-closed: if the record state cannot be fully decoded,
/// no file is deleted — "unreferenced" cannot be proven when ownership
/// metadata is suspect. A failed tombstone likewise stops the pass before
/// deletions begin, since the reference set would no longer be trustworthy.
class ArticleCleanupService {
  ArticleCleanupService({
    required ArticleRecordStore records,
    required ArticleMediaStore media,
    LifecycleGate? gate,
  }) : _records = records,
       _media = media,
       _gate = gate ?? LifecycleGate.current;

  final ArticleRecordStore _records;
  final ArticleMediaStore _media;
  final LifecycleGate? _gate;

  /// Files younger than this may still be mid-commit on another queue —
  /// never collect them on a scan that cannot serialize with writers.
  static const Duration _orphanGrace = Duration(minutes: 2);

  /// Runs one lifecycle pass. [isBookmarked] is the caller's live-claim
  /// verdict for canonical ids — evaluated inside the store lock at
  /// commit time. It reconciles `'bookmark'` claims both ways: stale
  /// claims the set denies are stripped, and live records that lost
  /// their claim have it restored.
  Future<CleanupResult> sweep({bool Function(String id)? isBookmarked}) async {
    var failed = false;
    var tombstoned = 0;
    const blocked = CleanupResult(
      tombstoned: 0,
      deletedFiles: 0,
      prunedSeen: 0,
      failed: true,
    );

    // Deletion publishes under the lifecycle gate with the ticket of the
    // pass; a pending or later reset owns cleanup instead.
    final gate = _gate;
    LifecycleTicket? ticket;
    if (gate != null) {
      try {
        ticket = await gate.beginWork();
      } on LifecycleResetPending {
        return blocked;
      } on TimeoutException {
        return blocked;
      }
    }

    // The pass is fenced to the lifecycle epoch it started on — wipeAll
    // does not ride the register queue, so a reset can land mid-sweep; a
    // stale epoch then rejects the tombstones rather than writing records
    // back into a wiped store.
    final epoch = await _records.currentEpoch();

    // 1. Ownerless live records leave the lifecycle through the tombstone
    //    fence — hard-deleting would let a stale write resurrect them.
    final before = await _records.listRecordsForGc();
    if (!before.clean) return blocked;

    // 1a. 'bookmark' claims are reconciled BOTH ways against the caller's
    //    live set: a stale claim the set denies is stripped, and a live
    //    record whose claim was lost (failed register, stale strip) gets
    //    it back — no other pass re-adds 'bookmark' once it is gone. The
    //    predicate is re-evaluated inside the locked mutation, so a
    //    toggle racing this pass always sees the verdict current at
    //    commit time. Records absent entirely can't be restored here —
    //    they need item data only the register path carries.
    if (isBookmarked != null) {
      for (final record in before.records) {
        if (record.tombstoned) continue;
        final result = await _records.mutate(record.id, expectedEpoch: epoch, (
          current,
        ) {
          if (current == null || current.tombstoned) return current;
          final live = isBookmarked(current.id);
          final has = current.owners.contains('bookmark');
          if (live == has) return current;
          final owners = {...current.owners};
          live ? owners.add('bookmark') : owners.remove('bookmark');
          return current.copyWith(owners: owners);
        });
        if (result == StoreWriteResult.failed) failed = true;
      }
    }

    for (final record in before.records) {
      if (record.tombstoned || record.owners.isNotEmpty) continue;
      // Ownership is re-checked inside the locked mutation: a claim that
      // landed after our snapshot — possibly from another isolate's
      // register — must never be tombstoned by a stale "ownerless" view.
      var fenced = false;
      final result = await _records.mutate(record.id, expectedEpoch: epoch, (
        current,
      ) {
        if (current == null ||
            current.tombstoned ||
            current.owners.isNotEmpty) {
          return current;
        }
        fenced = true;
        return ArticleRecord(
          id: ArticleIdentity.normalizeItemId(record.id) ?? record.id,
          feedUrl: record.feedUrl,
          generation: current.generation + 1,
          tombstoned: true,
        );
      });
      if (result == StoreWriteResult.applied && fenced) {
        tombstoned++;
      } else if (result == StoreWriteResult.failed) {
        failed = true;
      }
    }

    var deleted = 0;
    var pruned = 0;
    if (!failed) {
      // 2. Reference set comes from a fresh clean snapshot — the pass that
      //    tombstoned must not trust its own pre-tombstone view.
      final after = await _records.listRecordsForGc();
      if (!after.clean || (await _records.currentEpoch()) != epoch) {
        // An unclean snapshot can't prove "unreferenced" — and a changed
        // epoch means a reset landed mid-pass, making this era's verdict
        // not ours to act on.
        failed = true;
      } else {
        final orphans = await _media.unreferencedFiles(
          after.records,
          minAge: _orphanGrace,
        );
        Future<void> collect() async {
          // The scan's verdict is stale by now: re-read references at
          // decision time, so a claim landing after the orphan scan keeps
          // its file. Gated media publication cannot interleave here.
          final latest = await _records.listRecordsForGc();
          if (!latest.clean || (await _records.currentEpoch()) != epoch) {
            failed = true;
            return;
          }
          final referenced = {
            for (final record in latest.records)
              for (final entry in record.media.values) entry.file,
          };
          for (final file in orphans) {
            if (referenced.contains(file)) continue;
            // Count only proven deletions — a refused write means the space
            // is NOT reclaimed, and the pass reports partial failure.
            if (await _media.delete(file)) {
              deleted++;
            } else {
              failed = true;
            }
          }
        }

        if (orphans.isNotEmpty) {
          if (gate == null) {
            await collect();
          } else {
            try {
              await gate.withPublication(ticket!, collect);
            } on StaleLifecycleTicket {
              failed = true;
            } on LifecycleResetPending {
              failed = true;
            } on TimeoutException {
              failed = true;
            }
          }
        }
        // 3. Forget observation stamps whose article ended its lifecycle
        //    (tombstoned). Stamps with no record at all stay — they belong
        //    to dateless candidates whose subscription still carries them,
        //    and dropping them would silently restart the first-seen era
        //    (#40 §5).
        final tombstonedIds = {
          for (final r in after.records)
            if (r.tombstoned) r.id,
        };
        for (final id in (await _records.allFirstSeen()).keys) {
          if (!tombstonedIds.contains(id)) continue;
          if (await _records.deleteFirstSeen(id, expectedEpoch: epoch) ==
              StoreWriteResult.applied) {
            pruned++;
          }
        }
      }
    }

    return CleanupResult(
      tombstoned: tombstoned,
      deletedFiles: deleted,
      prunedSeen: pruned,
      failed: failed,
    );
  }
}
