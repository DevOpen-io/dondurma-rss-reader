import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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

/// Sends [request] and reads at most [maxBytes] of the body when [accept]
/// wants the response; otherwise the body is not read at all. Headers and
/// body share one [timeout]. The body is null when unread or over the limit.
Future<(http.StreamedResponse, Uint8List?)> sendBounded(
  http.Client client,
  http.BaseRequest request, {
  required int maxBytes,
  required bool Function(http.StreamedResponse response) accept,
  required Duration timeout,
}) => () async {
  final response = await client.send(request);
  if (!accept(response)) {
    await response.stream.listen(null).cancel();
    return (response, null);
  }
  return (response, await readAtMost(response.stream, maxBytes));
}().timeout(timeout);
