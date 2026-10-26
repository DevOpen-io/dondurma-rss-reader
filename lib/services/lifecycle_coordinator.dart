import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';

import 'lifecycle_mutex.dart';

final class LifecycleJournalException implements Exception {
  LifecycleJournalException(this.message);
  final String message;
  @override
  String toString() => 'LifecycleJournalException: $message';
}

final class StaleLifecycleTicket implements Exception {
  @override
  String toString() => 'StaleLifecycleTicket';
}

final class LifecycleResetPending implements Exception {
  @override
  String toString() => 'LifecycleResetPending';
}

/// Capture with beginWork BEFORE reading inputs or starting HTTP/extraction.
/// Reacquiring a ticket after an old response arrives does not authorize it.
final class LifecycleTicket {
  const LifecycleTicket._(this.storageId, this.resetEpoch);
  final String storageId;
  final String resetEpoch;

  Map<String, Object> toJson() => {
    'ticketVersion': 1,
    'storageId': storageId,
    'resetEpoch': resetEpoch,
  };

  factory LifecycleTicket.fromJson(Map<String, dynamic> json) {
    if (json['ticketVersion'] is! int ||
        json['ticketVersion'] != 1 ||
        !_isNonce(json['storageId']) ||
        json['resetEpoch'] is! String) {
      throw FormatException('Invalid lifecycle ticket');
    }
    return LifecycleTicket._(
      json['storageId'] as String,
      json['resetEpoch'] as String,
    );
  }
}

final class LifecycleReset {
  const LifecycleReset._(this.ticket, this.resetId);
  final LifecycleTicket ticket;
  final String resetId;
}

const _maxCleanupStages = 128;

bool _isNonce(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
bool _isStage(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$').hasMatch(value);

/// Immutable journal snapshot. Cleanup completion is NOT application cleanup:
/// the phase-2 caller must provide idempotent actions and integrate startup.
final class LifecycleState {
  LifecycleState._({
    required this.storageId,
    required this.resetEpoch,
    required this.resetSequence,
    required this.resetId,
    required this.resetPending,
    required List<String> requiredCleanupStages,
    required List<String> completedCleanupStages,
  }) : requiredCleanupStages = List.unmodifiable(requiredCleanupStages),
       completedCleanupStages = List.unmodifiable(completedCleanupStages);

  static const schemaVersion = 1;
  final String storageId;
  final String resetEpoch;
  final int resetSequence;
  final String? resetId;
  final bool resetPending;
  final List<String> requiredCleanupStages;
  final List<String> completedCleanupStages;
  LifecycleTicket get ticket => LifecycleTicket._(storageId, resetEpoch);
  LifecycleReset? get pendingReset =>
      resetPending ? LifecycleReset._(ticket, resetId!) : null;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'storageId': storageId,
    'resetEpoch': resetEpoch,
    'resetSequence': resetSequence,
    'resetId': resetId,
    'resetPending': resetPending,
    'requiredCleanupStages': requiredCleanupStages,
    'completedCleanupStages': completedCleanupStages,
  };

  factory LifecycleState._decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map ||
          json['schemaVersion'] is! int ||
          json['schemaVersion'] != schemaVersion ||
          !_isNonce(json['storageId']) ||
          json['resetSequence'] is! int ||
          (json['resetSequence'] as int) < 0 ||
          json['resetPending'] is! bool ||
          json['resetEpoch'] is! String) {
        throw const FormatException('Invalid lifecycle envelope');
      }
      final id = json['storageId'] as String;
      final sequence = json['resetSequence'] as int;
      final epoch = json['resetEpoch'] as String;
      final prefix = '$id:$sequence:';
      if (!epoch.startsWith(prefix) ||
          !_isNonce(epoch.substring(prefix.length))) {
        throw const FormatException('Invalid lifecycle epoch');
      }
      List<String> stages(Object? raw) {
        if (raw is! List ||
            raw.length > _maxCleanupStages ||
            raw.any((v) => v is! String || !_isStage(v))) {
          throw const FormatException('Invalid cleanup stages');
        }
        final result = raw.cast<String>();
        if (result.toSet().length != result.length) {
          throw const FormatException('Duplicate cleanup stage');
        }
        return result;
      }

      final required = stages(json['requiredCleanupStages']);
      final completed = stages(json['completedCleanupStages']);
      final pending = json['resetPending'] as bool;
      final resetId = json['resetId'];
      if ((sequence == 0 &&
              (resetId != null ||
                  pending ||
                  required.isNotEmpty ||
                  completed.isNotEmpty)) ||
          (sequence > 0 && !_isNonce(resetId)) ||
          completed.length > required.length ||
          completed.indexed.any((entry) => entry.$2 != required[entry.$1]) ||
          (!pending && required.any((stage) => !completed.contains(stage)))) {
        throw const FormatException('Inconsistent reset journal');
      }
      return LifecycleState._(
        storageId: id,
        resetEpoch: epoch,
        resetSequence: sequence,
        resetId: resetId as String?,
        resetPending: pending,
        requiredCleanupStages: required,
        completedCleanupStages: completed,
      );
    } catch (error) {
      throw LifecycleJournalException('Invalid journal: $error');
    }
  }

  LifecycleState _progress(List<String> completed) => LifecycleState._(
    storageId: storageId,
    resetEpoch: resetEpoch,
    resetSequence: resetSequence,
    resetId: resetId,
    resetPending: true,
    requiredCleanupStages: requiredCleanupStages,
    completedCleanupStages: completed,
  );

  // Completion rotates the epoch: tickets observed while pending, including
  // the reset handle's own, must not authorize post-cleanup publication.
  LifecycleState _finish() => LifecycleState._(
    storageId: storageId,
    resetEpoch: '$storageId:$resetSequence:${LifecycleCoordinator._nonce()}',
    resetSequence: resetSequence,
    resetId: resetId,
    resetPending: false,
    requiredCleanupStages: requiredCleanupStages,
    completedCleanupStages: completedCleanupStages,
  );
}

