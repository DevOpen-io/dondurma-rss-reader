import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/feed_item.dart';
import 'article_identity.dart';
import 'observed_article_persistence.dart';
import 'observed_article_persistence_stub.dart'
    if (dart.library.io) 'observed_article_persistence_io.dart'
    as persistence_factory;

/// [gone] marks a permanently failed piece (404/410, non-image payload,
/// oversize) — durable, never retried automatically.
enum MediaState { pending, ready, failed, gone }

/// Outcome of a mutation on [ArticleRecordStore]: [applied] the write
/// landed, [rejected] the fence or contract refused it (drop the write),
/// [failed] the lock timed out, storage errored, or persisted state was
/// undecodable (retry later is reasonable — nothing was written).
enum StoreWriteResult { applied, rejected, failed }

/// One downloaded media artifact referenced by an article record's manifest.
class MediaEntry {
  const MediaEntry({
    required this.file,
    required this.byteSize,
    required this.state,
    this.attempts = 0,
    this.nextRetryAt,
    this.waitSource,
  });

  factory MediaEntry.fromJson(Map<String, dynamic> json) => MediaEntry(
    file: json['file'] as String? ?? '',
    byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
    state: MediaState.values.asNameMap()[json['state']] ?? MediaState.pending,
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    nextRetryAt: DateTime.tryParse(
      json['nextRetryAt'] as String? ?? '',
    )?.toUtc(),
    waitSource: json['waitSource'] as String?,
  );

  /// File name inside the shared media pool (never a path).
  final String file;
  final int byteSize;
  final MediaState state;

  /// Preparation attempts so far — each piece is tried at most once per pass.
  final int attempts;

  /// Earliest time this piece may be retried (server `Retry-After` wins).
  final DateTime? nextRetryAt;

  /// What set [nextRetryAt]: `'server'` when a `Retry-After` header drove
  /// the wait (a manual retry must not bypass it), `'backoff'` for the
  /// local doubling backoff (manual retry may bypass). `null` marks a
  /// legacy wait of unknown origin — protected like a server wait.
  final String? waitSource;

  MediaEntry copyWith({
    String? file,
    int? byteSize,
    MediaState? state,
    int? attempts,
    DateTime? Function()? nextRetryAt,
    String? Function()? waitSource,
  }) => MediaEntry(
    file: file ?? this.file,
    byteSize: byteSize ?? this.byteSize,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextRetryAt: nextRetryAt != null ? nextRetryAt() : this.nextRetryAt,
    waitSource: waitSource != null ? waitSource() : this.waitSource,
  );

  Map<String, dynamic> toJson() => {
    'file': file,
    'byteSize': byteSize,
    'state': state.name,
    'attempts': attempts,
    'nextRetryAt': nextRetryAt?.toIso8601String(),
    'waitSource': waitSource,
  };
}

/// Durable per-article record: the saved content snapshot, its media
/// manifest, ownership references, retry schedule, and the generation fence
/// that stops stale in-flight writes from resurrecting deleted records.
class ArticleRecord {
  const ArticleRecord({
    required this.id,
    required this.feedUrl,
    this.link = '',
    this.title,
    this.siteName,
    this.body,
    this.bodyState = MediaState.pending,
    this.bodySource,
    this.publishedAt,
    this.savedAt,
    this.imageUrls = const [],
    this.media = const {},
    this.owners = const {},
    this.attempts = 0,
    this.nextRetryAt,
    this.generation = 0,
    this.tombstoned = false,
  });

