import 'dart:async';
import 'dart:typed_data';

/// Reads [stream] into memory unless it exceeds [maxBytes]; then stops
/// listening and returns null, so an oversized response is never buffered
/// whole before it can be rejected.
Future<Uint8List?> readAtMost(Stream<List<int>> stream, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
    // Leaving the loop cancels the subscription.
    if (builder.length > maxBytes) return null;
  }
  return builder.takeBytes();
}
