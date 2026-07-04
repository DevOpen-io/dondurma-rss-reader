import 'package:flutter/material.dart';

/// Shows a snackbar with the app-standard 4s auto-dismiss, replacing any
/// snackbar currently visible instead of queueing behind it.
///
/// Takes a [ScaffoldMessengerState] (not a BuildContext) so callers can
/// capture the messenger before an async gap.
void showAppSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  SnackBarAction? action,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        action: action,
      ),
    );
}
