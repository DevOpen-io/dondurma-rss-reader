import 'lifecycle_gate.dart';
import 'lifecycle_gate_factory_stub.dart'
    if (dart.library.io) 'lifecycle_gate_factory_io.dart';

export 'lifecycle_gate.dart';

/// Opens the app's gate: the native coordinator in application support
/// storage, or the single-isolate [MemoryLifecycleGate] on web.
Future<LifecycleGate> openAppLifecycleGate() => openPlatformLifecycleGate();
