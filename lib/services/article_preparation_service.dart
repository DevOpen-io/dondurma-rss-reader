import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../utils/async_semaphore.dart';
import '../utils/bounded_body.dart';
import '../utils/host_pacer.dart';
import '../utils/retry_after.dart';
import 'article_cleanup_service.dart';
import 'article_identity.dart';
import 'article_media_store.dart';
import 'article_record_store.dart';
import 'feed_backoff.dart';
import 'feed_service.dart';
import 'full_text_extraction_service.dart';
import 'lifecycle_gate.dart';

/// Offline preparation engine: ensures a saved article's full text and all of
/// its images are durably stored, per the #39 contract —
///
/// * automatic preparation only on unmetered networks ([preparePending]);
/// * an explicit user action ([prepareArticle], e.g. bookmarking) permits one
///   preparation pass for that one article, metered or not;
/// * at most [maxParallelTransfers] concurrent downloads per instance
///   (cross-isolate writers converge through the shared store lock and
///   deterministic file names);
/// * per-piece single attempt per pass, ready parts are kept;
/// * transient failures reschedule via doubling backoff capped at 60 minutes,
///   honoring a longer server `Retry-After`;
/// * tombstoned records are never resurrected — every mutation re-checks
///   inside the store lock.
class ArticlePreparationService {
  ArticlePreparationService({
    ArticleRecordStore? recordStore,
    ArticleMediaStore? mediaStore,
    http.Client? client,
    Future<String?> Function(String url)? extractFullText,
    this.maxParallelTransfers = 3,
    this.minHostGap = const Duration(milliseconds: 1500),
    HostPacer? hostPacer,
    FeedBackoff? backoff,
    DateTime Function()? now,
    LifecycleGate? gate,
  }) : _backoff = backoff,
       _gate = gate ?? LifecycleGate.current,
       _records = recordStore ?? ArticleRecordStore.of(Hive.box('feeds')),
       _media = mediaStore ?? ArticleMediaStore(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _extract = extractFullText ?? _defaultExtract,
       _now = now ?? DateTime.now {
    _semaphore = AsyncSemaphore(maxParallelTransfers);
    _hostPacer = hostPacer ?? HostPacer(minGap: minHostGap, now: _now);
  }

  /// Releases the internally created HTTP client (injected clients stay the
  /// caller's responsibility).
  void dispose() {
    if (_ownsClient) _client.close();
  }

  static Future<String?> _defaultExtract(String url) =>
      FullTextExtractionService.instance.extractFullText(url);

  static const int maxImagesPerArticle = 32;
  static const int maxMediaBytes = 15 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 15);

  final ArticleRecordStore _records;
  final ArticleMediaStore _media;
  final LifecycleGate? _gate;
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function(String url) _extract;
  final int maxParallelTransfers;

  /// Minimum spacing between requests to the same host — see [HostPacer].
  /// Kept as a ctor parameter because tests shrink it instead of waiting.
  /// Acts as this service's gap inside a shared pacer when one is
  /// injected by the provider.
  final Duration minHostGap;
  late final HostPacer _hostPacer;

  /// Shared rate-limit policy — a host cooldown learned by feed refresh
  /// (e.g. a Reddit 429) holds extraction and media downloads back too.
  /// Skipped pieces simply stay pending; cooldown is not a failure.
  final FeedBackoff? _backoff;

  /// Skipped pieces simply stay pending — a cooldown is not a failure.
  /// A manual retry may bypass a locally estimated host cooldown, but
  /// never a server-issued `Retry-After` mandate.
  bool _hostCooled(String url, DateTime now, {bool manual = false}) {
    final b = _backoff;
    if (b == null) return false;
    return manual ? b.isMandatedBackedOff(url, now) : b.isBackedOff(url, now);
  }

  final DateTime Function() _now;
  late final AsyncSemaphore _semaphore;

  /// Waits until [url]'s host is allowed another request, then reserves
  /// the next slot — this service's stricter [minHostGap] applies even
  /// inside a shared pacer.
  Future<void> _paceHost(String url) => _hostPacer.pace(url, gap: minHostGap);

