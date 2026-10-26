import 'article_identity.dart';
import 'article_media_store.dart';
import 'article_record_store.dart';

/// Persistence scope a durable article record grants the user — what the
/// row/article label may claim. `none` means no offline claim is shown
/// (normal feed item, ownerless residue, or a tombstone).
enum ArticleScope {
  none,
  saveRequested,
  savedText,
  savedReady,
  cachedText,
  cachedReady,
}

/// Why outstanding preparation work has not completed — the optional second
/// line under the scope label. Ordered by display precedence.
enum ArticleWait { unavailable, serverWait, retry, unmetered, preparing, none }

/// Lightweight, body-free summary of one [ArticleRecord] for UI surfaces.
///
/// Derived strictly from durable record state — never from image-cache
/// guesses or prefetch flags — so a "ready" label only appears when the
/// stored body is readable and every known media target is stored.
class ArticleStatus {
  const ArticleStatus({
    required this.owners,
    required this.bodyState,
    required this.bodySource,
    required this.hasBody,
    required this.bodyDue,
    required this.readyMedia,
    required this.totalMedia,
    required this.goneMedia,
    required this.goneBody,
    required this.earliestRetryAt,
    required this.earliestServerRetryAt,
    required this.hasServerWait,
    required this.hasDueWork,
    required this.hasActionable,
    required this.savedAt,
  });

  factory ArticleStatus.fromRecord(ArticleRecord r) {
    final hasBody = !r.tombstoned && (r.body?.isNotEmpty ?? false);
    // Body work only exists when there is a link to extract; otherwise the
    // RSS body already is the final state (mirrors _hasDueWork).
    final bodyDue = r.bodyState != MediaState.ready && r.link.isNotEmpty;
    var ready = 0, gone = 0, dueMedia = 0, serverWait = false;
    var actionable = bodyDue;
    DateTime? earliest, earliestServer;
    for (final e in r.media.values) {
      if (e.state == MediaState.ready) ready++;
      if (e.state == MediaState.gone) gone++;
      final due = e.state != MediaState.ready && e.state != MediaState.gone;
      if (due) {
        dueMedia++;
        if (e.waitSource == 'server') {
          serverWait = true;
          final t = e.nextRetryAt;
          if (t != null &&
              (earliestServer == null || t.isBefore(earliestServer))) {
            earliestServer = t;
          }
        }
        // A manual pass can only reach pieces with no wait or an explicit
        // local backoff — server/legacy waits stay protected.
        if (e.nextRetryAt == null || e.waitSource == 'backoff') {
          actionable = true;
        }
        // Only due pieces contribute to "earliest" — a gone entry keeps a
        // stale stamp that must not surface in the label.
        final t = e.nextRetryAt;
        if (t != null && (earliest == null || t.isBefore(earliest))) {
          earliest = t;
        }
      }
    }
    if (bodyDue) {
      final bodyWait = r.nextRetryAt;
      if (bodyWait != null &&
          (earliest == null || bodyWait.isBefore(earliest))) {
        earliest = bodyWait;
      }
    }
    return ArticleStatus(
      // A tombstoned record grants no offline claim even if fields linger.
      owners: r.tombstoned ? const {} : r.owners,
      bodyState: r.bodyState,
      bodySource: r.bodySource,
      hasBody: hasBody,
      bodyDue: bodyDue,
      readyMedia: ready,
      totalMedia: r.media.length,
      goneMedia: gone,
      goneBody: r.bodyState == MediaState.gone,
      earliestRetryAt: earliest,
      earliestServerRetryAt: earliestServer,
      hasServerWait: serverWait,
      hasDueWork: bodyDue || dueMedia > 0,
      hasActionable: actionable,
      savedAt: r.savedAt,
    );
  }

  final Set<String> owners;
  final MediaState bodyState;
  final String? bodySource;
  final bool hasBody;

  /// The full-text upgrade is still owed (RSS body may still be readable).
  final bool bodyDue;

  final int readyMedia;
  final int totalMedia;
  final int goneMedia;
  final bool goneBody;

  /// Earliest stored retry time across due body/media pieces — `gone`
  /// entries' stale stamps never reach this field.
  final DateTime? earliestRetryAt;

  /// Earliest wait among pieces stamped `'server'` — the time shown next to
  /// the "waiting on the source" label.
  final DateTime? earliestServerRetryAt;
  final bool hasServerWait;
  final bool hasDueWork;

  /// A manual pass can actually do work: something is due and at least one
  /// piece is either wait-free or gated only by a bypassable local backoff.
  final bool hasActionable;
  final DateTime? savedAt;

  bool get hasBookmark => owners.contains('bookmark');
  bool get hasTempCache => owners.contains('tempCache');

  /// The stored body is readable right now — kept regardless of upstream
  /// extraction state (RSS body survives a failed full-text attempt).
  bool get hasReadableBody => hasBody;

