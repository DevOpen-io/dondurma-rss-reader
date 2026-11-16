import 'package:flutter/services.dart';

/// Saves a file where the user chooses in the Android system "save as"
/// dialog (ACTION_CREATE_DOCUMENT, handled in `MainActivity`).
abstract final class DeviceFiles {
  static const _channel = MethodChannel('io.devopen.dondurma/files');

  /// Asks for a place for [name] and writes [bytes] there. True when
  /// saved, null when the user cancelled, false on an error.
  static Future<bool?> save(
    String name,
    String mimeType,
    Uint8List bytes,
  ) async {
    try {
      return await _channel.invokeMethod<bool>('saveFile', {
        'name': name,
        'mimeType': mimeType,
        'bytes': bytes,
      });
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
