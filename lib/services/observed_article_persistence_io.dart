import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:hive_ce/hive.dart';

import 'observed_article_persistence.dart';

ObservedArticlePersistence createObservedArticlePersistence(Box box) {
  final boxPath = box.path;
  if (boxPath == null || boxPath.isEmpty) {
    throw StateError(
      'Observed article storage requires a file-backed Hive box.',
    );
  }
  return FileObservedArticlePersistence(
    stateFile: File('$boxPath.observed-articles.json'),
  );
}

class FileObservedArticlePersistence implements ObservedArticlePersistence {
  FileObservedArticlePersistence({
    required this.stateFile,
    this.lockTimeout = const Duration(seconds: 2),
    this.retryDelay = const Duration(milliseconds: 20),
    this.afterLockAcquired,
  });

  final File stateFile;
  final Duration lockTimeout;
  final Duration retryDelay;

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
        if (acquired || !await lockFile.exists()) rethrow;
        if (stopwatch.elapsed >= lockTimeout) {
          return ExclusiveResult<T>.timeout();
        }
        await Future<void>.delayed(retryDelay);
      } finally {
        if (acquired) await _releaseOwnedLock(token);
      }
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
