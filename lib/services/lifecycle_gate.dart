import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

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

bool isLifecycleNonce(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

/// Capture with beginWork BEFORE reading inputs or starting HTTP/extraction.
/// Reacquiring a ticket after an old response arrives does not authorize it.
final class LifecycleTicket {
  @internal
  const LifecycleTicket.internal(this.storageId, this.resetEpoch);
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
        !isLifecycleNonce(json['storageId']) ||
        json['resetEpoch'] is! String) {
      throw FormatException('Invalid lifecycle ticket');
    }
    return LifecycleTicket.internal(
      json['storageId'] as String,
      json['resetEpoch'] as String,
    );
  }
}

final class LifecycleReset {
  @internal
  const LifecycleReset.internal(this.ticket, this.resetId);
  final LifecycleTicket ticket;
  final String resetId;
}

/// Shared publication/reset authority. Work captures a ticket with
/// [beginWork] before reading inputs; every durable publication runs inside
/// [withPublication] with that ticket; a reset invalidates older tickets.
abstract interface class LifecycleGate {
  /// The gate of this isolate, installed by each entry point (app main,
  /// background dispatcher). Null means ungated (unit tests).
  static LifecycleGate? current;

  Future<LifecycleTicket> beginWork();

  Future<T> withPublication<T>(
    LifecycleTicket ticket,
    Future<T> Function() action,
  );

  Future<LifecycleReset> beginReset({required List<String> cleanupStages});

  Future<void> performCleanupStage(
    LifecycleReset reset,
    String stage,
    Future<void> Function() action,
  );

  Future<void> completeReset(LifecycleReset reset);

  /// Finishes an interrupted reset; no-op when none is pending.
  Future<void> recoverPendingReset({
    required Map<String, Future<void> Function()> cleanupStages,
  });
}

/// Single-isolate gate for web, where no other isolate or process shares
/// storage. Same ticket/reset semantics as the native coordinator.
final class MemoryLifecycleGate implements LifecycleGate {
  static final Random _random = Random.secure();
  static String _nonce() => List.generate(
    32,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  final String _storageId = _nonce();
  late String _epoch = _nonce();
  String? _resetId;
  List<String> _required = const [];
  final List<String> _completed = [];
  Future<void> _tail = Future.value();
  static final Object _section = Object();

  LifecycleTicket get _ticket => LifecycleTicket.internal(_storageId, _epoch);

  Future<T> _locked<T>(Future<T> Function() action) {
    final outer = Zone.current[_section] as List<bool>?;
    if (outer != null && outer.first) {
      return Future.error(
        StateError('Nested lifecycle gate acquisition is forbidden'),
      );
    }
    final result = _tail.then((_) {
      final active = [true];
      return runZoned(
        action,
        zoneValues: {_section: active},
      ).whenComplete(() => active[0] = false);
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<LifecycleTicket> beginWork() => _locked(() async {
    if (_resetId != null) throw LifecycleResetPending();
    return _ticket;
  });

  @override
  Future<T> withPublication<T>(
    LifecycleTicket ticket,
    Future<T> Function() action,
  ) => _locked(() async {
    if (ticket.storageId != _storageId || ticket.resetEpoch != _epoch) {
      throw StaleLifecycleTicket();
    }
    if (_resetId != null) throw LifecycleResetPending();
    return action();
  });

  @override
  Future<LifecycleReset> beginReset({required List<String> cleanupStages}) =>
      _locked(() async {
        if (_resetId != null) throw LifecycleResetPending();
        _epoch = _nonce();
        _resetId = _nonce();
        _required = List.unmodifiable(cleanupStages);
        _completed.clear();
        return LifecycleReset.internal(_ticket, _resetId!);
      });

  void _check(LifecycleReset reset) {
    if (reset.ticket.storageId != _storageId || reset.resetId != _resetId) {
      throw StaleLifecycleTicket();
    }
  }

  @override
  Future<void> performCleanupStage(
    LifecycleReset reset,
    String stage,
    Future<void> Function() action,
  ) => _locked(() async {
    _check(reset);
    if (_completed.contains(stage)) return;
    if (_required.indexOf(stage) != _completed.length) {
      throw StateError('Cleanup stages must complete in recorded order');
    }
    await action();
    _completed.add(stage);
  });

  @override
  Future<void> completeReset(LifecycleReset reset) => _locked(() async {
    if (reset.resetId != _resetId) return;
    if (_completed.length != _required.length) {
      throw StateError('Required reset cleanup is incomplete');
    }
    _resetId = null;
    _epoch = _nonce();
  });

  @override
  Future<void> recoverPendingReset({
    required Map<String, Future<void> Function()> cleanupStages,
  }) => _locked(() async {
    if (_resetId == null) return;
    if (_required.any((stage) => !cleanupStages.containsKey(stage))) {
      throw ArgumentError('Recovery handlers must cover the recorded plan');
    }
    for (final stage in _required.skip(_completed.length)) {
      await cleanupStages[stage]!();
      _completed.add(stage);
    }
    _resetId = null;
    _epoch = _nonce();
  });
}
