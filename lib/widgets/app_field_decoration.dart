import 'package:flutter/material.dart';

/// The app's one text-field look: filled and rounded, outlined only in the
/// theme color while focused (or the error color). The theme's own input
/// decoration is bare for inline search fields, so dialogs use this.
InputDecoration appFieldDecoration(ColorScheme cs) {
  OutlineInputBorder border([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: side,
      );
  return InputDecoration(
    filled: true,
    fillColor: cs.surfaceContainerHigh,
    prefixIconColor: cs.onSurfaceVariant,
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(BorderSide(color: cs.primary, width: 2)),
    errorBorder: border(BorderSide(color: cs.error, width: 1.5)),
    focusedErrorBorder: border(BorderSide(color: cs.error, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}
