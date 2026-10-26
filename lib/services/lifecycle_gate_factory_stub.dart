import 'lifecycle_gate.dart';

Future<LifecycleGate> openPlatformLifecycleGate() async =>
    MemoryLifecycleGate();
