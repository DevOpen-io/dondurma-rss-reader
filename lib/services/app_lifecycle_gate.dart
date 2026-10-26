import 'package:flutter/foundation.dart';

import 'app_reset_service.dart';
import 'lifecycle_gate.dart';
import 'lifecycle_gate_factory_stub.dart'
    if (dart.library.io) 'lifecycle_gate_factory_io.dart';

export 'lifecycle_gate.dart';

/// Opens the app's gate: the native coordinator in application support
/// storage, or the single-isolate [MemoryLifecycleGate] on web.
Future<LifecycleGate> openAppLifecycleGate() => openPlatformLifecycleGate();

/// Entry-point setup for every isolate (UI, background dispatcher): installs
/// the isolate's gate and finishes an interrupted reset. Call after the Hive
/// boxes open and before anything reads them.
///
/// A recovery failure leaves the reset pending — new work then fails closed
/// until a later start completes it. A gate that cannot open at all (e.g. a
/// corrupt journal) is logged and the isolate runs ungated rather than
/// refusing to start.
Future<void> installAppLifecycleGate() async {
  final LifecycleGate gate;
  try {
    gate = LifecycleGate.current ??= await openAppLifecycleGate();
  } catch (error) {
    debugPrint('Lifecycle gate unavailable, running ungated: $error');
    return;
  }
  try {
    await AppResetService.recover(gate);
  } catch (error) {
    debugPrint('Interrupted reset still pending: $error');
  }
}
