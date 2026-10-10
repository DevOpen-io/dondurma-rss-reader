import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_ce/hive.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import '../models/feed_item.dart';
import '../utils/async_semaphore.dart';
import 'article_media_store.dart';
import 'article_record_store.dart';
import 'full_text_extraction_service.dart';

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
    DateTime Function()? now,
  }) : _records = recordStore ?? ArticleRecordStore.forBox(Hive.box('feeds')),
       _media = mediaStore ?? ArticleMediaStore(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _extract = extractFullText ?? _defaultExtract,
       _now = now ?? DateTime.now {
    _semaphore = AsyncSemaphore(maxParallelTransfers);
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
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function(String url) _extract;
  final int maxParallelTransfers;
  final DateTime Function() _now;
  late final AsyncSemaphore _semaphore;

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

  /// 1→2→4→8… minute doubling, capped at 60 — the earliest next attempt, not
  /// a guaranteed run time.
  static Duration backoffFor(int attempts) {
    if (attempts < 1) return Duration.zero;
    final minutes = 1 << (attempts - 1).clamp(0, 6);
    return Duration(minutes: minutes > 60 ? 60 : minutes);
  }

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

  static DateTime? _parseRetryAfter(String? header, DateTime now) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null && seconds >= 0) {
      return now.add(Duration(seconds: seconds));
    }
    try {
      final date = HttpDate.parse(header);
      return date.isAfter(now) ? date : null;
    } catch (_) {
      return null;
    }
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
  Future<StoreWriteResult> registerArticle(
    FeedItem item,
    Set<String> owners, {
    bool fullText = true,
  }) {
    if (owners.isEmpty) return Future.value(StoreWriteResult.rejected);
    return _enqueueRegister(() => _registerArticle(item, owners, fullText));
  }

  Future<StoreWriteResult> _registerArticle(
    FeedItem item,
    Set<String> owners,
    bool fullText,
  ) async {
    final imageUrls = <String>{
      if (item.imageUrl != null && item.imageUrl!.isNotEmpty) item.imageUrl!,
      ..._bodyImageUrls(item.content),
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
    return _records.mutate(item.id, (current) {
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
        );
      }
      if (current?.tombstoned == true) {
        return draft.copyWith(
          owners: owners,
          generation: current!.generation + 1,
        );
      }
      return draft.copyWith(generation: 1);
    });
  }

  /// Explicit single-article permit: one preparation pass for [articleId]
  /// regardless of transport cost — this is the "one article, one pass"
  /// mobile-data license an explicit user action grants. Still honors the
  /// stored `nextRetryAt` of each piece — a manual retry never bypasses a
  /// server `Retry-After` wait.
  Future<int> prepareArticle(String articleId) =>
      _enqueue(() => _prepareArticle(articleId));

  Future<int> _prepareArticle(String articleId) async {
    final record = await _records.read(articleId);
    if (record == null || record.tombstoned || record.owners.isEmpty) {
      return 0;
    }
    await _prepareRecord(record, _now().toUtc());
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
    final now = _now().toUtc();
    final records = await _records.listRecords();
    var attempted = 0;
    for (final record in records) {
      if (record.tombstoned || record.owners.isEmpty) continue;
      if (!_hasDueWork(record, now)) continue;
      attempted++;
      try {
        await _prepareRecord(record, now);
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

  Future<void> _prepareRecord(ArticleRecord record, DateTime now) async {
    final id = record.id;

    // 1. Body: full-text upgrade. The RSS body is kept when extraction fails.
    if (record.bodyState != MediaState.ready && record.link.isNotEmpty) {
      final retryDue =
          record.nextRetryAt == null || !record.nextRetryAt!.isAfter(now);
      if (retryDue) {
        String? html;
        try {
          html = await _extract(record.link);
        } catch (_) {}
        await _records.mutate(id, (current) {
          if (current == null || current.tombstoned) return current;
          if (current.owners.isEmpty) return current;
          // A slower overlapping pass that already succeeded never gets
          // downgraded by this one's failure.
          if (current.bodyState == MediaState.ready) return current;
          if (html != null && html.isNotEmpty) {
            final newImages = _bodyImageUrls(
              html,
            ).where((u) => !current.media.containsKey(u)).toList();
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
          final attempts = current.attempts + 1;
          return current.copyWith(
            bodyState: MediaState.failed,
            attempts: attempts,
            nextRetryAt: () => now.add(backoffFor(attempts)),
          );
        });
      }
    }

    // 2. Media: every due non-ready piece gets at most one attempt this pass.
    final fresh = await _records.read(id);
    if (fresh == null || fresh.tombstoned || fresh.owners.isEmpty) return;
    final pending = <MapEntry<String, MediaEntry>>[
      for (final e in fresh.media.entries)
        if (e.value.state != MediaState.ready &&
            e.value.state != MediaState.gone &&
            (e.value.nextRetryAt == null || !e.value.nextRetryAt!.isAfter(now)))
          e,
    ];
    await Future.wait([
      for (final piece in pending) _preparePiece(id, piece.key, now),
    ]);
  }

  Future<void> _preparePiece(String id, String url, DateTime now) async {
    await _semaphore.acquire();
    try {
      final outcome = await _fetchAndStore(url, now);
      await _records.mutate(id, (current) {
        if (current == null || current.tombstoned) return current;
        if (current.owners.isEmpty) return current;
        final existing = current.media[url];
        if (existing == null) return current;
        // Never downgrade a piece another pass already completed.
        if (existing.state == MediaState.ready) return current;
        // A permanent failure is fenced too: a racing pass's transient
        // failure must not resurrect it into the retry cycle.
        if (existing.state == MediaState.gone && outcome.ready == null) {
          return current;
        }
        final attempts = existing.attempts + 1;
        final media = {...current.media};
        if (outcome.ready != null) {
          media[url] = outcome.ready!.copyWith(attempts: attempts);
        } else if (outcome.gone) {
          media[url] = existing.copyWith(
            state: MediaState.gone,
            attempts: attempts,
          );
        } else {
          // The later of doubling backoff and server Retry-After wins —
          // a manual retry must not bypass a 429 wait either. A stored
          // (possibly longer, e.g. Retry-After) wait is never shortened.
          var retryAt = now.add(backoffFor(attempts));
          final server = outcome.retryAfter;
          if (server != null && server.isAfter(retryAt)) retryAt = server;
          final stored = existing.nextRetryAt;
          if (stored != null && stored.isAfter(retryAt)) retryAt = stored;
          media[url] = existing.copyWith(
            state: MediaState.failed,
            attempts: attempts,
            nextRetryAt: () => retryAt,
          );
        }
        return current.copyWith(media: media);
      });
    } finally {
      _semaphore.release();
    }
  }

  /// Downloads [url] into the media pool. Returns the ready manifest entry
  /// on success; [gone] for permanent failures (404/410, non-image payload,
  /// oversize) that must never be retried; [retryAfter] carries the server's
  /// hint for transient failures.
  Future<({MediaEntry? ready, DateTime? retryAfter, bool gone})> _fetchAndStore(
    String url,
    DateTime now,
  ) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {'User-Agent': 'Mozilla/5.0 (compatible; Dondurma RSS)'},
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final type = response.headers['content-type'] ?? '';
        if ((type.isNotEmpty && !type.startsWith('image/')) ||
            response.bodyBytes.length > maxMediaBytes) {
          // Soft-404 HTML / captive portal / oversize — structural, not
          // transient: retrying would fetch the same non-image forever.
          return (ready: null, retryAfter: null, gone: true);
        }
        return (
          ready: await _media.put(url, response.bodyBytes),
          retryAfter: null,
          gone: false,
        );
      }
      return (
        ready: null,
        retryAfter: _parseRetryAfter(response.headers['retry-after'], now),
        gone: response.statusCode == 404 || response.statusCode == 410,
      );
    } catch (_) {
      return (ready: null, retryAfter: null, gone: false);
    }
  }
}
