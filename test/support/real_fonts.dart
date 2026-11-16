import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled app fonts, Roboto and Material Icons, so text in a
/// widget test measures like on a device instead of in the square test font.
/// Call from `setUpAll`.
Future<void> loadRealFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  Future<void> family(String name, Iterable<String> paths) async {
    final loader = FontLoader(name);
    for (final path in paths) {
      loader.addFont(bytes(path));
    }
    await loader.load();
  }

  for (final name in ['Outfit', 'AtkinsonHyperlegibleNext', 'Lexend']) {
    await family(
      name,
      Directory(
        'assets/fonts/$name',
      ).listSync().map((f) => f.path).where((p) => p.endsWith('.ttf')),
    );
  }
  final material = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
  await family(
    'Roboto',
    Directory(material)
        .listSync()
        .map((f) => f.path)
        .where((p) => RegExp(r'/Roboto-[A-Za-z]+\.ttf$').hasMatch(p)),
  );
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
}

String _flutterRoot() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) return root;
  // `flutter test` runs from <root>/bin/cache/... ; walk up to the SDK.
  var dir = File(Platform.resolvedExecutable).parent;
  while (!File('${dir.path}/bin/flutter').existsSync()) {
    dir = dir.parent;
  }
  return dir.path;
}
