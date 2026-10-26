import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/lifecycle_coordinator.dart';

import 'support/lifecycle_worker.dart';

class _Worker {
  _Worker(this.process) {
    lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    errors = process.stderr.transform(utf8.decoder).join();
  }
  final Process process;
  late final StreamIterator<String> lines;
  late final Future<String> errors;
  Future<void> event(String expected) async {
    while (await lines.moveNext().timeout(const Duration(seconds: 15))) {
      final value = jsonDecode(lines.current) as Map;
      if (value['event'] == expected) return;
      if (value['event'] != 'busy') {
        throw TestFailure('Expected $expected, got $value');
      }
    }
    throw TestFailure('Worker ended before $expected: ${await errors}');
  }

  void release() => process.stdin.writeln('continue');
  Future<void> close() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await lines.cancel();
    await process.stdin.close();
    await errors;
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lifecycle-coordinator-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  LifecycleCoordinator coordinator({
    void Function()? onContention,
    Future<void> Function(File, File)? beforeReplace,
  }) => LifecycleCoordinator(
    directory: root,
    onContention: onContention,
    beforeJournalReplace: beforeReplace,
  );

  Future<_Worker> process(String mode) async {
    final worker = _Worker(
      await Process.start('dart', [
        'run',
        File('test/support/lifecycle_worker.dart').absolute.path,
        mode,
        root.path,
      ]),
    );
    addTearDown(worker.close);
    return worker;
  }

  // Process/isolate evidence is collected on Linux; other targets compile
  // the same backend but are not verified by this suite.
  final unsupported = !Platform.isLinux;

  test(
    'legacy bootstrap is idempotent across instances and preserves user bytes',
    () async {
      final legacy = File('${root.path}/cachedItemsJson');
      await legacy.writeAsString('legacy user data', flush: true);
      final first = await coordinator().initialize();
      final second = await coordinator().initialize();
      expect(second.toJson(), first.toJson());
      expect(second.resetPending, isFalse);
      expect(second.completedCleanupStages, isEmpty);
      expect(await legacy.readAsString(), 'legacy user data');
      expect(
        () => first.completedCleanupStages.add('bad'),
        throwsUnsupportedError,
      );
    },
    skip: unsupported,
  );

  test(
    'stale ticket is rejected after epoch change; new work waits for completion',
    () async {
      final current = coordinator();
      final old = await current.beginWork();
      final reset = await current.beginReset(cleanupStages: ['archive']);
      await expectLater(
        current.beginWork(),
        throwsA(isA<LifecycleResetPending>()),
      );
      var called = false;
      await expectLater(
        current.withPublication(old, () async {
          called = true;
        }),
        throwsA(isA<StaleLifecycleTicket>()),
      );
      expect(called, isFalse);
      final pendingTicket = (await current.initialize()).ticket;
      await expectLater(
        current.withPublication(pendingTicket, () async {
          called = true;
        }),
        throwsA(isA<LifecycleResetPending>()),
      );
      expect(called, isFalse);
      await expectLater(current.completeReset(reset), throwsStateError);
      await current.performCleanupStage(reset, 'archive', () async {});
      await current.completeReset(reset);
      final fresh = await coordinator().beginWork();
      expect(fresh.resetEpoch, isNot(old.resetEpoch));
      expect(
        await current.withPublication(fresh, () async => 'accepted'),
        'accepted',
      );
    },
    skip: unsupported,
  );