  factory ArticleRecord.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['media'];
    final rawOwners = json['owners'];
    final rawImages = json['imageUrls'];
    // Ownership/manifest fields that exist but carry a wrong type are
    // corruption, not absence — decoding them as empty would silently
    // strip claims and let GC free bytes it can't prove unreferenced.
    if (rawMedia != null && rawMedia is! Map) {
      throw const FormatException('media must be a map');
    }
    if (rawOwners != null && rawOwners is! List) {
      throw const FormatException('owners must be a list');
    }
    if (rawImages != null && rawImages is! List) {
      throw const FormatException('imageUrls must be a list');
    }
    final media = <String, MediaEntry>{};
    if (rawMedia is Map) {
      for (final entry in rawMedia.entries) {
        final value = entry.value;
        if (value is Map) {
          media[entry.key.toString()] = MediaEntry.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      }
    }
    return ArticleRecord(
      id: json['id'] as String? ?? '',
      feedUrl: json['feedUrl'] as String? ?? '',
      link: json['link'] as String? ?? '',
      title: json['title'] as String?,
      siteName: json['siteName'] as String?,
      body: json['body'] as String?,
      bodyState:
          MediaState.values.asNameMap()[json['bodyState']] ??
          MediaState.pending,
      bodySource: json['bodySource'] as String?,
      publishedAt: DateTime.tryParse(
        json['publishedAt'] as String? ?? '',
      )?.toUtc(),
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '')?.toUtc(),
      imageUrls:
          (rawImages as List?)?.map((e) => e.toString()).toList() ?? const [],
      media: media,
      owners:
          (rawOwners as List?)?.map((e) => e.toString()).toSet() ?? const {},
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextRetryAt: DateTime.tryParse(
        json['nextRetryAt'] as String? ?? '',
      )?.toUtc(),
      generation: (json['generation'] as num?)?.toInt() ?? 0,
      tombstoned: json['tombstoned'] as bool? ?? false,
    );
  }

  /// Normalized article id (see [ArticleIdentity.normalizeItemId]).
  final String id;
  final String feedUrl;

  /// The article's page URL — the target for full-text extraction.
  final String link;
  final String? title;
  final String? siteName;

  /// Best saved body — extracted full text when available, else the RSS body.
  final String? body;
  final MediaState bodyState;

  /// Provenance of [body]: `'rss'` (feed body) or `'extracted'` (full-text
  /// result). Lets a full-text preference flip re-pend only records whose
  /// ready body was never extracted — absent in older records, where it
  /// reads as `'rss'` and costs at most one re-extraction.
  final String? bodySource;
  final DateTime? publishedAt;
  final DateTime? savedAt;
  final List<String> imageUrls;

  /// Image url -> downloaded file entry in the shared media pool.
  final Map<String, MediaEntry> media;

  /// 'bookmark' | 'tempCache' | 'reader' — whoever still needs this record.
  final Set<String> owners;

  /// Whole-article preparation attempts — drives the 1→2→4…→60min backoff.
  final int attempts;

  /// Earliest time this article may be prepared again.
  final DateTime? nextRetryAt;
  final int generation;

  /// Tombstoned records fence off stale writes and carry no content.
  final bool tombstoned;

  ArticleRecord copyWith({
    String? id,
    String? feedUrl,
    String? link,
    String? Function()? title,
    String? Function()? siteName,
    String? Function()? body,
    MediaState? bodyState,
    String? Function()? bodySource,
    DateTime? Function()? publishedAt,
    DateTime? Function()? savedAt,
    List<String>? imageUrls,
    Map<String, MediaEntry>? media,
    Set<String>? owners,
    int? attempts,
    DateTime? Function()? nextRetryAt,
    int? generation,
    bool? tombstoned,
  }) => ArticleRecord(
    id: id ?? this.id,
    feedUrl: feedUrl ?? this.feedUrl,
    link: link ?? this.link,
    title: title != null ? title() : this.title,
    siteName: siteName != null ? siteName() : this.siteName,
    body: body != null ? body() : this.body,
    bodyState: bodyState ?? this.bodyState,
    bodySource: bodySource != null ? bodySource() : this.bodySource,
    publishedAt: publishedAt != null ? publishedAt() : this.publishedAt,
    savedAt: savedAt != null ? savedAt() : this.savedAt,
    imageUrls: imageUrls ?? this.imageUrls,
    media: media ?? this.media,
    owners: owners ?? this.owners,
    attempts: attempts ?? this.attempts,
    nextRetryAt: nextRetryAt != null ? nextRetryAt() : this.nextRetryAt,
    generation: generation ?? this.generation,
    tombstoned: tombstoned ?? this.tombstoned,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'feedUrl': feedUrl,
    'link': link,
    'title': title,
    'siteName': siteName,
    'body': body,
    'bodyState': bodyState.name,
    'bodySource': bodySource,
    'publishedAt': publishedAt?.toIso8601String(),
    'savedAt': savedAt?.toIso8601String(),
    'imageUrls': imageUrls,
    'media': media.map((key, value) => MapEntry(key, value.toJson())),
    'owners': owners.toList(),
    'attempts': attempts,
    'nextRetryAt': nextRetryAt?.toIso8601String(),
    'generation': generation,
    'tombstoned': tombstoned,
  };
}

