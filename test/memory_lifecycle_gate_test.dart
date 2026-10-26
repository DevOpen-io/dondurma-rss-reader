import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/lifecycle_gate.dart';

void main() {
  test('reset invalidates older and pending-era tickets', () async {
    final gate = MemoryLifecycleGate();
    final old = await gate.beginWork();
    final reset = await gate.beginReset(cleanupStages: ['wipe']);
    await expectLater(gate.beginWork(), throwsA(isA<LifecycleResetPending>()));
    await expectLater(
      gate.withPublication(reset.ticket, () async {}),
      throwsA(isA<LifecycleResetPending>()),
    );
    await expectLater(gate.completeReset(reset), throwsStateError);
    var wiped = false;
    await gate.performCleanupStage(reset, 'wipe', () async => wiped = true);
    await gate.completeReset(reset);
    expect(wiped, isTrue);
    for (final stale in [old, reset.ticket]) {
      await expectLater(
        gate.withPublication(stale, () async {}),
        throwsA(isA<StaleLifecycleTicket>()),
      );
    }
    final fresh = await gate.beginWork();
    expect(await gate.withPublication(fresh, () async => 1), 1);
  });

  test('publications serialize and nesting is rejected', () async {
    final gate = MemoryLifecycleGate();
    final ticket = await gate.beginWork();
    final order = <String>[];
    final release = Completer<void>();
    final first = gate.withPublication(ticket, () async {
      order.add('first-in');
      await expectLater(gate.beginWork(), throwsStateError);
      await release.future;
      order.add('first-out');
    });
    final second = gate.withPublication(
      ticket,
      () async => order.add('second'),
    );
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait([first, second]);
    expect(order, ['first-in', 'first-out', 'second']);
    // Work scheduled from a finished section is not nested.
    final later = Completer<LifecycleTicket>();
    await gate.withPublication(ticket, () async {
      Timer.run(() => later.complete(gate.beginWork()));
    });
    expect((await later.future).resetEpoch, ticket.resetEpoch);
  });
}
