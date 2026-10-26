// Pure Dart helper: used both by Isolate.spawn and a fresh `dart run` process.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:ice_cream_rss_reader/services/lifecycle_coordinator.dart';

void lifecycleIsolateWorker(List<Object> args) async {
  final root = args[0] as String;
  final output = args[1] as SendPort;
  final mode = args[2] as String;
  final input = ReceivePort();
  try {
    final coordinator = LifecycleCoordinator(
      directory: Directory(root),
      onContention: () => output.send(['busy']),
    );
    final ticket = await coordinator.beginWork();
    output.send(['ready', input.sendPort]);
    await input.first;
    input.close();
    if (mode == 'hold') {
      final release = ReceivePort();
      await coordinator.withPublication(ticket, () async {
        output.send(['entered', release.sendPort]);
        await release.first;
      });
      release.close();
    } else {
      final counter = File('$root/counter');
      for (var i = 0; i < 12; i++) {
        await coordinator.withPublication(ticket, () async {
          final value = int.parse(await counter.readAsString());
          await counter.writeAsString('${value + 1}', flush: true);
        });
      }
    }
    output.send(['done']);
  } catch (error, stack) {
    output.send(['error', error.toString(), stack.toString()]);
    input.close();
  }
}

Future<void> _event(String event) async {
  stdout.writeln(jsonEncode({'event': event}));
  await stdout.flush();
}

Future<void> main(List<String> args) async {
  final mode = args[0];
  final root = Directory(args[1]);
  final commands = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  var coordinator = LifecycleCoordinator(
    directory: root,
    onContention: () => stdout.writeln(jsonEncode({'event': 'busy'})),
  );
  if (mode == 'crash-journal') {
    await coordinator.initialize();
    coordinator = LifecycleCoordinator(
      directory: root,
      beforeJournalReplace: (staged, target) async {
        if ((jsonDecode(await staged.readAsString()) as Map)['resetPending'] ==
            true) {
          await _event('staged');
          await commands.first;
          exit(74); // No finally blocks, journal rename has not happened.
        }
      },
    );
    await coordinator.beginReset(cleanupStages: ['archive']);
    throw StateError('Expected process exit');
  }
  if (mode == 'crash-cleanup') {
    final reset = await coordinator.beginReset(
      cleanupStages: ['archive', 'media'],
    );
    await coordinator.performCleanupStage(
      reset,
      'archive',
      () => File(
        '${root.path}/archive-cleaned',
      ).writeAsString('done').then((_) {}),
    );
    await coordinator.performCleanupStage(reset, 'media', () async {
      await File(
        '${root.path}/media-cleaned',
      ).writeAsString('done', flush: true);
      await _event('cleanup-started');
      await commands.first;
      exit(73); // Action done, stage acknowledgement not committed.
    });
    throw StateError('Expected process exit');
  }
  final ticket = await coordinator.beginWork();
  if (mode == 'hold') {
    await coordinator.withPublication(ticket, () async {
      await _event('entered');
      await commands.first;
    });
  } else if (mode == 'publish') {
    await _event('ready');
    await commands.first;
    await coordinator.withPublication(ticket, () async {
      await _event('entered');
      await File(
        '${root.path}/process-publication',
      ).writeAsString('done', flush: true);
    });
  } else {
    throw ArgumentError('Unknown worker mode: $mode');
  }
  await _event('done');
}
