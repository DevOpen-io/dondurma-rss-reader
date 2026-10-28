import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/utils/bounded_body.dart';

void main() {
  test('returns the body when it fits', () async {
    final bytes = await readAtMost(
      Stream.fromIterable([
        [1, 2],
        [3],
      ]),
      3,
    );
    expect(bytes, [1, 2, 3]);
  });

  test('stops reading and cancels once the limit is passed', () async {
    var cancelled = false;
    var sent = 0;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        while (!cancelled) {
          controller.add([0, 0, 0, 0]);
          sent++;
          await Future<void>.delayed(Duration.zero);
        }
      },
      onCancel: () => cancelled = true,
    );
    expect(await readAtMost(controller.stream, 10), isNull);
    expect(cancelled, isTrue);
    expect(sent, lessThan(5));
  });
}
