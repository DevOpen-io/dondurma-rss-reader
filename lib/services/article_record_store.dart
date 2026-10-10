import 'dart:convert';

import 'package:hive_ce/hive.dart';

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
  });

  factory MediaEntry.fromJson(Map<String, dynamic> json) => MediaEntry(
    file: json['file'] as String? ?? '',
    byteSize: (json['byteSize'] as num?)?.toInt() ?? 0,
    state: MediaState.values.asNameMap()[json['state']] ?? MediaState.pending,
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    nextRetryAt: DateTime.tryParse(
      json['nextRetryAt'] as String? ?? '',
    )?.toUtc(),
  );

  /// File name inside the shared media pool (never a path).
  final String file;
  final int byteSize;
  final MediaState state;

  /// Preparation attempts so far — each piece is tried at most once per pass.
  final int attempts;

  /// Earliest time this piece may be retried (server `Retry-After` wins).
  final DateTime? nextRetryAt;

  MediaEntry copyWith({
    String? file,
    int? byteSize,
    MediaState? state,
    int? attempts,
    DateTime? Function()? nextRetryAt,
  }) => MediaEntry(
    file: file ?? this.file,
    byteSize: byteSize ?? this.byteSize,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextRetryAt: nextRetryAt != null ? nextRetryAt() : this.nextRetryAt,
  );

  Map<String, dynamic> toJson() => {
    'file': file,
    'byteSize': byteSize,
    'state': state.name,
    'attempts': attempts,
    'nextRetryAt': nextRetryAt?.toIso8601String(),
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

/// Persists [ArticleRecord]s and per-article first-seen timestamps in a
/// lock-file-serialized JSON sidecar next to the `'feeds'` Hive box — the
/// same proven mechanism [ObservedArticleStore] uses, because a shared Hive
/// box cannot arbitrate writes between the foreground and Workmanager
/// isolates (each keeps its own in-memory keystore).
class ArticleRecordStore {
  ArticleRecordStore(this._persistence);

  ArticleRecordStore.forBox(Box box)
    : this(
        persistence_factory.createObservedArticlePersistence(
          box,
          fileSuffix: '.article-archive.json',
        ),
      );

  static const int schemaVersion = 1;

  final ObservedArticlePersistence _persistence;

  static String _norm(String id) => ArticleIdentity.normalizeItemId(id) ?? id;

  static const Map<String, dynamic> _emptyState = {
    'records': <String, dynamic>{},
    'seen': <String, dynamic>{},
    'epoch': 0,
  };

  /// Decodes persisted state. Returns null when the file holds non-empty but
  /// undecodable or foreign-schema content — mutations must refuse to
  /// overwrite it rather than destroy unknown user data. A `records`/`seen`
  /// container of the wrong type also fails closed: coercing it to empty
  /// would let a GC pass "prove" every file unreferenced (#40 fail-closed).
  Map<String, dynamic>? _tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['schema'] == schemaVersion) {
        for (final key in const ['records', 'seen']) {
          if (decoded.containsKey(key) && decoded[key] is! Map) {
            return null;
          }
        }
        return {
          'schema': schemaVersion,
          'records': decoded['records'] is Map
              ? Map<String, dynamic>.from(decoded['records'] as Map)
              : <String, dynamic>{},
          'seen': decoded['seen'] is Map
              ? Map<String, dynamic>.from(decoded['seen'] as Map)
              : <String, dynamic>{},
          'epoch': decoded['epoch'] is int ? decoded['epoch'] as int : 0,
        };
      }
    } catch (_) {}
    return null;
  }

  static int _epochOf(Map<String, dynamic> state) =>
      state['epoch'] is int ? state['epoch'] as int : 0;

  /// State for a mutation: empty when the file is absent, null when the file
  /// exists but cannot be decoded (fail closed — never rewrite blindly).
  Future<Map<String, dynamic>?> _stateForMutation() async {
    final raw = await _persistence.read();
    if (raw == null || raw.isEmpty) {
      return {
        'schema': schemaVersion,
        'records': <String, dynamic>{},
        'seen': <String, dynamic>{},
        'epoch': 0,
      };
    }
    return _tryDecode(raw);
  }

  ArticleRecord? _decodeRecord(Map<String, dynamic> state, String id) {
    final raw = state['records'][_norm(id)];
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
  Future<ArticleRecord?> read(String id) async {
    try {
      final state = _tryDecode(await _persistence.read()) ?? _emptyState;
      return _decodeRecord(state, id);
    } catch (_) {
      return null;
    }
  }

  /// Current lifecycle epoch — bumped by [wipeAll]. Units of work capture
  /// this once and pass it as `expectedEpoch` to mutations so nothing
  /// started before a reset can write after it.
  Future<int> currentEpoch() async {
    try {
      final state = _tryDecode(await _persistence.read()) ?? _emptyState;
      return _epochOf(state);
    } catch (_) {
      return 0;
    }
  }

  /// GC-facing snapshot: the decodable records plus whether the read was
  /// fully clean. `clean == false` means the state was undecodable or at
  /// least one record entry was skipped — a cleanup pass must then treat
  /// "unreferenced" as "unknown" and delete nothing (#40).
  Future<({List<ArticleRecord> records, bool clean})> listRecordsForGc() async {
    final Map<String, dynamic> state;
    try {
      final raw = await _persistence.read();
      final decoded = _tryDecode(raw);
      if (raw != null && raw.isNotEmpty && decoded == null) {
        return (records: const <ArticleRecord>[], clean: false);
      }
      state = decoded ?? _emptyState;
    } catch (_) {
      return (records: const <ArticleRecord>[], clean: false);
    }
    var clean = true;
    final records = <ArticleRecord>[];
    for (final raw in (state['records'] as Map).values) {
      if (raw is Map) {
        try {
          records.add(ArticleRecord.fromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {
          clean = false;
        }
      } else {
        clean = false;
      }
    }
    return (records: records, clean: clean);
  }

  /// Every decodable record. Corrupt entries are skipped — callers doing
  /// media GC must treat "absent here" as "unknown", not "safe to delete".
  /// Fails closed (returns empty) on storage errors.
  Future<List<ArticleRecord>> listRecords() async {
    final Map<String, dynamic> state;
    try {
      state = _tryDecode(await _persistence.read()) ?? _emptyState;
    } catch (_) {
      return const [];
    }
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

  /// Atomically replaces the record for [id] with [update]'s result inside
  /// the write lock. Returning `null` deletes the record; returning the
  /// unchanged [ArticleRecord] instance skips the write. The stored id is
  /// coerced to the normalized key so map key and payload never diverge.
  ///
  /// [expectedEpoch] fences a unit of work against [wipeAll]: callers capture
  /// [currentEpoch] before starting, and any mutation landing after a reset
  /// sees a different epoch and is rejected — a reset can never resurrect a
  /// record through a queued write.
  Future<StoreWriteResult> mutate(
    String id,
    ArticleRecord? Function(ArticleRecord? current) update, {
    int? expectedEpoch,
  }) async {
    if (_norm(id).isEmpty) return StoreWriteResult.rejected;
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        if (expectedEpoch != null && _epochOf(state) != expectedEpoch) {
          return StoreWriteResult.rejected;
        }
        final current = _decodeRecord(state, id);
        final next = update(current);
        if (identical(next, current)) return StoreWriteResult.applied;
        final records = state['records'] as Map<String, dynamic>;
        if (next == null) {
          records.remove(_norm(id));
        } else {
          records[_norm(id)] = next.copyWith(id: _norm(id)).toJson();
        }
        await _persistence.write(jsonEncode(state));
        return StoreWriteResult.applied;
      });
      return result.acquired ? result.value! : StoreWriteResult.failed;
    } catch (_) {
      return StoreWriteResult.failed;
    }
  }

  /// Writes a live record; refuses to overwrite a tombstone — re-creating a
  /// deleted record is a lifecycle transition and must go through [revive].
  Future<StoreWriteResult> write(ArticleRecord record) async {
    var refused = false;
    final result = await mutate(record.id, (current) {
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
    record.id,
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
    if (_norm(record.id).isEmpty || record.generation != expectedGeneration) {
      return StoreWriteResult.rejected;
    }
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        final current = _decodeRecord(state, record.id);
        if (current == null || current.tombstoned) {
          return StoreWriteResult.rejected;
        }
        if (current.generation != expectedGeneration) {
          return StoreWriteResult.rejected;
        }
        (state['records'] as Map<String, dynamic>)[_norm(record.id)] = record
            .copyWith(id: _norm(record.id))
            .toJson();
        await _persistence.write(jsonEncode(state));
        return StoreWriteResult.applied;
      });
      return result.acquired ? result.value! : StoreWriteResult.failed;
    } catch (_) {
      return StoreWriteResult.failed;
    }
  }

  /// Fences [id] off: content is dropped, generation bumped, and later
  /// generation-checked writes are rejected. Tombstoning a never-existing id
  /// still records the fence.
  Future<StoreWriteResult> tombstone(String id, {int? expectedEpoch}) => mutate(
    id,
    expectedEpoch: expectedEpoch,
    (current) => ArticleRecord(
      id: _norm(id),
      feedUrl: current?.feedUrl ?? '',
      generation: (current?.generation ?? 0) + 1,
      tombstoned: true,
    ),
  );

  Future<bool> isTombstoned(String id) async =>
      (await read(id))?.tombstoned ?? false;

  /// Hard-deletes the record only (media GC and firstSeen pruning are
  /// separate lifecycle concerns).
  Future<StoreWriteResult> deleteRecord(String id) => mutate(id, (_) => null);

  /// Records the earliest first-observation of [id] inside the write lock;
  /// later observations never overwrite the earliest stored value. Intended
  /// for archived candidates — the `seen` map is not pruned here, so callers
  /// must not stamp every article in every sync.
  Future<StoreWriteResult> recordFirstSeen(
    String id,
    DateTime observedAt, {
    int? expectedEpoch,
  }) async {
    if (_norm(id).isEmpty) return StoreWriteResult.rejected;
    final at = observedAt.toUtc();
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        if (expectedEpoch != null && _epochOf(state) != expectedEpoch) {
          return StoreWriteResult.rejected;
        }
        final seen = state['seen'] as Map<String, dynamic>;
        final raw = seen[_norm(id)];
        final existing = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
        if (existing == null || existing.isAfter(at)) {
          seen[_norm(id)] = at.toIso8601String();
          await _persistence.write(jsonEncode(state));
        }
        return StoreWriteResult.applied;
      });
      return result.acquired ? result.value! : StoreWriteResult.failed;
    } catch (_) {
      return StoreWriteResult.failed;
    }
  }

  Future<DateTime?> firstSeen(String id) async {
    try {
      final state = _tryDecode(await _persistence.read()) ?? _emptyState;
      final raw = (state['seen'] as Map)[_norm(id)];
      return raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
    } catch (_) {
      return null;
    }
  }

  /// Snapshot of every recorded first-observation time — one storage read
  /// for callers that sort many candidates at once (temp-cache selection).
  Future<Map<String, DateTime>> allFirstSeen() async {
    try {
      final state = _tryDecode(await _persistence.read()) ?? _emptyState;
      final seen = state['seen'] as Map;
      final result = <String, DateTime>{};
      for (final entry in seen.entries) {
        final value = entry.value;
        if (entry.key is String && value is String) {
          final parsed = DateTime.tryParse(value);
          if (parsed != null) result[entry.key as String] = parsed.toUtc();
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<StoreWriteResult> deleteFirstSeen(
    String id, {
    int? expectedEpoch,
  }) async {
    if (_norm(id).isEmpty) return StoreWriteResult.rejected;
    try {
      final result = await _persistence.runExclusive(() async {
        final state = await _stateForMutation();
        if (state == null) return StoreWriteResult.failed;
        if (expectedEpoch != null && _epochOf(state) != expectedEpoch) {
          return StoreWriteResult.rejected;
        }
        final seen = state['seen'] as Map<String, dynamic>;
        if (!seen.containsKey(_norm(id))) return StoreWriteResult.applied;
        seen.remove(_norm(id));
        await _persistence.write(jsonEncode(state));
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
        await _persistence.write(jsonEncode(state));
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

  /// Wipes every record and observation stamp — the factory-reset path.
  /// Orphaned media files left behind are the S5 sweep's job; the durable
  /// claims that would resurrect or drive downloads are gone here. The
  /// lifecycle epoch is bumped so writes carrying a pre-reset fence are
  /// rejected instead of resurrecting content.
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
          final previous = _epochOf(
            _tryDecode(await _persistence.read()) ?? _emptyState,
          );
          await _persistence.write(
            jsonEncode({
              'schema': schemaVersion,
              'records': <String, dynamic>{},
              'seen': <String, dynamic>{},
              'epoch': _nextEpoch(previous),
            }),
          );
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