  /// Serializes every public operation on this instance so overlapping
  /// sweeps/permits can't double-attempt a piece in the same logical pass.
  /// (Cross-isolate writers still serialize at the store's file lock; the
  /// shared file name makes a duplicate download converge to the same file.)
  /// FIFO order means an explicit permit may queue behind a running sweep —
  /// accepted: the permit re-reads state and converges on whatever the
  /// sweep already completed.
  Future<dynamic> _tail = Future<void>.value();

  /// Registrations ride a second queue: each is a single atomic record
  /// mutation, so it can't interleave destructively with a sweep — and a
  /// multi-minute sweep must never stall membership reconciliation (#37),
  /// which awaits every registration it issues.
  Future<dynamic> _registerTail = Future<void>.value();

  /// Completes once both queues are drained, including work enqueued while
  /// waiting — lets tests and shutdown await fire-and-forget mutations.
  Future<void> get idle async {
    while (true) {
      final tail = _tail;
      final registerTail = _registerTail;
      await Future.wait([tail, registerTail]);
      if (identical(tail, _tail) && identical(registerTail, _registerTail)) {
        return;
      }
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then((_) => null, onError: (_) => null);
    return result;
  }

  Future<T> _enqueueRegister<T>(Future<T> Function() work) {
    final result = _registerTail.then((_) => work());
    _registerTail = result.then((_) => null, onError: (_) => null);
    return result;
  }

  /// In-memory write fence: bumped by [resetFence] so mutations ENQUEUED
  /// before a factory reset no-op instead of resurrecting wiped records.
  /// Cross-isolate writers (Workmanager) can't see this — they carry the
  /// store's persisted epoch instead (see `expectedEpoch`).
  var _queueEpoch = 0;

  /// No-ops every register-queue mutation enqueued before this call. Run on
  /// factory reset before the stores are wiped.
  void resetFence() => _queueEpoch++;

  Future<StoreWriteResult> _enqueueGuarded(
    Future<StoreWriteResult> Function(bool Function() isCurrent) work,
  ) {
    final enqueuedAt = _queueEpoch;
    // Also pass the check into the locked mutation: the work may already
    // have left this queue and be waiting for another writer during reset.
    bool isCurrent() => enqueuedAt == _queueEpoch;
    return _enqueueRegister(() async {
      if (!isCurrent()) return StoreWriteResult.rejected;
      final result = await work(isCurrent);
      // A fence landing mid-mutation turned it into a no-op the store still
      // reports as applied; claim listeners must not see that as success.
      return isCurrent() ? result : StoreWriteResult.rejected;
    });
  }

  /// Runs [update] on the register queue so owner strips serialize FIFO
  /// with [registerArticle] — the user's toggle order IS the durable order,
  /// and a queued registration can never re-add an owner already stripped.
  Future<StoreWriteResult> mutateRecord(
    ArticleRef ref,
    ArticleRecord? Function(ArticleRecord? current) update, {
    int? expectedEpoch,
  }) => _enqueueGuarded(
    (isCurrent) => _records.mutate(
      ref,
      (current) => isCurrent() ? update(current) : current,
      expectedEpoch: expectedEpoch,
    ),
  );

  /// One lifecycle sweep on the register queue: tombstones ownerless
  /// records, deletes unreferenced media, prunes dead observation stamps.
  /// Serialized with registrations so no manifest commits mid-scan.
  /// Deliberately NOT queue-epoch guarded — post-reset hygiene is exactly
  /// what a queued pass should still do. Repeat callers coalesce onto the
  /// in-flight pass plus at most one re-run.
  Future<CleanupResult> sweepCleanup({
    bool Function(ArticleRef ref)? isBookmarked,
  }) {
    final inFlight = _sweepInFlight;
    if (inFlight != null) {
      _sweepAgain = true;
      return inFlight;
    }
    final run = _enqueueRegister(() async {
      try {
        var result = await _cleanup.sweep(isBookmarked: isBookmarked);
        while (_sweepAgain) {
          _sweepAgain = false;
          result = await _cleanup.sweep(isBookmarked: isBookmarked);
        }
        if (result.failed) {
          debugPrint(
            'ArticlePreparationService: lifecycle sweep reported failure — '
            'unclaimed media stays put until a clean pass succeeds.',
          );
        }
        return result;
      } finally {
        // Never leave the dead future behind — a throwing pass would
        // otherwise park _sweepInFlight forever and silently disable
        // every subsequent sweep this session.
        _sweepInFlight = null;
      }
    });
    return _sweepInFlight = run;
  }

  Future<CleanupResult>? _sweepInFlight;
  var _sweepAgain = false;

  late final ArticleCleanupService _cleanup = ArticleCleanupService(
    records: _records,
    media: _media,
    gate: _gate,
  );

  /// Lifecycle ticket for one unit of work, captured before its inputs are
  /// read. Null when ungated; throws while a reset is pending.
  Future<LifecycleTicket?> _beginWork() async => _gate?.beginWork();

  /// The store's persisted lifecycle epoch — capture before a unit of work
  /// and pass to mutations as `expectedEpoch` to fence out resets.
  Future<int> currentRecordEpoch() => _records.currentEpoch();

  /// Automatic preparation is licensed only when an unmetered transport
  /// (wifi/ethernet) is present AND no metered one is reported. `vpn` is
  /// neutral — a VPN over cellular still reports `mobile` alongside it, so
  /// metering is decided by the underlying transports. Mobile and
  /// unknown-cost sets wait — never an auto-download license.
  static bool unmeteredNetwork(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    if (results.contains(ConnectivityResult.mobile)) return false;
    return results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
  }

  /// Image lists of recently registered RSS bodies, least recent first.
  /// Reconcile re-registers every cache member on each pass; re-parsing
  /// each unchanged body was the bulk of that pass's main-isolate work.
  final _rssBodyImages = <String, List<String>>{};

  List<String> _rssBodyImageUrls(String? html) {
    if (html == null || html.isEmpty) return const [];
    final known = _rssBodyImages.remove(html);
    final urls = known ?? _bodyImageUrls(html);
    _rssBodyImages[html] = urls;
    if (_rssBodyImages.length > 256) {
      _rssBodyImages.remove(_rssBodyImages.keys.first);
    }
    return urls;
  }

  static List<String> _bodyImageUrls(String? html) {
    if (html == null || html.isEmpty) return const [];
    return parse(html)
        .getElementsByTagName('img')
        .map((e) => e.attributes['src'] ?? e.attributes['data-src'])
        .whereType<String>()
        .where((s) => s.startsWith('http'))
        .take(maxImagesPerArticle)
        .toList();
  }

  /// Persists the minimal durable record for [item]: the best body at hand
  /// (the RSS body), discovered image URLs, a `pending` media manifest, and
  /// the union of [owners]. Idempotent — re-calls merge owners and top up
  /// missing manifest pieces without touching ready content. A tombstoned
  /// record is [ArticleRecordStore.revive]d because re-bookmarking is a new
  /// lifecycle claim, not a stale write.
  ///
  /// Callers racing an un-bookmark (S5 tombstone) must re-check bookmark
  /// state before calling — a delayed register revives a deleted record.
  ///
  /// [fullText] is the caller's effective extraction preference: `false`
  /// means the RSS body is the final content — a still-pending or failed
  /// extraction intent on an existing record is cancelled, never retried.
  /// [expectedEpoch] fences this registration against a mid-flight factory
  /// reset: the caller captured [currentRecordEpoch] before its async work
  /// began, and a wipe in between rejects the write instead of resurrecting
  /// a record the reset already erased.
  ///
  /// [claimCheck] is evaluated INSIDE the store lock at mutation time — a
  /// caller whose claim may have been rescinded between enqueue and
  /// execution (e.g. an un-bookmark racing this registration) passes its
  /// live-state check so a delayed register can never resurrect an owner
  /// that was already stripped.
  Future<StoreWriteResult> registerArticle(
    FeedItem item,
    Set<String> owners, {
    bool fullText = true,
    int? expectedEpoch,
    bool Function()? claimCheck,
  }) {
    if (owners.isEmpty) return Future.value(StoreWriteResult.rejected);
    return _enqueueGuarded(
      (isCurrent) => _registerArticle(
        item,
        owners,
        fullText,
        expectedEpoch,
        () => isCurrent() && (claimCheck?.call() ?? true),
      ),
    );
  }

  Future<StoreWriteResult> _registerArticle(
    FeedItem item,
    Set<String> owners,
    bool fullText,
    int? expectedEpoch,
    bool Function()? claimCheck,
  ) async {
    final imageUrls = <String>{
      if (item.imageUrl != null && item.imageUrl!.isNotEmpty) item.imageUrl!,
      ..._rssBodyImageUrls(item.content),
    }.toList();
    final manifest = {
      for (final url in imageUrls) url: ArticleMediaStore.pendingEntry(url),
    };
    final draft = ArticleRecord(
      id: item.id,
      feedUrl: item.feedUrl,
      link: item.link,
      title: item.title,
      siteName: item.siteName,
      body: item.content,
      bodyState: (item.link.isEmpty || !fullText)
          ? MediaState.ready
          : MediaState.pending,
      bodySource: 'rss',
      publishedAt: item.pubDate,
      savedAt: _now().toUtc(),
      imageUrls: imageUrls,
      media: manifest,
      owners: owners,
    );
    // A proven copy of the same article from another source donates its
    // extracted body and ready media — copied into this instance's own
    // record, so the instances stay independent afterwards.
    // Only a new instance can take a donation; reconcile re-registers
    // existing members every pass and must not scan the archive each time.
    final existing = fullText ? await _records.read(ArticleRef.of(item)) : null;
    final donor = fullText && (existing == null || existing.tombstoned)
        ? await _provenDonor(item)
        : null;
    final fresh = donor == null
        ? draft
        : draft.copyWith(
            body: () => donor.body,
            bodyState: MediaState.ready,
            bodySource: () => 'extracted',
            imageUrls: {...imageUrls, ...donor.imageUrls}.toList(),
            media: {
              ...manifest,
              for (final e in donor.media.entries)
                if (e.value.state == MediaState.ready) e.key: e.value,
            },
          );
    return _records.mutate(ArticleRef.of(item), expectedEpoch: expectedEpoch, (
      current,
    ) {
      // The claim must still be live inside the lock — a rescinded claim
      // (un-bookmark, strip) must not be re-added by this delayed write.
      if (claimCheck != null && !claimCheck()) return current;
      if (current != null && !current.tombstoned) {
        final mergedOwners = {...current.owners, ...owners};
        final mergedMedia = {...manifest, ...current.media};
        final mergedImages = {...current.imageUrls, ...imageUrls};
        // Extraction switched off → unfinished extraction intent (pending
        // or failed-with-retry) settles on the RSS body. Switched back on →
        // a ready record whose body was never extracted regains intent.
        final nextBodyState = !fullText && current.bodyState != MediaState.ready
            ? MediaState.ready
            : fullText &&
                  current.bodyState == MediaState.ready &&
                  current.bodySource != 'extracted' &&
                  current.link.isNotEmpty
            ? MediaState.pending
            : current.bodyState;
        final nextTitle = (draft.title ?? '').isNotEmpty
            ? draft.title
            : current.title;
        final nextPublishedAt = draft.publishedAt ?? current.publishedAt;
        final nextBodySource = current.body == null && draft.body != null
            ? 'rss'
            : current.bodySource;
        // Skip the locked file write when the merge is a no-op — reconcile
        // re-registers every member each pass.
        if (mergedOwners.length == current.owners.length &&
            mergedMedia.length == current.media.length &&
            mergedImages.length == current.imageUrls.length &&
            nextBodyState == current.bodyState &&
            (current.body != null || draft.body == null) &&
            current.link.isNotEmpty &&
            nextTitle == current.title &&
            nextPublishedAt == current.publishedAt &&
            nextBodySource == current.bodySource) {
          return current;
        }
        return current.copyWith(
          owners: mergedOwners,
          media: mergedMedia,
          imageUrls: mergedImages.toList(),
          body: current.body == null ? () => draft.body : null,
          bodySource: nextBodySource != current.bodySource
              ? () => nextBodySource
              : null,
          link: current.link.isEmpty ? draft.link : current.link,
          title: nextTitle != current.title ? () => nextTitle : null,
          publishedAt: nextPublishedAt != current.publishedAt
              ? () => nextPublishedAt
              : null,
          bodyState: nextBodyState,
          // Settling onto the RSS body cancels the extraction wait — a
          // stale nextRetryAt would otherwise label the record "retry
          // pending" forever (#41 phantom-wait fix).
          nextRetryAt:
              (nextBodyState == MediaState.ready &&
                  nextBodyState != current.bodyState)
              ? () => null
              : null,
        );
      }
      if (current?.tombstoned == true) {
        return fresh.copyWith(
          owners: owners,
          generation: current!.generation + 1,
        );
      }
      return fresh.copyWith(generation: 1);
    });
  }

  /// Another source's live record proven to be the same article: same
  /// normalized article link and same non-empty title, with an extracted
  /// body. A shared GUID or link alone is not proof.
  Future<ArticleRecord?> _provenDonor(FeedItem item) async {
    final link = ArticleIdentity.normalizeArticleUrl(item.link);
    if (link == null || item.title.isEmpty) return null;
    final self = ArticleRef.of(item);
    for (final record in await _records.listRecords()) {
      if (record.tombstoned ||
          record.bodyState != MediaState.ready ||
          record.bodySource != 'extracted' ||
          record.title != item.title ||
          ArticleIdentity.normalizeArticleUrl(record.link) != link ||
          ArticleRef(record.feedUrl, record.id) == self) {
        continue;
      }
      return record;
    }
    return null;
  }

  /// Explicit single-article permit: one preparation pass for [articleId]
  /// regardless of transport cost — this is the "one article, one pass"
  /// mobile-data license an explicit user action grants. Local backoff
  /// waits may be bypassed here; a server `Retry-After` wait never is.
  Future<int> prepareArticle(ArticleRef ref) =>
      _enqueue(() => _prepareArticle(ref));

  Future<int> _prepareArticle(ArticleRef ref) async {
    final LifecycleTicket? ticket;
    try {
      ticket = await _beginWork();
    } on LifecycleResetPending {
      return 0;
    } on TimeoutException {
      return 0;
    }
    // Fence before reading the snapshot. A reset between read and epoch
    // capture must not license old content to mutate a new-era record.
    final epoch = await _records.currentEpoch();
    final record = await _records.read(ref);
    if (record == null || record.tombstoned || record.owners.isEmpty) {
      return 0;
    }
    await _prepareRecord(record, _now().toUtc(), epoch, ticket, manual: true);
    return 1;
  }

  /// Automatic sweep over every owned record with due, incomplete work.
  /// [unmetered] is the caller's transport verdict — `false` (metered or
  /// unknown) means nothing is downloaded at all.
  Future<int> preparePending({required bool unmetered}) {
    if (!unmetered) return Future.value(0);
    return _enqueue(_preparePending);
  }

  Future<int> _preparePending() async {
    final LifecycleTicket? ticket;
    try {
      ticket = await _beginWork();
    } on LifecycleResetPending {
      return 0;
    } on TimeoutException {
      return 0;
    }
    final now = _now().toUtc();
    // Fence before the snapshot: a reset during either read must reject
    // all old commits, never license stale content with the new epoch.
    final epoch = await _records.currentEpoch();
    final records = await _records.listRecords();
    var attempted = 0;
    for (final record in records) {
      if (record.tombstoned || record.owners.isEmpty) continue;
      if (!_hasDueWork(record, now)) continue;
      attempted++;
      try {
        await _prepareRecord(record, now, epoch, ticket);
      } catch (_) {
        // One bad record never forfeits the rest of the sweep — its durable
        // state is retried at the next eligible opportunity.
      }
    }
    return attempted;
  }

  bool _hasDueWork(ArticleRecord record, DateTime now) {
    // Body work only exists when there's a link to extract — otherwise the
    // RSS body already is the final state.
    if (record.bodyState != MediaState.ready &&
        record.link.isNotEmpty &&
        (record.nextRetryAt == null || !record.nextRetryAt!.isAfter(now))) {
      return true;
    }
    for (final entry in record.media.values) {
      if (entry.state != MediaState.ready &&
          entry.state != MediaState.gone &&
          (entry.nextRetryAt == null || !entry.nextRetryAt!.isAfter(now))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _prepareRecord(
    ArticleRecord record,
    DateTime now,
    int epoch,
    LifecycleTicket? ticket, {
    bool manual = false,
  }) async {
    final id = ArticleRef(record.feedUrl, record.id);

    // 1. Body: full-text upgrade. The RSS body is kept when extraction fails.
    if (record.bodyState != MediaState.ready && record.link.isNotEmpty) {
      // A body wait is only ever the local doubling backoff — an explicit
      // user retry may bypass it (server waits only exist on media).
      final retryDue =
          (manual ||
              record.nextRetryAt == null ||
              !record.nextRetryAt!.isAfter(now)) &&
          // A host cooldown learned elsewhere (feed 429) skips the
          // extraction attempt without counting it as a failure.
          !_hostCooled(record.link, now, manual: manual);
      if (retryDue) {
        String? html;
        try {
          // The extraction service paces its own request against the
          // shared HostPacer — pacing here too would double the gap.
          html = await _extract(record.link);
        } catch (_) {}
        // A page that yields no more than the RSS body is a failed
        // extraction — never an offline "full text" equal to the excerpt.
        if (html != null &&
            html.isNotEmpty &&
            !FullTextExtractionService.isMoreThanExcerpt(
              FullTextExtractionService.plainText(html),
              FullTextExtractionService.plainText(record.body ?? ''),
            )) {
          FullTextExtractionService.instance.discard(record.link);
          html = null;
        }
        // Parsed before the record lock: the lock is shared with the
        // background isolate, which waits at most a few seconds for it.
        final extractedImages = html == null || html.isEmpty
            ? const <String>[]
            : _bodyImageUrls(html);
        await _records.mutate(id, expectedEpoch: epoch, (current) {
          if (current == null ||
              current.tombstoned ||
              current.generation != record.generation) {
            return current;
          }
          if (current.owners.isEmpty) return current;
          // A slower overlapping pass that already succeeded never gets
          // downgraded by this one's failure.
          if (current.bodyState == MediaState.ready) return current;
          if (html != null && html.isNotEmpty) {
            final newImages = extractedImages
                .where((u) => !current.media.containsKey(u))
                .toList();
            final mergedMedia = {...current.media};
            for (final url in newImages) {
              mergedMedia[url] = ArticleMediaStore.pendingEntry(url);
            }
            return current.copyWith(
              body: () => html,
              bodyState: MediaState.ready,
              bodySource: () => 'extracted',
              nextRetryAt: () => null,
              imageUrls: {...current.imageUrls, ...newImages}.toList(),
              media: mergedMedia,
            );
          }
          // Deferred only when the extraction was skipped WITHOUT a
          // request (a cooldown gate saw it first). A page that actually
          // answered 429 is a real failed attempt — the cooldown it just
          // recorded covers this same check, so the marker is what
          // separates "skipped" from "fetched and failed".
          if (_hostCooled(record.link, _now(), manual: manual) &&
              FullTextExtractionService.instance.wasDeferred(record.link)) {
            return current;
          }
          final attempts = current.attempts + 1;
          return current.copyWith(
            bodyState: MediaState.failed,
            attempts: attempts,
            nextRetryAt: () => now.add(retryBackoff(attempts)),
          );
        });
      }
    }

    // 2. Media: every due non-ready piece gets at most one attempt this pass.
    final fresh = await _records.read(id);
    if (fresh == null ||
        fresh.tombstoned ||
        fresh.owners.isEmpty ||
        fresh.generation != record.generation) {
      return;
    }
    final pending = <MapEntry<String, MediaEntry>>[
      for (final e in fresh.media.entries)
        if (e.value.state != MediaState.ready &&
            e.value.state != MediaState.gone &&
            !_hostCooled(e.key, now, manual: manual) &&
            (e.value.nextRetryAt == null ||
                !e.value.nextRetryAt!.isAfter(now) ||
                // A manual retry may bypass the local backoff — but never a
                // server-issued Retry-After wait. Legacy entries carry no
                // stamp, so only an explicit 'backoff' is bypassable.
                (manual && e.value.waitSource == 'backoff')))
          e,
    ];
    await Future.wait([
      for (final piece in pending)
        _preparePiece(
          id,
          piece.key,
          epoch,
          record.generation,
          ticket,
          manual: manual,
        ),
    ]);
  }

  Future<void> _preparePiece(
    ArticleRef id,
    String url,
    int epoch,
    int generation,
    LifecycleTicket? ticket, {
    bool manual = false,
  }) async {
    await _semaphore.acquire();
    try {
      final outcome = await _fetchAndStore(url, manual: manual);
      // A multi-resource publication (managed file + manifest): void once
      // the ticket's era is over.
      await publishInEra(_gate, ticket, () async {
        MediaEntry? ready;
        final bytes = outcome.bytes;
        if (bytes != null) {
          // Bytes reach the shared URL file only for the era and record
          // generation that requested them: a stale response must neither
          // create a file after a reset nor overwrite newer bytes (A/J).
          final current = await _records.read(id);
          final entry = current?.media[url];
          if (current != null &&
              !current.tombstoned &&
              current.generation == generation &&
              current.owners.isNotEmpty &&
              entry != null &&
              entry.state != MediaState.ready &&
              await _records.currentEpoch() == epoch) {
            ready = await _media.put(url, bytes);
          }
        }
        await _commitPiece(id, url, epoch, generation, outcome, ready);
      });
    } finally {
      _semaphore.release();
    }
  }

  Future<void> _commitPiece(
    ArticleRef id,
    String url,
    int epoch,
    int generation,
    _PieceOutcome outcome,
    MediaEntry? ready,
  ) => _records.mutate(id, expectedEpoch: epoch, (current) {
    if (current == null ||
        current.tombstoned ||
        current.generation != generation) {
      return current;
    }
    if (current.owners.isEmpty) return current;
    final existing = current.media[url];
    if (existing == null) return current;
    // Deferred by a host cooldown learned mid-queue: not an attempt —
    // the piece stays pending with its retry state untouched.
    if (outcome.deferred) return current;
    // Never downgrade a piece another pass already completed.
    if (existing.state == MediaState.ready) return current;
    // A permanent failure is fenced too: a racing pass's transient
    // failure must not resurrect it into the retry cycle.
    if (existing.state == MediaState.gone && ready == null) {
      return current;
    }
    // Bytes that were not published (stale record) commit nothing.
    if (outcome.bytes != null && ready == null) return current;
    final attempts = existing.attempts + 1;
    final media = {...current.media};
    if (ready != null) {
      media[url] = ready.copyWith(attempts: attempts);
    } else if (outcome.gone) {
      media[url] = existing.copyWith(
        state: MediaState.gone,
        attempts: attempts,
      );
    } else {
      // The later of doubling backoff and server Retry-After wins —
      // a manual retry must not bypass a 429 wait either. A stored
      // (possibly longer, e.g. Retry-After) wait is never shortened.
      var retryAt = _now().add(retryBackoff(attempts));
      var waitSource = 'backoff';
      final server = outcome.retryAfter;
      if (server != null && server.isAfter(retryAt)) {
        retryAt = server;
        waitSource = 'server';
      }
      final stored = existing.nextRetryAt;
      if (stored != null && stored.isAfter(retryAt)) {
        retryAt = stored;
        // A kept legacy wait keeps its protection: unknown origin is
        // treated like a server wait, not a bypassable backoff.
        waitSource = existing.waitSource ?? 'server';
      }
      media[url] = existing.copyWith(
        state: MediaState.failed,
        attempts: attempts,
        nextRetryAt: () => retryAt,
        waitSource: () => waitSource,
      );
    }
    return current.copyWith(media: media);
  });

  /// Downloads [url] into the media pool. Returns the ready manifest entry
  /// on success; [gone] for permanent failures (404/410, non-image payload,
  /// oversize) that must never be retried; [retryAfter] carries the server's
  /// hint for transient failures; [deferred] marks a skip with zero
  /// attempts — the piece was cooled mid-queue, not failed.
  ///
  /// All retry math uses a fresh `_now()` at response time — the sweep's
  /// `now` may be minutes stale after semaphore and pacing waits, and a
  /// `Retry-After` relative to a dead timestamp schedules wrong.
  Future<_PieceOutcome> _fetchAndStore(
    String url, {
    bool manual = false,
  }) async {
    try {
      await _paceHost(url);
      // The queue wait may have spanned a sibling's 429 — honor the
      // cooldown learned in the meantime instead of firing anyway.
      if (_hostCooled(url, _now(), manual: manual)) {
        return (bytes: null, retryAfter: null, gone: false, deferred: true);
      }
      // The body streams with a cap, so an oversize or non-image payload is
      // dropped without buffering it.
      final (response, bytes) = await sendBounded(
        _client,
        http.Request('GET', Uri.parse(url))
          ..headers['User-Agent'] = 'Mozilla/5.0 (compatible; Dondurma RSS)',
        maxBytes: maxMediaBytes,
        accept: (response) {
          final type = response.headers['content-type'] ?? '';
          final declared = response.contentLength;
          return response.statusCode == 200 &&
              (type.isEmpty || type.startsWith('image/')) &&
              (declared == null || declared <= maxMediaBytes);
        },
        timeout: _requestTimeout,
      );
      if (response.statusCode == 200) {
        if (bytes == null || bytes.isEmpty) {
          // Soft-404 HTML / captive portal / oversize / empty payload —
          // structural, not transient: retrying would fetch the same
          // non-image forever (an empty put throws, looping the wait).
          return (bytes: null, retryAfter: null, gone: true, deferred: false);
        }
        return (bytes: bytes, retryAfter: null, gone: false, deferred: false);
      }
      final retryAfter = parseRetryAfter(
        response.headers['retry-after'],
        _now(),
      );
      // A media 429 is a host-wide signal too — share it so feed fetches
      // and other pieces on the same origin stop hammering the server.
      if (response.statusCode == 429 ||
          response.statusCode == 503 ||
          retryAfter != null) {
        _backoff?.recordFailure(
          url,
          FeedFetchException(
            FeedFetchErrorKind.httpStatus,
            'Media fetch failed (Status: ${response.statusCode})',
            retryAfter: retryAfter,
            statusCode: response.statusCode,
          ),
          _now(),
        );
      }
      return (
        bytes: null,
        retryAfter: retryAfter,
        gone: response.statusCode == 404 || response.statusCode == 410,
        deferred: false,
      );
    } catch (_) {
      return (bytes: null, retryAfter: null, gone: false, deferred: false);
    }
  }
}

/// Downloaded bytes are staged in memory; they reach the media pool only
/// inside the gated publication of [ArticlePreparationService._preparePiece].
typedef _PieceOutcome = ({
  Uint8List? bytes,
  DateTime? retryAfter,
  bool gone,
  bool deferred,
});