/// Persists [ArticleRecord]s and per-instance first-seen timestamps in a
/// lock-file-serialized JSON sidecar next to the `'feeds'` Hive box — the
/// same proven mechanism [ObservedArticleStore] uses, because a shared Hive
/// box cannot arbitrate writes between the foreground and Workmanager
/// isolates (each keeps its own in-memory keystore).
///
/// Schema 2 keys every record by its source instance ([ArticleRef]), so two
/// feeds sharing a GUID never share a record. It lives in its own file; the
/// schema-1 archive (global ids) is migration input only, read under this
/// store's lock the first time schema 2 is absent, and never rewritten
/// except by [wipeAll]. A legacy record is re-keyed only when exactly one
/// known instance (cached items + bookmark snapshots) carries its id and its
/// stored feed agrees; everything else is quarantined — bytes and manifest
/// kept (media stays referenced), never shown as an instance's offline copy.
class ArticleRecordStore {
  ArticleRecordStore(
    this._persistence, {
    ObservedArticlePersistence? legacy,
    Iterable<FeedItem> Function()? knownInstances,
  }) : _legacy = legacy,
       _knownInstances = knownInstances;

  ArticleRecordStore.forBox(Box box)
    : this(
        persistence_factory.createObservedArticlePersistence(
          box,
          fileSuffix: '.article-archive.v2.json',
        ),
        legacy: persistence_factory.createObservedArticlePersistence(
          box,
          fileSuffix: '.article-archive.json',
        ),
        knownInstances: () => _knownInstancesFor(box),
      );

  static const int schemaVersion = 2;
  static const int legacySchemaVersion = 1;

  final ObservedArticlePersistence _persistence;
  final ObservedArticlePersistence? _legacy;
  final Iterable<FeedItem> Function()? _knownInstances;

  /// Instances the app can currently show: the cache snapshot and the
  /// bookmark snapshots. Corrupt payloads contribute nothing.
  static Iterable<FeedItem> _knownInstancesFor(Box feeds) sync* {
    Iterable<FeedItem> decode(Object? raw) sync* {
      if (raw is! String || raw.isEmpty) return;
      try {
        for (final entry in jsonDecode(raw) as List) {
          yield FeedItem.fromJson(Map<String, dynamic>.from(entry as Map));
        }
      } catch (_) {}
    }

    yield* decode(feeds.get('cachedItemsJson'));
    if (Hive.isBoxOpen('bookmarks')) {
      yield* decode(Hive.box('bookmarks').get('bookmarkedItemsJson'));
    }
  }

  static Map<String, dynamic> _empty(int epoch) => {
    'schema': schemaVersion,
    'records': <String, dynamic>{},
    'seen': <String, dynamic>{},
    'quarantine': <String, dynamic>{},
    'epoch': epoch,
  };

