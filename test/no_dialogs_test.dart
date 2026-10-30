import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app asks and confirms in bottom sheets (showAdaptiveSheet with an
/// ActionSheet), never in pop-up dialogs; only the adaptive helper may open
/// a dialog, for the desktop layout.
void main() {
  test('no screen opens a pop-up dialog', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('adaptive_dialog.dart')) continue;
      if (file.path.contains('/l10n/')) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (line.contains(
          RegExp(r'\b(showDialog|AlertDialog|SimpleDialog)\b'),
        )) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