  test(
    'publication owns mutex until its awaited action ends; reset then completes',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final blocked = Completer<void>();
      final publisher = coordinator();
      final ticket = await publisher.beginWork();
      final publication = publisher.withPublication(ticket, () async {
        entered.complete();
        await release.future;
        await File('${root.path}/published').writeAsString('old');
      });
      await entered.future;
      final resetting = coordinator(
        onContention: () {
          if (!blocked.isCompleted) blocked.complete();
        },
      );
      var completed = false;
      final resetFuture = resetting.beginReset(cleanupStages: []).then((
        reset,
      ) async {
        await resetting.completeReset(reset);
        completed = true;
      });
      await blocked.future;
      expect(completed, isFalse);
      release.complete();
      await publication;
      await resetFuture;
      expect(completed, isTrue);
      await expectLater(
        publisher.withPublication(ticket, () async {}),
        throwsA(isA<StaleLifecycleTicket>()),
      );
    },
    skip: unsupported,
  );

  test(
    'reset wins first; callback cannot publish; later valid ticket still works',
    () async {
      final current = coordinator();
      final old = await current.beginWork();
      final reset = await coordinator().beginReset(cleanupStages: []);
      await coordinator().completeReset(reset);
      final file = File('${root.path}/publication');
      await expectLater(
        current.withPublication(old, () => file.writeAsString('stale')),
        throwsA(isA<StaleLifecycleTicket>()),
      );
      expect(await file.exists(), isFalse);
      final fresh = await current.beginWork();
      await current.withPublication(fresh, () => file.writeAsString('current'));
      expect(await file.readAsString(), 'current');
    },
    skip: unsupported,
  );

  test(
    'multiple consecutive resets never reuse epochs or accept an old reset handle',
    () async {
      final current = coordinator();
      final oldTickets = <LifecycleTicket>[];
      final epochs = <String>{};
      LifecycleReset? firstReset;
      for (var i = 0; i < 12; i++) {
        final ticket = await current.beginWork();
        expect(epochs.add(ticket.resetEpoch), isTrue);
        oldTickets.add(ticket);
        final reset = await current.beginReset(cleanupStages: []);
        firstReset ??= reset;
        await current.completeReset(reset);
      }
      for (final old in oldTickets) {
        await expectLater(
          current.withPublication(old, () async {}),
          throwsA(isA<StaleLifecycleTicket>()),
        );
      }
      await expectLater(
        current.completeReset(firstReset!),
        throwsA(isA<StaleLifecycleTicket>()),
      );
      expect((await current.initialize()).resetSequence, 12);
    },
    skip: unsupported,
  );

  test(
    'malformed, foreign, or inconsistent journal fails closed without rewriting',
    () async {
      final current = coordinator();
      final state = await current.initialize();
      final journal = File('${root.path}/lifecycle.json');
      final cases = <String>[
        '{broken',
        jsonEncode({...state.toJson(), 'schemaVersion': 99}),
        jsonEncode({...state.toJson(), 'schemaVersion': 1.0}),
        jsonEncode({...state.toJson(), 'resetPending': true}),
        jsonEncode({
          ...state.toJson(),
          'completedCleanupStages': ['invented'],
        }),
      ];
      for (final value in cases) {
        await journal.writeAsString(value, flush: true);
        await expectLater(
          coordinator().beginWork(),
          throwsA(isA<LifecycleJournalException>()),
        );
        expect(await journal.readAsString(), value);
      }
    },
    skip: unsupported,
  );

  test(
    'missing acknowledged journal fails closed instead of fresh bootstrap',
    () async {
      await coordinator().beginWork();
      await File('${root.path}/lifecycle.json').delete();
      await expectLater(
        coordinator().initialize(),
        throwsA(isA<LifecycleJournalException>()),
      );
    },
    skip: unsupported,
  );

  test(
    'pending reset survives restart; recovery skips acknowledged stages and is idempotent',
    () async {
      final old = await coordinator().beginWork();
      final reset = await coordinator().beginReset(
        cleanupStages: ['archive', 'media'],
      );
      var archiveRuns = 0;
      var mediaRuns = 0;
      await coordinator().performCleanupStage(reset, 'archive', () async {
        archiveRuns++;
      });
      final restarted = coordinator();
      expect((await restarted.initialize()).resetPending, isTrue);
      await expectLater(
        restarted.beginWork(),
        throwsA(isA<LifecycleResetPending>()),
      );
      final callbacks = <String, Future<void> Function()>{
        'archive': () async {
          archiveRuns++;
        },
        'media': () async {
          mediaRuns++;
        },
      };
      final done = await restarted.recoverPendingReset(
        cleanupStages: callbacks,
      );
      expect(done.resetPending, isFalse);
      await restarted.recoverPendingReset(cleanupStages: callbacks);
      expect(archiveRuns, 1);
      expect(mediaRuns, 1);
      await expectLater(
        restarted.withPublication(old, () async {}),
        throwsA(isA<StaleLifecycleTicket>()),
      );
    },
    skip: unsupported,
  );

  test(
    'failed cleanup remains pending and unknown recovery plan does not run callbacks',
    () async {
      final current = coordinator();
      final reset = await current.beginReset(cleanupStages: ['archive']);
      await expectLater(
        current.performCleanupStage(reset, 'archive', () async {
          throw StateError('IO failure');
        }),
        throwsStateError,
      );
      expect((await current.initialize()).completedCleanupStages, isEmpty);
      var called = false;
      await expectLater(
        current.recoverPendingReset(
          cleanupStages: {
            'wrong': () async {
              called = true;
            },
          },
        ),
        throwsArgumentError,
      );
      expect(called, isFalse);
      expect((await current.initialize()).resetPending, isTrue);
    },
    skip: unsupported,
  );

  test(
    'recovery accepts a newer superset plan and runs only recorded stages',
    () async {
      // An older build recorded this plan; the newer build renamed 'media'
      // but keeps the legacy handler so a pending reset can still finish.
      await coordinator().beginReset(cleanupStages: ['archive', 'media']);
      final ran = <String>[];
      final done = await coordinator().recoverPendingReset(
        cleanupStages: {
          for (final stage in ['archive', 'media', 'media-v2'])
            stage: () async => ran.add(stage),
        },
      );
      expect(ran, ['archive', 'media']);
      expect(done.resetPending, isFalse);
    },
    skip: unsupported,
  );

  test(
    'interrupted journal replacement leaves the previous committed state usable',
    () async {
      final old = await coordinator().beginWork();
      final failing = coordinator(
        beforeReplace: (staged, target) async {
          throw StateError('before rename');
        },
      );
      await expectLater(
        failing.beginReset(cleanupStages: []),
        throwsStateError,
      );
      final state = await coordinator().initialize();
      expect(state.resetPending, isFalse);
      expect(state.resetEpoch, old.resetEpoch);
      expect(
        await coordinator().withPublication(old, () async => true),
        isTrue,
      );
    },
    skip: unsupported,
  );

  test(
    'nested calls across instances throw instead of recursively locking',
    () async {
      final current = coordinator();
      final ticket = await current.beginWork();
      await current.withPublication(ticket, () async {
        await expectLater(
          coordinator().beginReset(cleanupStages: []),
          throwsStateError,
        );
      });
      expect(await current.withPublication(ticket, () async => true), isTrue);
    },
    skip: unsupported,
  );

  test(
    'four real isolates serialize publication over the same storage path',
    () async {
      final main = coordinator();
      final ticket = await main.beginWork();
      final counter = File('${root.path}/counter');
      await counter.writeAsString('0');
      final ports = <ReceivePort>[];
      final streams = <StreamIterator<List>>[];
      final gates = <SendPort>[];
      for (var i = 0; i < 4; i++) {
        final port = ReceivePort();
        ports.add(port);
        final stream = StreamIterator(port.cast<List>());
        streams.add(stream);
        final isolate = await Isolate.spawn(lifecycleIsolateWorker, <Object>[
          root.path,
          port.sendPort,
          'increment',
        ]);
        addTearDown(() {
          isolate.kill(priority: Isolate.immediate);
          port.close();
        });
        expect(await stream.moveNext(), isTrue);
        expect(stream.current.first, 'ready');
        gates.add(stream.current[1] as SendPort);
      }
      final entered = Completer<void>();
      final release = Completer<void>();
      final holding = main.withPublication(ticket, () async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      for (final gate in gates) {
        gate.send(true);
      }
      for (final stream in streams) {
        expect(await stream.moveNext(), isTrue);
        expect(stream.current.first, 'busy');
      }
      release.complete();
      await holding;
      for (final stream in streams) {
        do {
          expect(
            await stream.moveNext().timeout(const Duration(seconds: 15)),
            isTrue,
          );
        } while (stream.current.first == 'busy');
        expect(stream.current.first, 'done', reason: '${stream.current}');
        await stream.cancel();
      }
      expect(await counter.readAsString(), '48');
    },
    skip: unsupported,
  );

  test(
    'separate process waits for publication mutex and proceeds after release',
    () async {
      final worker = await process('publish');
      await worker.event('ready');
      final current = coordinator();
      final ticket = await current.beginWork();
      final entered = Completer<void>();
      final release = Completer<void>();
      final holding = current.withPublication(ticket, () async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      worker.release();
      await worker.event('busy');
      expect(await File('${root.path}/process-publication').exists(), isFalse);
      release.complete();
      await holding;
      await worker.event('entered');
      await worker.event('done');
      expect(await worker.process.exitCode, 0);
      expect(
        await File('${root.path}/process-publication').readAsString(),
        'done',
      );
    },
    skip: unsupported,
  );

  test(
    'SIGKILL of process holding publication releases the OS mutex without stealing',
    () async {
      final worker = await process('hold');
      await worker.event('entered');
      worker.process.kill(ProcessSignal.sigkill);
      expect(await worker.process.exitCode, isNot(0));
      final current = coordinator();
      final ticket = await current.beginWork();
      expect(
        await current.withPublication(ticket, () async => 'after owner death'),
        'after owner death',
      );
    },
    skip: unsupported,
  );

  test(
    'same-process isolate termination permits subsequent lock acquisition on this VM',
    () async {
      final port = ReceivePort();
      final exited = ReceivePort();
      final messages = StreamIterator(port.cast<List>());
      final isolate = await Isolate.spawn(lifecycleIsolateWorker, <Object>[
        root.path,
        port.sendPort,
        'hold',
      ], onExit: exited.sendPort);
      addTearDown(() async {
        isolate.kill(priority: Isolate.immediate);
        await messages.cancel();
        port.close();
        exited.close();
      });
      expect(await messages.moveNext(), isTrue);
      (messages.current[1] as SendPort).send(true);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current.first, 'entered');
      isolate.kill(priority: Isolate.immediate);
      await exited.first.timeout(const Duration(seconds: 10));
      // Current VM is expected to finalize the unreachable native handle. The
      // SDK only guarantees finalization by isolate-GROUP shutdown; document
      // this availability limit, rather than replacing it with a lease steal.
      final current = coordinator();
      final ticket = await current.beginWork();
      expect(await current.withPublication(ticket, () async => true), isTrue);
    },
    skip: unsupported,
  );

  test(
    'process exit during cleanup preserves journal and recovery replays unacknowledged stage',
    () async {
      final old = await coordinator().beginWork();
      final worker = await process('crash-cleanup');
      await worker.event('cleanup-started');
      worker.release();
      expect(await worker.process.exitCode, 73);
      final restarted = coordinator();
      final before = await restarted.initialize();
      expect(before.resetPending, isTrue);
      expect(before.completedCleanupStages, ['archive']);
      var replayed = 0;
      final done = await restarted.recoverPendingReset(
        cleanupStages: {
          'archive': () async => fail('acknowledged stage must not replay'),
          'media': () async {
            replayed++;
            await File(
              '${root.path}/media-cleaned',
            ).writeAsString('done', flush: true);
          },
        },
      );
      expect(done.resetPending, isFalse);
      expect(replayed, 1);
      await expectLater(
        restarted.withPublication(old, () async {}),
        throwsA(isA<StaleLifecycleTicket>()),
      );
      expect(
        await restarted.withPublication(
          await restarted.beginWork(),
          () async => true,
        ),
        isTrue,
      );
    },
    skip: unsupported,
  );

  test(
    'process exit before journal rename cannot advance the committed epoch',
    () async {
      final old = await coordinator().beginWork();
      final worker = await process('crash-journal');
      await worker.event('staged');
      worker.release();
      expect(await worker.process.exitCode, 74);
      final restarted = coordinator();
      final state = await restarted.initialize();
      expect(state.resetPending, isFalse);
      expect(state.resetEpoch, old.resetEpoch);
      expect(await restarted.withPublication(old, () async => true), isTrue);
      expect(
        await root.list().where((f) => f.path.contains('.tmp-')).length,
        1,
        reason:
            'Uncommitted staging is ignored, not promoted to authoritative state',
      );
    },
    skip: unsupported,
  );

  test(
    'live owner is never stolen even with an old lock-file timestamp',
    () async {
      final owner = coordinator();
      final ticket = await owner.beginWork();
      final entered = Completer<void>();
      final release = Completer<void>();
      final pending = owner.withPublication(ticket, () async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      await File(
        '${root.path}/publication.lock',
      ).setLastModified(DateTime(2000));
      final contender = LifecycleCoordinator(
        directory: root,
        lockTimeout: const Duration(milliseconds: 30),
        retryInterval: const Duration(milliseconds: 2),
      );
      var ran = false;
      await expectLater(
        contender.withPublication(ticket, () async {
          ran = true;
        }),
        throwsA(isA<TimeoutException>()),
      );
      expect(ran, isFalse);
      release.complete();
      await pending;
      expect(await contender.withPublication(ticket, () async => true), isTrue);
    },
    skip: unsupported,
  );

  test(
    'cleanup plan is bounded, ordered and cannot delete later valid data on replay',
    () async {
      final current = coordinator();
      await current.initialize();
      expect(
        () => current.beginReset(
          cleanupStages: List.generate(129, (i) => 'stage$i'),
        ),
        throwsArgumentError,
      );
      final reset = await current.beginReset(
        cleanupStages: ['archive', 'media'],
      );
      var called = false;
      await expectLater(
        current.performCleanupStage(reset, 'media', () async {
          called = true;
        }),
        throwsStateError,
      );
      expect(called, isFalse);
      await current.performCleanupStage(reset, 'archive', () async {});
      await current.performCleanupStage(reset, 'media', () async {});
      await current.completeReset(reset);
      final file = File('${root.path}/new-valid-data');
      await current.withPublication(
        await current.beginWork(),
        () => file.writeAsString('current'),
      );
      await current.performCleanupStage(reset, 'archive', () async {
        await file.delete();
      });
      await current.recoverPendingReset(
        cleanupStages: {
          'archive': () async {
            await file.delete();
          },
          'media': () async {},
        },
      );
      expect(await file.readAsString(), 'current');
    },
    skip: unsupported,
  );

  test('ticket round-trip does not authorize another storage domain', () async {
    final ticket = LifecycleTicket.fromJson(
      (await coordinator().beginWork()).toJson(),
    );
    final other = LifecycleCoordinator(
      directory: Directory('${root.path}/other-domain'),
    );
    var ran = false;
    await expectLater(
      other.withPublication(ticket, () async {
        ran = true;
      }),
      throwsA(isA<StaleLifecycleTicket>()),
    );
    expect(ran, isFalse);
    expect(
      await coordinator().withPublication(ticket, () async => true),
      isTrue,
    );
  }, skip: unsupported);

  test(
    'journal committed before initial marker is adopted without data loss',
    () async {
      final state = await coordinator().initialize();
      await File('${root.path}/initialized').delete();
      expect((await coordinator().initialize()).toJson(), state.toJson());
      expect(
        await File('${root.path}/initialized').readAsString(),
        state.storageId,
      );
    },
    skip: unsupported,
  );

  test('mutex symlink is rejected without touching its target', () async {
    final foreign = File('${root.path}/foreign-user-data');
    await foreign.writeAsString('preserve');
    await Link('${root.path}/publication.lock').create(foreign.path);
    await expectLater(
      coordinator().initialize(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await foreign.readAsString(), 'preserve');
    expect(await File('${root.path}/lifecycle.json').exists(), isFalse);
  }, skip: unsupported);

  test(
    'new directory bootstrap and symlink alias resolve to the same journal',
    () async {
      final nested = Directory('${root.path}/new/nested');
      final first = LifecycleCoordinator(directory: nested);
      final ticket = await first.beginWork();
      final alias = Link('${root.path}/alias');
      await alias.create(nested.path);
      final second = LifecycleCoordinator(directory: Directory(alias.path));
      expect((await second.initialize()).ticket.resetEpoch, ticket.resetEpoch);
      expect(await second.withPublication(ticket, () async => true), isTrue);
    },
    skip: unsupported,
  );

  test(
    'concurrent reset callers cannot open a second reset while pending',
    () async {
      final results = await Future.wait(
        List.generate(8, (_) async {
          try {
            return await coordinator().beginReset(cleanupStages: []);
          } on LifecycleResetPending {
            return null;
          }
        }),
      );
      expect(results.whereType<LifecycleReset>().length, 1);
      await coordinator().completeReset(
        results.whereType<LifecycleReset>().single,
      );
      expect((await coordinator().initialize()).resetSequence, 1);
    },
    skip: unsupported,
  );

  for (final finish in ['complete', 'recover']) {
    test(
      'tickets observed while pending cannot publish after $finish',
      () async {
        final current = coordinator();
        final reset = await current.beginReset(cleanupStages: ['archive']);
        final pendingTicket = (await current.initialize()).ticket;
        if (finish == 'complete') {
          await current.performCleanupStage(reset, 'archive', () async {});
          await current.completeReset(reset);
          // Replaying the same completed handle stays idempotent.
          expect((await current.completeReset(reset)).resetPending, isFalse);
        } else {
          await coordinator().recoverPendingReset(
            cleanupStages: {'archive': () async {}},
          );
        }
        var called = false;
        for (final stale in [pendingTicket, reset.ticket]) {
          await expectLater(
            current.withPublication(stale, () async => called = true),
            throwsA(isA<StaleLifecycleTicket>()),
          );
        }
        expect(called, isFalse);
        final fresh = await current.beginWork();
        expect(await current.withPublication(fresh, () async => true), isTrue);
      },
      skip: unsupported,
    );
  }

  test(
    'work scheduled by a callback may use the coordinator after release',
    () async {
      final current = coordinator();
      final ticket = await current.beginWork();
      final later = Completer<LifecycleTicket>();
      await current.withPublication(ticket, () async {
        Timer.run(() => later.complete(current.beginWork()));
      });
      expect((await later.future).resetEpoch, ticket.resetEpoch);
    },
    skip: unsupported,
  );
}
