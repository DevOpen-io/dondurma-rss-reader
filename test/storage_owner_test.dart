import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/services/storage_owner.dart';

/// The WorkManager task runs in a second isolate of the app's process. Two
/// isolates writing the same Hive box corrupt it ("Recovering corrupted
/// box" on device, 2026-11-16, read marks lost). While the app's UI isolate
/// is alive the task hands its pass to it instead of opening the boxes.

/// Background side, run in a spawned isolate: reports whether the pass was
/// handed off.
Future<void> _backgroundHandOff(SendPort result) async {
  result.send(
    await StorageOwner.handOffToUi(ackTimeout: const Duration(seconds: 2)),
  );
}

Future<bool> _handOffFromAnotherIsolate() async {
  final port = ReceivePort();
  await Isolate.spawn(_backgroundHandOff, port.sendPort);
  final handedOff = await port.first as bool;
  port.close();
  return handedOff;
}

void main() {
  tearDown(StorageOwner.debugReset);

  test('with no app open the task runs its own pass', () async {
    expect(await _handOffFromAnotherIsolate(), isFalse);
  });

  test('a live app runs the pass for the task', () async {
    var ticks = 0;
    await StorageOwner.claimForUi();
    StorageOwner.onBackgroundTick = () async => ticks++;

    expect(await _handOffFromAnotherIsolate(), isTrue);
    expect(ticks, 1);
  });

  test('an app that went away without saying so is not waited on', () async {
    // A name left behind by a UI isolate that died: nobody answers.
    final dead = ReceivePort()..close();
    IsolateNameServer.registerPortWithName(dead.sendPort, StorageOwner.uiName);

    final watch = Stopwatch()..start();
    expect(await _handOffFromAnotherIsolate(), isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(IsolateNameServer.lookupPortByName(StorageOwner.uiName), isNull);
  });

  test('a released app no longer takes passes', () async {
    await StorageOwner.claimForUi();
    StorageOwner.releaseUi();
    expect(await _handOffFromAnotherIsolate(), isFalse);
  });

  test('the task stops writing once the app appears', () async {
    expect(StorageOwner.uiAppeared, isFalse, reason: 'not in a task');
    StorageOwner.enterBackground();
    expect(StorageOwner.uiAppeared, isFalse);
    // The app's isolate announces itself mid-pass.
    final ui = ReceivePort();
    IsolateNameServer.registerPortWithName(ui.sendPort, StorageOwner.uiName);
    expect(StorageOwner.uiAppeared, isTrue);
    StorageOwner.leaveBackground();
    ui.close();
  });

  test('the app waits for a running task to let go of storage', () async {
    StorageOwner.enterBackground();
    var claimed = false;
    final claim = StorageOwner.claimForUi(
      maxWait: const Duration(seconds: 5),
    ).then((_) => claimed = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(claimed, isFalse, reason: 'the task still holds the boxes');
    StorageOwner.leaveBackground();
    await claim;
    expect(claimed, isTrue);
  });

  test('a task that never lets go delays the app only so long', () async {
    StorageOwner.enterBackground();
    final watch = Stopwatch()..start();
    await StorageOwner.claimForUi(maxWait: const Duration(milliseconds: 400));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    StorageOwner.leaveBackground();
  });
}