final class _CriticalSection {
  bool active = true;
}

/// Shared publication/reset authority across isolates and processes.
///
/// The native mutex is built for every native target by hook/build.dart;
/// there is no fallback to expiring leases or process-scoped Dart locks.
/// Never delete/replace the permanent lock file while any process uses it.
/// No network work belongs in a publication or cleanup callback.
final class LifecycleCoordinator {
  LifecycleCoordinator({
    required this.directory,
    this.lockTimeout = const Duration(seconds: 10),
    this.retryInterval = const Duration(milliseconds: 5),
    @visibleForTesting this.onContention,
    @visibleForTesting this.beforeJournalReplace,
  }) : _native = LifecycleMutexBindings() {
    if (lockTimeout <= Duration.zero || retryInterval <= Duration.zero) {
      throw ArgumentError('Lifecycle lock durations must be positive');
    }
  }

  final Directory directory;
  final Duration lockTimeout;
  final Duration retryInterval;
  final LifecycleMutexBindings _native;
  // Deterministic test seams. Never used by production writers in phase 1.
  final void Function()? onContention;
  final Future<void> Function(File staged, File target)? beforeJournalReplace;
  static final Object _criticalSection = Object();
  static final Random _random = Random.secure();

  static String _nonce() => List.generate(
    32,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<T> _locked<T>(Future<T> Function(Directory root) action) async {
    // Reject even different-root nested acquisitions, preventing ABBA as
    // well as same-root self-deadlock across coordinator instances.
    // The zone outlives the call for work the callback schedules; only an
    // active section counts as nesting.
    final outer = Zone.current[_criticalSection] as _CriticalSection?;
    if (outer?.active ?? false) {
      throw StateError('Nested lifecycle coordinator acquisition is forbidden');
    }
    final missing = <Directory>[];
    var ancestor = directory.absolute;
    while (!await ancestor.exists()) {
      missing.add(ancestor);
      ancestor = ancestor.parent;
    }
    await directory.create(recursive: true);
    // Journal durability also needs newly created directory entries durable;
    // syncing only the leaf would not persist its link in the parent.
    for (final created in missing.reversed) {
      _native.syncDirectory(await created.parent.resolveSymbolicLinks());
    }
    final root = Directory(await directory.resolveSymbolicLinks());
    final handle = _native.open('${root.path}/publication.lock');
    try {
      final stopwatch = Stopwatch()..start();
      var signaled = false;
      while (!handle.tryAcquire()) {
        if (!signaled) {
          signaled = true;
          onContention?.call();
        }
        if (stopwatch.elapsed >= lockTimeout) {
          throw TimeoutException(
            'Lifecycle mutex acquisition timed out',
            lockTimeout,
          );
        }
        await Future<void>.delayed(retryInterval);
      }
      final section = _CriticalSection();
      try {
        return await runZoned(
          () => action(root),
          zoneValues: {_criticalSection: section},
        );
      } finally {
        section.active = false;
      }
    } finally {
      handle.close();
    }
  }

  Future<void> _replace(
    Directory root,
    File target,
    String value, {
    bool journal = false,
  }) async {
    final staged = File('${target.path}.tmp-${_nonce()}');
    try {
      await staged.create(exclusive: true);
      await staged.writeAsString(value, flush: true);
      if (journal) await beforeJournalReplace?.call(staged, target);
      await staged.rename(target.path);
      _native.syncDirectory(root.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<LifecycleState> _load(Directory root) async {
    final journal = File('${root.path}/lifecycle.json');
    final marker = File('${root.path}/initialized');
    final journalType = await FileSystemEntity.type(
      journal.path,
      followLinks: false,
    );
    final markerType = await FileSystemEntity.type(
      marker.path,
      followLinks: false,
    );
    if (journalType != FileSystemEntityType.notFound &&
            journalType != FileSystemEntityType.file ||
        markerType != FileSystemEntityType.notFound &&
            markerType != FileSystemEntityType.file) {
      throw LifecycleJournalException(
        'Journal and marker must be regular files',
      );
    }
    if (journalType == FileSystemEntityType.notFound &&
        markerType != FileSystemEntityType.notFound) {
      throw LifecycleJournalException(
        'Previously initialized journal is missing',
      );
    }
    final LifecycleState state;
    if (journalType == FileSystemEntityType.notFound) {
      final id = _nonce();
      state = LifecycleState._(
        storageId: id,
        resetEpoch: '$id:0:${_nonce()}',
        resetSequence: 0,
        resetId: null,
        resetPending: false,
        requiredCleanupStages: [],
        completedCleanupStages: [],
      );
      await _save(root, state);
    } else {
      if (await journal.length() > 65536) {
        throw LifecycleJournalException('Journal exceeds size limit');
      }
      state = LifecycleState._decode(await journal.readAsString());
    }
    if (markerType == FileSystemEntityType.notFound) {
      // A crash after initial journal rename but before this marker is safe:
      // no ticket was returned yet, and the same journal is adopted on retry.
      await _replace(root, marker, state.storageId);
    } else if (await marker.readAsString() != state.storageId) {
      throw LifecycleJournalException('Storage identity does not match marker');
    }
    return state;
  }

  Future<void> _save(Directory root, LifecycleState state) => _replace(
    root,
    File('${root.path}/lifecycle.json'),
    jsonEncode(state.toJson()),
    journal: true,
  );

  Future<LifecycleState> initialize() => _locked(_load);

  Future<LifecycleTicket> beginWork() => _locked((root) async {
    final state = await _load(root);
    if (state.resetPending) throw LifecycleResetPending();
    return state.ticket;
  });

  Future<T> withPublication<T>(
    LifecycleTicket ticket,
    Future<T> Function() action,
  ) => _locked((root) async {
    final state = await _load(root);
    if (ticket.storageId != state.storageId ||
        ticket.resetEpoch != state.resetEpoch) {
      throw StaleLifecycleTicket();
    }
    if (state.resetPending) throw LifecycleResetPending();
    return action();
  });

  Future<LifecycleReset> beginReset({required List<String> cleanupStages}) {
    final stages = List<String>.of(cleanupStages);
    if (stages.length > _maxCleanupStages ||
        stages.any((v) => !_isStage(v)) ||
        stages.toSet().length != stages.length) {
      throw ArgumentError('Cleanup stages must be unique simple names');
    }
    return _locked((root) async {
      final before = await _load(root);
      if (before.resetPending) throw LifecycleResetPending();
      if (before.resetSequence == 0x7fffffffffffffff) {
        throw StateError('Reset sequence exhausted');
      }
      final sequence = before.resetSequence + 1;
      final state = LifecycleState._(
        storageId: before.storageId,
        resetEpoch: '${before.storageId}:$sequence:${_nonce()}',
        resetSequence: sequence,
        resetId: _nonce(),
        resetPending: true,
        requiredCleanupStages: stages,
        completedCleanupStages: [],
      );
      await _save(root, state);
      return state.pendingReset!;
    });
  }

  void _checkReset(LifecycleState state, LifecycleReset reset) {
    // resetId is a per-reset nonce; the epoch rotates on completion.
    if (state.storageId != reset.ticket.storageId ||
        state.resetId != reset.resetId) {
      throw StaleLifecycleTicket();
    }
  }

  /// The action must be idempotent: a crash after it but before journal commit
  /// intentionally causes replay. It executes under the publication mutex.
  Future<LifecycleState> performCleanupStage(
    LifecycleReset reset,
    String stage,
    Future<void> Function() action,
  ) => _locked((root) async {
    final state = await _load(root);
    _checkReset(state, reset);
    if (!state.requiredCleanupStages.contains(stage)) {
      throw ArgumentError('Unknown cleanup stage');
    }
    if (state.completedCleanupStages.contains(stage)) return state;
    if (!state.resetPending) throw StateError('Reset is already complete');
    if (state.requiredCleanupStages[state.completedCleanupStages.length] !=
        stage) {
      throw StateError('Cleanup stages must complete in recorded order');
    }
    await action();
    final after = state._progress([...state.completedCleanupStages, stage]);
    await _save(root, after);
    return after;
  });

  Future<LifecycleState> completeReset(LifecycleReset reset) =>
      _locked((root) async {
        final state = await _load(root);
        _checkReset(state, reset);
        if (!state.resetPending) return state;
        if (state.requiredCleanupStages.any(
          (stage) => !state.completedCleanupStages.contains(stage),
        )) {
          throw StateError('Required reset cleanup is incomplete');
        }
        final after = state._finish();
        await _save(root, after);
        return after;
      });

  /// No app cleanup is inferred. Every recorded stage needs a handler before
  /// any callback runs; extra handlers are ignored. Failure leaves
  /// pending=true for a later explicit retry.
  Future<LifecycleState> recoverPendingReset({
    required Map<String, Future<void> Function()> cleanupStages,
  }) {
    final actions = Map<String, Future<void> Function()>.of(cleanupStages);
    return _locked((root) async {
      var state = await _load(root);
      if (!state.resetPending) return state;
      // A superset is allowed: newer builds keep legacy stage handlers so a
      // plan recorded before a rename can still finish.
      if (state.requiredCleanupStages.any(
        (stage) => !actions.containsKey(stage),
      )) {
        throw ArgumentError(
          'Recovery handlers must cover the recorded cleanup plan',
        );
      }
      for (final stage in state.requiredCleanupStages) {
        if (state.completedCleanupStages.contains(stage)) continue;
        await actions[stage]!();
        state = state._progress([...state.completedCleanupStages, stage]);
        await _save(root, state);
      }
      state = state._finish();
      await _save(root, state);
      return state;
    });
  }
}