  /// Decodes persisted state of [schema]. Returns null when the content is
  /// undecodable or foreign — mutations must refuse to overwrite it rather
  /// than destroy unknown user data. A container of the wrong type also
  /// fails closed: coercing it to empty would let a GC pass "prove" every
  /// file unreferenced (#40 fail-closed).
  static Map<String, dynamic>? _tryDecode(String? raw, {int? schema}) {
    if (raw == null || raw.isEmpty) return null;
    final expected = schema ?? schemaVersion;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['schema'] == expected) {
        for (final key in const ['records', 'seen', 'quarantine']) {
          if (decoded.containsKey(key) && decoded[key] is! Map) {
            return null;
          }
        }
        Map<String, dynamic> map(String key) => decoded[key] is Map
            ? Map<String, dynamic>.from(decoded[key] as Map)
            : <String, dynamic>{};
        return {
          'schema': expected,
          'records': map('records'),
          'seen': map('seen'),
          'quarantine': map('quarantine'),
          'epoch': decoded['epoch'] is int ? decoded['epoch'] as int : 0,
        };
      }
    } catch (_) {}
    return null;
  }

  static int _epochOf(Map<String, dynamic> state) =>
      state['epoch'] is int ? state['epoch'] as int : 0;

  /// Schema-2 state derived from the legacy archive; null when the legacy
  /// file exists but is undecodable (fail closed, migrate nothing).
  Future<Map<String, dynamic>?> _migratedState() async {
    final raw = await _legacy?.read();
    if (raw == null || raw.isEmpty) return _empty(0);
    final legacy = _tryDecode(raw, schema: legacySchemaVersion);
    if (legacy == null) return null;
    final feedsById = <String, Set<String>>{};
    for (final item in _knownInstances?.call() ?? const <FeedItem>[]) {
      final ref = ArticleRef.of(item);
      (feedsById[ref.id] ??= {}).add(ref.feedUrl);
    }
    final state = _empty(_epochOf(legacy));
    final records = state['records'] as Map<String, dynamic>;
    final quarantine = state['quarantine'] as Map<String, dynamic>;
    for (final MapEntry(key: legacyId, :value)
        in (legacy['records'] as Map<String, dynamic>).entries) {
      ArticleRecord? record;
      if (value is Map) {
        try {
          record = ArticleRecord.fromJson(Map<String, dynamic>.from(value));
        } catch (_) {}
      }
      // A legacy tombstone fenced writers of the global key; nothing in
      // schema 2 writes that key, so the fence has no subject left.
      if (record != null && record.tombstoned) continue;
      final feeds = feedsById[legacyId] ?? const <String>{};
      if (record != null &&
          feeds.length == 1 &&
          feeds.single == record.feedUrl) {
        final ref = ArticleRef(record.feedUrl, legacyId);
        records[ref.key] = record.copyWith(id: ref.id).toJson();
      } else {
        quarantine[legacyId] = value;
      }
    }
    // Ambiguous stamps go to every known instance — the conservative side:
    // nothing already observed reads as new again.
    final seen = state['seen'] as Map<String, dynamic>;
    for (final MapEntry(key: legacyId, :value)
        in (legacy['seen'] as Map<String, dynamic>).entries) {
      for (final feed in feedsById[legacyId] ?? const <String>{}) {
        seen[ArticleRef(feed, legacyId).key] = value;
      }
    }
    return state;
  }

  /// State for a mutation, inside the lock: the schema-2 file, else the
  /// migrated legacy archive, else empty. Null when stored content cannot
  /// be decoded (fail closed — never rewrite blindly).
  Future<Map<String, dynamic>?> _stateForMutation() async {
    final raw = await _persistence.read();
    if (raw == null || raw.isEmpty) return _migratedState();
    return _decode(raw);
  }

  /// The last file text this store decoded, and its state. Every access
  /// still reads the file — another isolate may have written it — but a
  /// byte-identical text skips `jsonDecode`, which for an archive carrying
  /// article bodies was the main cost of each read and of every member a
  /// reconcile pass re-registers.
  String? _decodedRaw;
  Map<String, dynamic>? _decodedState;

  /// Decoded state of [raw] as a private copy: writers replace entries of
  /// the top-level maps (never edit a record's map in place), so copying
  /// those maps keeps the reused state untouched.
  Map<String, dynamic>? _decode(String raw) {
    if (raw != _decodedRaw) {
      _decodedState = _tryDecode(raw);
      _decodedRaw = raw;
    }
    final state = _decodedState;
    return state == null ? null : _copyState(state);
  }

  static Map<String, dynamic> _copyState(Map<String, dynamic> state) => {
    ...state,
    for (final key in const ['records', 'seen', 'quarantine'])
      key: Map<String, dynamic>.of(state[key] as Map<String, dynamic>),
  };

  /// Persists [state]; the written text becomes the reusable decode.
  Future<void> _writeState(Map<String, dynamic> state) async {
    final raw = jsonEncode(state);
    await _persistence.write(raw);
    _decodedRaw = raw;
    _decodedState = _copyState(state);
  }

  /// Lock-free read view. When schema 2 is absent but a legacy archive
  /// exists, the migration is persisted under the lock first, so every
  /// reader and writer agrees on one mapping. Null when undecodable.
  Future<Map<String, dynamic>?> _readState() async {
    final raw = await _persistence.read();
    if (raw != null && raw.isNotEmpty) return _decode(raw);
    final legacy = await _legacy?.read();
    if (legacy == null || legacy.isEmpty) return _empty(0);
    final result = await _persistence.runExclusive(() async {
      final current = await _persistence.read();
      if (current != null && current.isNotEmpty) return _decode(current);
      final migrated = await _migratedState();
      if (migrated != null) await _writeState(migrated);
      return migrated;
    });
    return result.acquired ? result.value : null;
  }

  static ArticleRecord? _decodeRecord(
    Map<String, dynamic> state,
    ArticleRef ref,
  ) {
    final raw = state['records'][ref.key];
    if (raw is! Map) return null;
    try {
      return ArticleRecord.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      // Corrupt records read as missing rather than crashing callers.
      return null;
    }
  }

  /// Advisory snapshot — callers that write must re-check inside
  /// [writeIfGeneration]/[mutate]; this read is not a consistent base.
  /// Fails closed (returns `null`) on storage errors so unawaited callers
  /// never surface an async exception.
  Future<ArticleRecord?> read(ArticleRef ref) async {
    try {
      final state = await _readState();
      return state == null ? null : _decodeRecord(state, ref);
    } catch (_) {
      return null;
    }
  }

  /// Current lifecycle epoch — bumped by [wipeAll]. Units of work capture
  /// this once and pass it as `expectedEpoch` to mutations so nothing
  /// started before a reset can write after it.
  Future<int> currentEpoch() async {
    try {
      final state = await _readState();
      return state == null ? 0 : _epochOf(state);
    } catch (_) {
      return 0;
    }
  }

  /// GC-facing snapshot: live records, quarantined legacy records (their
  /// media stays referenced) and whether the read was fully clean.
  /// `clean == false` means the state was undecodable or an entry was
  /// skipped — a cleanup pass must then treat "unreferenced" as "unknown"
  /// and delete nothing (#40).
  Future<
    ({List<ArticleRecord> records, List<ArticleRecord> quarantine, bool clean})
  >
  listRecordsForGc() async {
    const unclean = (
      records: <ArticleRecord>[],
      quarantine: <ArticleRecord>[],
      clean: false,
    );
    final Map<String, dynamic>? state;
    try {
      state = await _readState();
    } catch (_) {
      return unclean;
    }
    if (state == null) return unclean;
    var clean = true;
    List<ArticleRecord> decodeAll(String key) {
      final result = <ArticleRecord>[];
      for (final raw in (state![key] as Map).values) {
        if (raw is Map) {
          try {
            result.add(ArticleRecord.fromJson(Map<String, dynamic>.from(raw)));
          } catch (_) {
            clean = false;
          }
        } else {
          clean = false;
        }
      }
      return result;
    }

    final records = decodeAll('records');
    final quarantine = decodeAll('quarantine');
    return (records: records, quarantine: quarantine, clean: clean);
  }

  /// Every decodable live record. Corrupt entries are skipped — callers
  /// doing media GC must treat "absent here" as "unknown", not "safe to
  /// delete". Fails closed (returns empty) on storage errors.
  Future<List<ArticleRecord>> listRecords() async {
    final Map<String, dynamic>? state;
    try {
      state = await _readState();
    } catch (_) {
      return const [];
    }
    if (state == null) return const [];
    final records = <ArticleRecord>[];
    for (final raw in (state['records'] as Map).values) {
      if (raw is Map) {
        try {
          records.add(ArticleRecord.fromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {}
      }
    }
    return records;
  }

  /// Atomically replaces the record of [ref] with [update]'s result inside
  /// the write lock. Returning `null` deletes the record; returning the
  /// unchanged [ArticleRecord] instance skips the write. The stored payload
  /// is coerced to [ref]'s identity so key and payload never diverge.
  ///
  /// [expectedEpoch] fences a unit of work against [wipeAll]: callers capture
  /// [currentEpoch] before starting, and any mutation landing after a reset
  /// sees a different epoch and is rejected — a reset can never resurrect a
  /// record through a queued write.
  Future<StoreWriteResult> mutate(
    ArticleRef ref,
    ArticleRecord? Function(ArticleRecord? current) update, {
    int? expectedEpoch,
  }) async {
    if (ref.id.isEmpty) return StoreWriteResult.rejected;
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        if (expectedEpoch != null && _epochOf(state) != expectedEpoch) {
          return StoreWriteResult.rejected;
        }
        final current = _decodeRecord(state, ref);
        final next = update(current);
        if (identical(next, current)) return StoreWriteResult.applied;
        final records = state['records'] as Map<String, dynamic>;
        if (next == null) {
          records.remove(ref.key);
        } else {
          records[ref.key] = next
              .copyWith(id: ref.id, feedUrl: ref.feedUrl)
              .toJson();
        }
        await _writeState(state);
        return StoreWriteResult.applied;
      });
      return result.acquired ? result.value! : StoreWriteResult.failed;
    } catch (_) {
      return StoreWriteResult.failed;
    }
  }

  static ArticleRef _refOf(ArticleRecord record) =>
      ArticleRef(record.feedUrl, record.id);

  /// Writes a live record; refuses to overwrite a tombstone — re-creating a
  /// deleted record is a lifecycle transition and must go through [revive].
  Future<StoreWriteResult> write(ArticleRecord record) async {
    var refused = false;
    final result = await mutate(_refOf(record), (current) {
      if (current?.tombstoned == true) {
        refused = true;
        return current;
      }
      return record;
    });
    return result == StoreWriteResult.applied && refused
        ? StoreWriteResult.rejected
        : result;
  }

  /// Re-creates [record] after a tombstone by continuing the generation
  /// sequence, so stale writes fenced to the old generation still lose.
  Future<StoreWriteResult> revive(ArticleRecord record) => mutate(
    _refOf(record),
    (current) => record.copyWith(generation: (current?.generation ?? 0) + 1),
  );

  /// Compare-and-swap: applies [record] only when the stored record exists,
  /// is not tombstoned, still carries [expectedGeneration], and [record]
  /// itself carries that same generation (a generation change is a lifecycle
  /// transition, not a content write). [rejected] means the fence refused;
  /// [failed] means nothing was decided (lock/IO/undecodable state).
  Future<StoreWriteResult> writeIfGeneration(
    ArticleRecord record,
    int expectedGeneration,
  ) async {
    final ref = _refOf(record);
    if (ref.id.isEmpty || record.generation != expectedGeneration) {
      return StoreWriteResult.rejected;
    }
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        final current = _decodeRecord(state, ref);
        if (current == null || current.tombstoned) {
          return StoreWriteResult.rejected;
        }
        if (current.generation != expectedGeneration) {
          return StoreWriteResult.rejected;
        }
        (state['records'] as Map<String, dynamic>)[ref.key] = record
            .copyWith(id: ref.id)
            .toJson();
        await _writeState(state);
        return StoreWriteResult.applied;
      });
      return result.acquired ? result.value! : StoreWriteResult.failed;
    } catch (_) {
      return StoreWriteResult.failed;
    }
  }

  /// Fences [ref] off: content is dropped, generation bumped, and later
  /// generation-checked writes are rejected. Tombstoning a never-existing
  /// instance still records the fence.
  Future<StoreWriteResult> tombstone(ArticleRef ref, {int? expectedEpoch}) =>
      mutate(
        ref,
        expectedEpoch: expectedEpoch,
        (current) => ArticleRecord(
          id: ref.id,
          feedUrl: ref.feedUrl,
          generation: (current?.generation ?? 0) + 1,
          tombstoned: true,
        ),
      );

  Future<bool> isTombstoned(ArticleRef ref) async =>
      (await read(ref))?.tombstoned ?? false;

  /// Hard-deletes the record only (media GC and firstSeen pruning are
  /// separate lifecycle concerns).
  Future<StoreWriteResult> deleteRecord(ArticleRef ref) =>
      mutate(ref, (_) => null);

  /// Records the earliest first-observation of [ref] inside the write lock;
  /// later observations never overwrite the earliest stored value. Intended
  /// for archived candidates — the `seen` map is not pruned here, so callers
  /// must not stamp every article in every sync.
  Future<StoreWriteResult> recordFirstSeen(
    ArticleRef ref,
    DateTime observedAt, {
    int? expectedEpoch,
  }) async {
    if (ref.id.isEmpty) return StoreWriteResult.rejected;
    final at = observedAt.toUtc();
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        if (expectedEpoch != null && _epochOf(state) != expectedEpoch) {
          return StoreWriteResult.rejected;
        }
        final seen = state['seen'] as Map<String, dynamic>;
        final raw = seen[ref.key];
        final existing = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
        if (existing == null || existing.isAfter(at)) {
          seen[ref.key] = at.toIso8601String();
          await _writeState(state);
        }
        return StoreWriteResult.applied;
      });
      return result.acquired ? result.value! : StoreWriteResult.failed;
    } catch (_) {
      return StoreWriteResult.failed;
    }
  }

  Future<DateTime?> firstSeen(ArticleRef ref) async {
    try {
      final state = await _readState();
      final raw = (state?['seen'] as Map?)?[ref.key];
      return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    } catch (_) {
      return null;
    }
  }

  /// Snapshot of every recorded first-observation time, keyed by
  /// [ArticleRef] — one storage read for callers that sort many candidates
  /// at once (temp-cache selection).
  Future<Map<ArticleRef, DateTime>> allFirstSeen() async {
    try {
      final state = await _readState();
      if (state == null) return const {};
      final result = <ArticleRef, DateTime>{};
      for (final entry in (state['seen'] as Map).entries) {
        final ref = entry.key is String
            ? ArticleRef.tryParse(entry.key as String)
            : null;
        final value = entry.value;
        if (ref != null && value is String) {
          final parsed = DateTime.tryParse(value);
          if (parsed != null) result[ref] = parsed.toUtc();
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<StoreWriteResult> deleteFirstSeen(
    ArticleRef ref, {
    int? expectedEpoch,
  }) async {
    if (ref.id.isEmpty) return StoreWriteResult.rejected;
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        if (expectedEpoch != null && _epochOf(state) != expectedEpoch) {
          return StoreWriteResult.rejected;
        }
        final seen = state['seen'] as Map<String, dynamic>;
        if (!seen.containsKey(ref.key)) return StoreWriteResult.applied;
        seen.remove(ref.key);
        await _writeState(state);
        return StoreWriteResult.applied;
      });
      return result.acquired ? result.value! : StoreWriteResult.failed;
    } catch (_) {
      return StoreWriteResult.failed;
    }
  }

  /// Bumps the lifecycle epoch without touching records — the clearCache
  /// fence: any fenced write captured before the bump is rejected, so a
  /// background-isolate registration in flight during the clear cannot
  /// re-add an owner the strip just removed (#40 §1 cross-isolate case).
  /// Records and stamps stay exactly as they were.
  Future<bool> bumpEpoch() async {
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return false;
        state['epoch'] = _nextEpoch(_epochOf(state));
        await _writeState(state);
        return true;
      });
      return result.acquired && (result.value ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Next epoch value: a timestamp beats every fence captured from any
  /// past era, but never regresses below `previous + 1` — two writes in
  /// the same microsecond must not tie and let a stale fence pass.
  static int _nextEpoch(int previous) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return now > previous ? now : previous + 1;
  }

  /// Wipes every record, quarantined legacy record and observation stamp —
  /// the factory-reset path — including the legacy archive, which holds
  /// personal data too. Orphaned media files left behind are the S5 sweep's
  /// job. The lifecycle epoch is bumped so writes carrying a pre-reset fence
  /// are rejected instead of resurrecting content.
  ///
  /// Returns `false` when the lock/write could not be completed even after
  /// one retry — the caller must not report a reset it couldn't enforce.
  Future<bool> wipeAll() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _persistence.runExclusive(() async {
          // A timestamp, not a counter: the pre-wipe state may be corrupt
          // or absent, and any fence captured from it must still lose —
          // only a monotonically fresh value guarantees that.
          int epochIn(String? raw, int schema) {
            final decoded = _tryDecode(raw, schema: schema);
            return decoded == null ? 0 : _epochOf(decoded);
          }

          final legacy = _legacy;
          final legacyRaw = await legacy?.read();
          final previous = [
            epochIn(await _persistence.read(), schemaVersion),
            epochIn(legacyRaw, legacySchemaVersion),
          ].reduce((a, b) => a > b ? a : b);
          await _persistence.write(jsonEncode(_empty(_nextEpoch(previous))));
          if (legacy != null && legacyRaw != null && legacyRaw.isNotEmpty) {
            await legacy.write(
              jsonEncode({
                'schema': legacySchemaVersion,
                'records': <String, dynamic>{},
                'seen': <String, dynamic>{},
                'epoch': 0,
              }),
            );
          }
          return true;
        });
        if (result.acquired) return result.value ?? false;
      } catch (_) {
        // Retry once below; a second failure reports honestly.
      }
    }
    return false;
  }
}
