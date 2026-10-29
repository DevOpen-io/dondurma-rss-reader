import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Links shared to the app from other apps through the Android share sheet
/// (#67). The home screen opens "Add feed" for each one; until it is shown
/// (onboarding, cold start) the link waits here.
abstract final class SharedLinks {
  static const _channel = MethodChannel('io.devopen.dondurma/share');

  /// The shared text waiting for the home screen; null when none.
  static final pending = ValueNotifier<String?>(null);

  /// Takes the text the app was opened with, then every text shared while
  /// it runs.
  static Future<void> listen() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') pending.value = call.arguments as String?;
    });
    final initial = await _channel.invokeMethod<String>('initialText');
    if (initial != null) pending.value = initial;
  }
}

/// The first http(s) address in shared [text] — a page title often comes
/// with it — without the punctuation that closes a sentence around it.
String? sharedUrl(String text) {
  final match = RegExp(r'https?://[^\s<>"]+').firstMatch(text)?.group(0);
  return match?.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
}
