import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'lifecycle_coordinator.dart';

/// The journal and mutex live in application support storage, outside every
/// reset target (Hive boxes, sidecars, the media pool).
Future<LifecycleGate> openPlatformLifecycleGate() async {
  final support = await getApplicationSupportDirectory();
  final coordinator = LifecycleCoordinator(
    directory: Directory('${support.path}/lifecycle'),
  );
  await coordinator.initialize();
  return coordinator;
}
