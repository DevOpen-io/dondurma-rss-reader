import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'article_record_store.dart';

/// Permanent media pool shared across article records.
///
/// Files live in app documents (not the OS-evictable temp cache) and are
/// named by a stable hash of the remote URL, so two records referencing the
/// same image share one file — [unreferencedFiles] is what keeps a shared
/// file from being treated as orphaned.
class ArticleMediaStore {
  ArticleMediaStore({Directory? root}) : _root = root;

  static final RegExp _fileNamePattern = RegExp(r'^m_[0-9a-f]{16}$');

  final Directory? _root;
  Directory? _resolved;

  Future<Directory> _dir() async {
    final known = _resolved;
    final resolved =
        known ??
        (_root ??
            Directory(
              '${(await getApplicationDocumentsDirectory()).path}/offline_media',
            ));
    // A reset may delete the pool directory, so existence is checked each
    // time; the temp-file sweep lists the whole pool and runs once per
    // store — status reads call this for every ready file.
    if (!await resolved.exists()) await resolved.create(recursive: true);
    if (known == null) unawaited(_sweepTempFiles(resolved));
    return _resolved = resolved;
  }

  /// Best-effort cleanup of torn `put` temp files older than a day — a crash
  /// between write and rename leaves one behind, and nothing else can see it.
  Future<void> _sweepTempFiles(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in dir.list()) {
        if (entity is! File ||
            !entity.uri.pathSegments.last.contains('.tmp.')) {
          continue;
        }
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // Sweeping is best-effort; leftovers are invisible and harmless.
    }
  }

  static bool _isValidFileName(String name) => _fileNamePattern.hasMatch(name);

  /// Resolves a `file://` src to a [File] only when its basename matches
  /// the managed `m_` scheme — feed HTML is untrusted input, so arbitrary
  /// `file://` URLs in the body never reach the filesystem (#41).
  static File? managedFileFromSrc(String src) {
    if (!src.startsWith('file://')) return null;
    final String path;
    try {
      path = Uri.decodeFull(src.substring(7));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (path.contains('..')) return null;
    final name = path.split('/').last;
    if (!_isValidFileName(name)) return null;
    return File(path);
  }

  /// 64-bit FNV-1a hash of the UTF-16 code units — deterministic,
  /// dependency-free file naming. Public so callers can commit a `pending`
  /// manifest entry BEFORE bytes land on disk (see [pendingEntry]): the
  /// record lock cannot be held across a network download, so a
  /// manifest-after-file protocol would let cleanup collect a file whose
  /// manifest commit was still in flight.
  static String fileNameFor(String url) {
    // FNV offset basis 0xcbf29ce484222325, assembled from 32-bit halves so
    // web compilation accepts it (same 64-bit value on native targets).
    var hash = (0xcbf29ce4 << 32) | 0x84222325;
    for (final byte in url.codeUnits) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    // BigInt needed: Dart ints are always signed 64-bit, so toUnsigned(64)
    // cannot produce the unsigned interpretation of a negative hash.
    final unsigned = BigInt.from(hash).toUnsigned(64).toRadixString(16);
    return 'm_${unsigned.padLeft(16, '0')}';
  }

  /// Manifest entry to commit before downloading: `pending` with size 0 —
  /// cleanup then always sees the file as referenced and [verify] stays
  /// false until real bytes arrive.
  static MediaEntry pendingEntry(String url) => MediaEntry(
    file: fileNameFor(url),
    byteSize: 0,
    state: MediaState.pending,
  );

  static int _tempCounter = 0;

  /// Writes [bytes] for [imageUrl] via temp-file + rename so a torn write
  /// can never surface as a ready file. Same URL resolves to the same file;
  /// a newer same-URL write replaces content while existing manifests still
  /// carry the old [MediaEntry.byteSize] — re-verify before trusting them.
  Future<MediaEntry> put(String imageUrl, List<int> bytes) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(
        imageUrl,
        'imageUrl',
        'refusing to persist an empty payload as ready media',
      );
    }
    final dir = await _dir();
    final name = fileNameFor(imageUrl);
    final random = Random().nextInt(1 << 32);
    final temp = File(
      '${dir.path}/$name.tmp.${DateTime.now().microsecondsSinceEpoch}_'
      '${_tempCounter++}_$random',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename('${dir.path}/$name');
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    return MediaEntry(
      file: name,
      byteSize: bytes.length,
      state: MediaState.ready,
    );
  }

  /// Absolute path of [fileName] inside the media pool — for renderers that
  /// hand the file straight to the platform (`Image.file`, `file://` src).
  /// Returns null for names outside the managed `m_` scheme.
  Future<String?> pathFor(String fileName) async {
    if (!_isValidFileName(fileName)) return null;
    return '${(await _dir()).path}/$fileName';
  }

  Future<Uint8List?> read(MediaEntry entry) async {
    if (!_isValidFileName(entry.file)) return null;
    final file = File('${(await _dir()).path}/${entry.file}');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// A media entry is only "ready" when the file is really on disk with the
  /// expected size — the durable-readability check behind the `ready` label.
  Future<bool> verify(MediaEntry entry) async {
    if (!_isValidFileName(entry.file)) return false;
    final file = File('${(await _dir()).path}/${entry.file}');
    if (!await file.exists()) return false;
    return await file.length() == entry.byteSize;
  }

  /// Files on disk that no record manifest references. Shared files stay
  /// referenced as long as any record lists them; anything not matching the
  /// generated `m_` naming scheme is left alone.
  ///
  /// Scan and delete must be one decision, taken only when no writer can be
  /// mid-commit — a record snapshot taken before the scan can miss a
  /// manifest that commits during it. [minAge] shrinks that window to
  /// effectively zero for a different reason: a file renamed into place
  /// moments ago may be racing its manifest commit on another queue, so
  /// callers that can't serialize with writers pass a grace period and only
  /// stale orphans are reported.
  Future<List<String>> unreferencedFiles(
    Iterable<ArticleRecord> records, {
    Duration minAge = Duration.zero,
  }) async {
    final referenced = <String>{
      for (final record in records)
        for (final entry in record.media.values) entry.file,
    };
    final cutoff = DateTime.now().subtract(minAge);
    final dir = await _dir();
    final orphans = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!_isValidFileName(name)) continue;
      if (referenced.contains(name)) continue;
      if (minAge > Duration.zero) {
        // A file that can't be stat'd — raced away or permission-denied —
        // reads as "unknown age", never as a safe delete.
        try {
          if ((await entity.lastModified()).isAfter(cutoff)) continue;
        } on FileSystemException {
          continue;
        }
      }
      orphans.add(name);
    }
    return orphans;
  }

  /// Deletes every managed file — `m_*` media and torn `*.tmp.*` staging —
  /// while leaving foreign content alone. The factory-reset path uses this;
  /// files the pool did not create are not ours to remove.
  Future<int> deleteAllManaged() async {
    final dir = await _dir();
    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!_isValidFileName(name) && !name.contains('.tmp.')) continue;
      try {
        await entity.delete();
        deleted++;
      } on FileSystemException {
        // A racing delete already handled it, or the OS refused — the file
        // is reported best-effort either way.
      }
    }
    return deleted;
  }

  /// Deletes one managed file. Returns `false` on an I/O failure so GC can
  /// report a partial pass instead of counting attempted deletes as freed
  /// space — a file that merely doesn't exist counts as done.
  Future<bool> delete(String file) async {
    if (!_isValidFileName(file)) return false;
    final target = File('${(await _dir()).path}/$file');
    try {
      if (await target.exists()) await target.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