  /// Everything the user asked for is on disk: body final and every known
  /// media target stored. A `gone` piece already fails `readyMedia ==
  /// totalMedia`.
  bool get fullyReady =>
      hasReadableBody && !bodyDue && readyMedia == totalMedia;

  ArticleScope get scope {
    if (hasBookmark) {
      if (!hasReadableBody) return ArticleScope.saveRequested;
      return fullyReady ? ArticleScope.savedReady : ArticleScope.savedText;
    }
    if (hasTempCache) {
      if (!hasReadableBody) return ArticleScope.none;
      return fullyReady ? ArticleScope.cachedReady : ArticleScope.cachedText;
    }
    return ArticleScope.none;
  }

  /// The single most relevant reason preparation is incomplete.
  /// [unmeteredNow] is the caller's current transport verdict; [now]
  /// anchors stored retry times.
  ArticleWait waitFor({required bool unmeteredNow, required DateTime now}) {
    if (goneBody || goneMedia > 0) return ArticleWait.unavailable;
    final serverWaiting =
        earliestServerRetryAt != null && earliestServerRetryAt!.isAfter(now);
    if (serverWaiting) return ArticleWait.serverWait;
    final waiting = earliestRetryAt != null && earliestRetryAt!.isAfter(now);
    if (waiting) return ArticleWait.retry;
    if (hasDueWork) {
      return unmeteredNow ? ArticleWait.preparing : ArticleWait.unmetered;
    }
    return ArticleWait.none;
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleStatus &&
      other.owners.length == owners.length &&
      other.owners.containsAll(owners) &&
      other.bodyState == bodyState &&
      other.bodySource == bodySource &&
      other.hasBody == hasBody &&
      other.bodyDue == bodyDue &&
      other.readyMedia == readyMedia &&
      other.totalMedia == totalMedia &&
      other.goneMedia == goneMedia &&
      other.goneBody == goneBody &&
      other.earliestRetryAt == earliestRetryAt &&
      other.earliestServerRetryAt == earliestServerRetryAt &&
      other.hasServerWait == hasServerWait &&
      other.hasDueWork == hasDueWork &&
      other.hasActionable == hasActionable &&
      other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(owners),
    bodyState,
    bodySource,
    hasBody,
    bodyDue,
    readyMedia,
    totalMedia,
    goneMedia,
    goneBody,
    earliestRetryAt,
    earliestServerRetryAt,
    hasServerWait,
    hasDueWork,
    hasActionable,
    savedAt,
  );
}

/// Lightweight status map for list/article surfaces: tombstoned records are
/// excluded and a corrupt store fails closed to an empty map — a missing
/// entry means "no offline claim", never "ready".
///
/// When [media] is given, `ready` manifest entries are verified against
/// the actual file on disk before they may back a "ready" label: a file
/// that vanished or is truncated demotes the entry back to `pending` —
/// repaired in the record so the engine retries it — and never counts
/// toward the label (#41 verify-before-ready).
Future<Map<ArticleRef, ArticleStatus>> listArticleStatuses(
  ArticleRecordStore store, {
  ArticleMediaStore? media,
}) async {
  final gc = await store.listRecordsForGc();
  if (!gc.clean) return const {};
  final map = <ArticleRef, ArticleStatus>{};
  for (final r in gc.records) {
    if (r.tombstoned) continue;
    final ref = ArticleRef(r.feedUrl, r.id);
    var record = r;
    if (media != null && r.media.isNotEmpty) {
      final stale = <String>{};
      for (final e in r.media.entries) {
        if (e.value.state == MediaState.ready && !await media.verify(e.value)) {
          stale.add(e.key);
        }
      }
      if (stale.isNotEmpty) {
        MediaEntry demote(MediaEntry e) =>
            e.copyWith(state: MediaState.pending, nextRetryAt: () => null);
        // Repair the manifest in the same decision: the engine only
        // retries pending entries, so the claim and the truth converge.
        // The demote is snapshot-checked — a fresh ready entry committed
        // by a concurrent prepare pass between the snapshot and this lock
        // is not ours to downgrade.
        await store.mutate(ref, (current) {
          if (current == null || current.tombstoned) return current;
          final m = {...current.media};
          var changed = false;
          for (final key in stale) {
            final e = m[key];
            final snap = record.media[key];
            if (e == null ||
                snap == null ||
                e.state != MediaState.ready ||
                e.file != snap.file ||
                e.byteSize != snap.byteSize) {
              continue;
            }
            m[key] = demote(e);
            changed = true;
          }
          return changed ? current.copyWith(media: m) : current;
        });
        final m = {...record.media};
        for (final key in stale) {
          final e = m[key];
          if (e != null) m[key] = demote(e);
        }
        record = record.copyWith(media: m);
      }
    }
    map[ref] = ArticleStatus.fromRecord(record);
  }
  return map;
}
