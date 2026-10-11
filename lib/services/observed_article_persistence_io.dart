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

  // A populated directory can be claimed by atomic rename but cannot be
  // overwritten or removed by another contender's stale cleanup. Keep the
  // existing lock file inside this protocol for legacy-lock recovery.
  Directory get _guardDirectory => Directory('${lockFile.path}.guard');

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
    final stopwatch = Stopwatch()..start();

    while (true) {
      // A retry publishes a different owner marker, so a delayed recovery
      // from an earlier attempt cannot remove this attempt's fresh guard.
      final token = _newToken();
      var acquired = false;
      var guardAcquired = false;
      try {
        await _acquireGuard(token);
        guardAcquired = true;
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
        if (guardAcquired) {
          // All file-lock acquisition, recovery and release now hold the
          // same guard. A stale decision cannot unlink a newer owner's lock.
          if (await _stealIfStale()) continue;
        } else {
          if (await _recoverStaleGuard()) continue;
        }
        if (stopwatch.elapsed >= lockTimeout) {
          return ExclusiveResult<T>.timeout();
        }
        await Future<void>.delayed(retryDelay);
      } finally {
        try {
          if (acquired) await _releaseOwnedLock(token);
        } finally {
          if (guardAcquired) {
            await _removeGuardOwner(_guardDirectory, 'owner-$token');
          }
        }
      }
    }
  }

  Future<void> _acquireGuard(String token) async {
    final candidate = Directory('${_guardDirectory.path}.$token');
    final ownerName = 'owner-$token';
    try {
      await candidate.create();
      await File(
        '${candidate.path}/$ownerName',
      ).writeAsString(DateTime.now().toUtc().toIso8601String(), flush: true);
      // POSIX rename refuses to replace a non-empty directory; Windows
      // refuses an existing destination. The owner marker is present before
      // publication, so no contender can replace an active guard.
      await candidate.rename(_guardDirectory.path);
    } finally {
      // After a successful rename this path is absent. After a failed rename
      // it contains only this attempt's marker, never another owner's data.
      await _removeGuardOwner(candidate, ownerName);
    }
  }

  Future<bool> _recoverStaleGuard() async {
    try {
      final entries = await _guardDirectory.list(followLinks: false).toList();
      if (entries.isEmpty) {
        // A writer died after removing its marker. A concurrently published
        // fresh guard is non-empty, making this non-recursive delete fail.
        await _guardDirectory.delete();
        return true;
      }
      if (entries.length != 1 || entries.single is! File) return false;
      final owner = entries.single as File;
      final name = owner.path.split(Platform.pathSeparator).last;
      if (!RegExp(r'^owner-[0-9]+-[0-9]+-[0-9]+$').hasMatch(name)) {
        return false;
      }
      final stamped = DateTime.tryParse(await owner.readAsString())?.toUtc();
      if (stamped == null ||
          DateTime.now().toUtc().difference(stamped) <= staleLockAge) {
        return false;
      }
      return await _removeGuardOwner(_guardDirectory, name);
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _removeGuardOwner(Directory directory, String ownerName) async {
    try {
      // Delete only the snapshotted owner's unique marker. If another
      // contender already recovered/replaced the directory this fails; if it
      // replaces the now-empty directory afterwards, the non-recursive
      // directory delete fails because the new marker keeps it non-empty.
      await File('${directory.path}/$ownerName').delete();
      await directory.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Deletes the lock file when its embedded timestamp (or mtime fallback)
  /// is older than [staleLockAge]. Returns true so the caller retries the
  /// exclusive create immediately. Only called while holding the guard.
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
