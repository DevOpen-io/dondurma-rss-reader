import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:hive_ce/hive.dart';

import 'observed_article_persistence.dart';

ObservedArticlePersistence createObservedArticlePersistence(
  Box box, {
  String fileSuffix = '.observed-articles.json',
}) {
  final boxPath = box.path;
  if (boxPath == null || boxPath.isEmpty) {
    throw StateError(
      'Observed article storage requires a file-backed Hive box.',
    );
  }
  return FileObservedArticlePersistence(stateFile: File('$boxPath$fileSuffix'));
}

class FileObservedArticlePersistence implements ObservedArticlePersistence {
  FileObservedArticlePersistence({
    required this.stateFile,
    this.lockTimeout = const Duration(seconds: 2),
    this.retryDelay = const Duration(milliseconds: 20),
    this.staleLockAge = const Duration(minutes: 2),
    this.afterLockAcquired,
  });

  final File stateFile;
  final Duration lockTimeout;
  final Duration retryDelay;

  /// A lock file older than this is presumed orphaned (its owner was killed)
  /// and may be stolen. Comfortably above [lockTimeout] so a live holder's
  /// fresh lock is never stolen.
  final Duration staleLockAge;

  /// Test seam used to hold the critical section after ownership is acquired.
  final Future<void> Function()? afterLockAcquired;

  File get lockFile => File('${stateFile.path}.lock');

  static int _tokenCounter = 0;

  String _newToken() {
    final random = Random.secure().nextInt(1 << 32);
    return '${DateTime.now().microsecondsSinceEpoch}-${_tokenCounter++}-$random';
  }

  @override
  Future<String?> read() async {
    if (!await stateFile.exists()) return null;
    return stateFile.readAsString();
  }

  @override
  Future<void> write(String value) async {
    await stateFile.parent.create(recursive: true);
    final token = _newToken();
    final temp = File('${stateFile.path}.tmp.$token');
    try {
      await temp.writeAsString(value, flush: true);
      await temp.rename(stateFile.path);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  @override
  Future<ExclusiveResult<T>> runExclusive<T>(
    Future<T> Function() action,
  ) async {
    await stateFile.parent.create(recursive: true);
    final token = _newToken();
    final stopwatch = Stopwatch()..start();

    while (true) {
      var acquired = false;
      try {
        await lockFile.create(exclusive: true);
        acquired = true;
        await lockFile.writeAsString(
          '$token\n${DateTime.now().toUtc().toIso8601String()}',
          flush: true,
        );
        await afterLockAcquired?.call();
        return ExclusiveResult<T>.acquired(await action());
      } on FileSystemException {
        if (acquired) rethrow;
        // Fail closed: a lock that vanished between the failed create and
        // this check, or any persistent error, surfaces as a timeout — never
        // as an exception escaping the bool-style contract of callers.
        if (await _stealIfStale()) continue;
        if (stopwatch.elapsed >= lockTimeout) {
          return ExclusiveResult<T>.timeout();
        }
        await Future<void>.delayed(retryDelay);
      } finally {
        if (acquired) await _releaseOwnedLock(token);
      }
    }
  }

  /// Deletes the lock file when its embedded timestamp (or mtime fallback)
  /// is older than [staleLockAge]. Returns true so the caller retries the
  /// exclusive create immediately.
  Future<bool> _stealIfStale() async {
    try {
      if (!await lockFile.exists()) return false;
      DateTime stamped;
      try {
        final lines = (await lockFile.readAsString()).split('\n');
        stamped =
            DateTime.tryParse(lines.length > 1 ? lines[1] : '')?.toUtc() ??
            (await lockFile.lastModified()).toUtc();
      } on FileSystemException {
        return false;
      }
      if (DateTime.now().toUtc().difference(stamped) <= staleLockAge) {
        return false;
      }
      await lockFile.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _releaseOwnedLock(String token) async {
    try {
      if (!await lockFile.exists()) return;
      final contents = await lockFile.readAsString();
      if (contents.split('\n').first == token) {
        await lockFile.delete();
      }
    } on FileSystemException {
      // Fail closed. Runtime contenders never steal an unreadable/orphan lock.
    }
  }
}
