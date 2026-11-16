import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes the current frame to [path] as PNG. Debug aid for visual checks;
/// renders offscreen, no window is shown.
Future<void> snapshot(WidgetTester tester, String path) async {
  final element = tester.binding.rootElement!;
  var render = element.renderObject!;
  while (render is! RenderRepaintBoundary) {
    late RenderObject child;
    render.visitChildren((c) => child = c);
    render = child;
  }
  final boundary = render;
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}
