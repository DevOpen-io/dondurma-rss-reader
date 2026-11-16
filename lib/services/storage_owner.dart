import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Keeps the Hive boxes to one writer per process.
///
/// The WorkManager task runs in a second isolate of the app's process, and
/// Hive gives each isolate its own write position in a box file: two
/// isolates writing the same box corrupt it (on device: "Recovering
/// corrupted box", read marks lost). So while the app's UI isolate is
/// alive — also in the background, when WorkManager fires most — the task
/// hands its pass to it instead of opening the boxes, and a task already
/// running stops writing once the app appears.
abstract final class StorageOwner {
  /// Names registered with [IsolateNameServer], shared by all isolates of
  /// the process.
  static const uiName = 'dondurma.storage.ui';
  static const backgroundName = 'dondurma.storage.background';

  static ReceivePort? _uiPort;
  static ReceivePort? _backgroundPort;

  /// Runs a background pass in the UI isolate (set once the app's providers
  /// exist). Until then a handed-off pass is acknowledged and skipped.
  static Future<void> Function()? onBackgroundTick;

  /// Announces the UI isolate before it opens the boxes, waiting up to
  /// [maxWait] for a background pass that holds them to finish.
  static Future<void> claimForUi({
    Duration maxWait = const Duration(seconds: 10),
  }) async {
    final port = _uiPort ??= ReceivePort()..listen(_onUiMessage);
    IsolateNameServer.removePortNameMapping(uiName);
    IsolateNameServer.registerPortWithName(port.sendPort, uiName);
    final deadline = DateTime.now().add(maxWait);
    while (IsolateNameServer.lookupPortByName(backgroundName) != null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// The UI isolate is going away (app detached).
  static void releaseUi() {
    IsolateNameServer.removePortNameMapping(uiName);
    _uiPort?.close();
    _uiPort = null;
  }

  static Future<void> _onUiMessage(Object? message) async {
    if (message is! SendPort) return;
    message.send('ack');
    try {
      await onBackgroundTick?.call();
    } catch (e) {
      debugPrint('[storage] handed-off pass failed: $e');
    }
    message.send('done');
  }

  /// Called by the background task first. True when the app's UI isolate
  /// took the pass (and has run it); false when the task must run it — no
  /// app, or a name left by a UI isolate that died, which is then dropped.
  static Future<bool> handOffToUi({
    Duration ackTimeout = const Duration(seconds: 3),
    Duration passTimeout = const Duration(minutes: 8),
  }) async {
    final ui = IsolateNameServer.lookupPortByName(uiName);
    if (ui == null) return false;
    final reply = ReceivePort();
    final replies = StreamIterator(reply);
    try {
      ui.send(reply.sendPort);
      final acked = await replies.moveNext().timeout(
        ackTimeout,
        onTimeout: () => false,
      );
      if (!acked) {
        IsolateNameServer.removePortNameMapping(uiName);
        return false;
      }
      await replies.moveNext().timeout(passTimeout, onTimeout: () => false);
      return true;
    } finally {
      unawaited(replies.cancel());
      reply.close();
    }
  }

  /// Marks a background pass that holds the boxes.
  static void enterBackground() {
    final port = _backgroundPort ??= ReceivePort();
    IsolateNameServer.removePortNameMapping(backgroundName);
    IsolateNameServer.registerPortWithName(port.sendPort, backgroundName);
  }

  static void leaveBackground() {
    IsolateNameServer.removePortNameMapping(backgroundName);
    _backgroundPort?.close();
    _backgroundPort = null;
  }

  /// In a background pass: the app's UI isolate has appeared, so the pass
  /// must not write any more.
  static bool get uiAppeared =>
      _backgroundPort != null &&
      IsolateNameServer.lookupPortByName(uiName) != null;

  @visibleForTesting
  static void debugReset() {
    releaseUi();
    leaveBackground();
    onBackgroundTick = null;
  }
}
