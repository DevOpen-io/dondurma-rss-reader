import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

void main() {
  late Directory tempDir;
  late File stateFile;
  late Directory mediaDir;

  ArticleRef ref(
    String id, [
    String feedUrl = 'https://example.com/feed.xml',
  ]) => ArticleRef(feedUrl, id);

  ArticleRecordStore newStore() =>
      ArticleRecordStore(FileObservedArticlePersistence(stateFile: stateFile));

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('s2_storage_test_');
  });

  setUp(() {
    stateFile = File(
      '${tempDir.path}/archive_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    mediaDir = Directory(
      '${tempDir.path}/media_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  ArticleRecord buildRecord({
    required String id,
    String feedUrl = 'https://example.com/feed.xml',
    String? body,
    Set<String>? owners,
    int generation = 1,
    bool tombstoned = false,
    Map<String, MediaEntry> media = const {},
  }) {
    return ArticleRecord(
      id: id,
      feedUrl: feedUrl,
      title: 'Title $id',
      siteName: 'Example',
      body: body ?? 'Body of $id',
      imageUrls: const ['https://example.com/a.png'],
      media: media,
      owners: owners ?? {'bookmark'},
      generation: generation,
      tombstoned: tombstoned,
    );
  }

  group('ArticleRecordStore', () {
    test('record round-trips through a simulated restart', () async {
      final record = buildRecord(
        id: 'art-1',
        media: {
          'https://example.com/a.png': const MediaEntry(
            file: 'm_abc',
            byteSize: 42,
            state: MediaState.ready,
          ),
        },
      );
      expect(await newStore().write(record), StoreWriteResult.applied);

      // A fresh store on the same file = restart: state comes back off disk.
      final read = await newStore().read(ref('art-1'));
      expect(read, isNotNull);
      expect(read!.id, 'art-1');
      expect(read.body, 'Body of art-1');
      expect(read.owners, {'bookmark'});
      expect(read.generation, 1);
      expect(read.media['https://example.com/a.png']!.byteSize, 42);
      expect(read.media['https://example.com/a.png']!.state, MediaState.ready);
    });

    test('missing keys return defaults without throwing', () async {
      final store = newStore();
      expect(await store.read(ref('nope')), isNull);
      expect(await store.firstSeen(ref('nope')), isNull);
      expect(await store.isTombstoned(ref('nope')), isFalse);
      expect(await store.listRecords(), isEmpty);
    });

    test('corrupt persisted state reads as empty, not as a crash', () async {
      await stateFile.writeAsString('{{{not json');
      final store = newStore();
      expect(await store.read(ref('x')), isNull);
      expect(await store.firstSeen(ref('x')), isNull);
    });

    test('corrupt record entry degrades to missing', () async {
      await stateFile.writeAsString(
        jsonEncode({
          'schema': ArticleRecordStore.schemaVersion,
          'records': {ref('x').key: 42},
          'seen': {},
        }),
      );
      expect(await newStore().read(ref('x')), isNull);
    });

    test('record ids are normalized like article ids', () async {
      final store = newStore();
      await store.write(buildRecord(id: 'HTTPS://Example.COM/A/'));
      expect(await store.read(ref('https://example.com/A/')), isNotNull);
    });

    test('listRecords enumerates every stored record', () async {
      final store = newStore();
      await store.write(buildRecord(id: 'a'));
      await store.write(buildRecord(id: 'b'));
      final ids = (await store.listRecords()).map((r) => r.id).toSet();
      expect(ids, {'a', 'b'});
    });

    test('mutate returning null deletes the record', () async {
      final store = newStore();
      await store.write(buildRecord(id: 'del'));
      expect(await store.deleteRecord(ref('del')), StoreWriteResult.applied);
      expect(await store.read(ref('del')), isNull);
    });

    test('write refuses to overwrite a tombstone; revive continues the '
        'generation sequence', () async {
      final store = newStore();
      await store.write(buildRecord(id: 'life', generation: 1));
      await store.tombstone(ref('life'));

      expect(
        await store.write(buildRecord(id: 'life', generation: 1)),
        StoreWriteResult.rejected,
      );
      expect((await store.read(ref('life')))!.tombstoned, isTrue);

      expect(
        await store.revive(buildRecord(id: 'life')),
        StoreWriteResult.applied,
      );
      final revived = (await store.read(ref('life')))!;
      expect(revived.tombstoned, isFalse);
      expect(revived.generation, 3); // tombstone bumped 1→2, revive → 3
      // A stale write fenced to the pre-delete generation still loses.
      expect(
        await store.writeIfGeneration(
          buildRecord(id: 'life', generation: 1),
          1,
        ),
        StoreWriteResult.rejected,
      );
    });

    test(
      'undecodable state is preserved: mutations fail closed, reads empty',
      () async {
        await stateFile.writeAsString('{"schema":99,"records":{"x":{}}}');
        final store = newStore();
        expect(await store.read(ref('x')), isNull);
        expect(
          await store.write(buildRecord(id: 'new')),
          StoreWriteResult.failed,
        );
        expect(
          await store.recordFirstSeen(ref('x'), DateTime.utc(2026)),
          StoreWriteResult.failed,
        );
        // The foreign-schema payload was never rewritten.
        expect(stateFile.readAsStringSync(), contains('"schema":99'));
      },
    );

    test('non-String seen values decode as absent, not a crash', () async {
      await stateFile.writeAsString(
        jsonEncode({
          'schema': ArticleRecordStore.schemaVersion,
          'records': {},
          'seen': {ref('x').key: 42},
        }),
      );
      final store = newStore();
      expect(await store.firstSeen(ref('x')), isNull);
      expect(
        await store.recordFirstSeen(ref('x'), DateTime.utc(2026, 3, 1)),
        StoreWriteResult.applied,
      );
      expect(await store.firstSeen(ref('x')), DateTime.utc(2026, 3, 1));
    });

    test('lock timeout surfaces as failed, not an exception', () async {
      // A fresh lock file held by a fake owner: mutations time out.
      File('${stateFile.path}.lock').writeAsStringSync(
        'other-owner\n${DateTime.now().toUtc().toIso8601String()}',
      );
      final store = ArticleRecordStore(
        FileObservedArticlePersistence(
          stateFile: stateFile,
          lockTimeout: const Duration(milliseconds: 100),
          retryDelay: const Duration(milliseconds: 10),
        ),
      );
      expect(
        await store.write(buildRecord(id: 'blocked')),
        StoreWriteResult.failed,
      );
    });

    test('a stale lock left by a killed writer is stolen', () async {
      File('${stateFile.path}.lock').writeAsStringSync(
        'dead-owner\n${DateTime.utc(2000).toIso8601String()}',
      );
      expect(
        await newStore().write(buildRecord(id: 'recovered')),
        StoreWriteResult.applied,
      );
      expect(await newStore().read(ref('recovered')), isNotNull);
    });

    test(
      'interleaved instances serialize read-modify-write through the lock',
      () async {
        // Two stores on the same file stand in for foreground + background
        // isolates: every mutation must apply on top of the latest on-disk
        // state, not a stale snapshot.
        final a = newStore();
        final b = newStore();
        await a.write(buildRecord(id: 'shared', generation: 1));

        ArticleRecord? bump(ArticleRecord? c) =>
            c!.copyWith(attempts: c.attempts + 1, generation: c.generation);
        await Future.wait([
          a.mutate(ref('shared'), bump),
          b.mutate(ref('shared'), bump),
          a.mutate(ref('shared'), bump),
          b.mutate(ref('shared'), bump),
        ]);
        expect((await newStore().read(ref('shared')))!.attempts, 4);
      },
    );

    test(
      'a separate isolate serializes mutations through the same lock file',
      () async {
        // Real cross-isolate contention: the spawned isolate loses the CAS
        // when the foreground tombstones first.
        await newStore().write(buildRecord(id: 'raced', generation: 1));
        final path = stateFile.path;
        final raced = ref('raced');

        final remote = Isolate.run(() async {
          final store = ArticleRecordStore(
            FileObservedArticlePersistence(stateFile: File(path)),
          );
          await store.tombstone(raced);
        });
        await remote;

        final local = await newStore().writeIfGeneration(
          buildRecord(id: 'raced', generation: 1),
          1,
        );
        expect(local, StoreWriteResult.rejected);
        expect((await newStore().read(ref('raced')))!.tombstoned, isTrue);
      },
    );

    test('forBox anchors the state file next to the Hive box', () async {
      final boxDir = Directory(
        '${tempDir.path}/hive_${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
      final box = await Hive.openBox('feeds', path: boxDir.path);
      addTearDown(() => box.close());
      final store = ArticleRecordStore.forBox(box);
      expect(
        await store.write(buildRecord(id: 'anchored')),
        StoreWriteResult.applied,
      );
      expect(await store.read(ref('anchored')), isNotNull);
      expect(File('${box.path}.article-archive.v2.json').existsSync(), isTrue);
    });
  });

  group('firstSeen', () {
    test('earliest observation wins and survives restart', () async {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final t2 = DateTime.utc(2026, 1, 2, 10);

      expect(
        await newStore().recordFirstSeen(ref('art-2'), t1),
        StoreWriteResult.applied,
      );
      await newStore().recordFirstSeen(ref('art-2'), t2);
      expect(await newStore().firstSeen(ref('art-2')), t1);

      // Fresh store on the same file — the value really came from disk.
      expect(await newStore().firstSeen(ref('art-2')), t1);
    });

    test('records one firstSeen per distinct article', () async {
      final t = DateTime.utc(2026, 2, 1);
      await newStore().recordFirstSeen(ref('a'), t);
      await newStore().recordFirstSeen(
        ref('b'),
        t.add(const Duration(hours: 1)),
      );
      expect(await newStore().firstSeen(ref('a')), t);
      expect(
        await newStore().firstSeen(ref('b')),
        t.add(const Duration(hours: 1)),
      );
    });
  });

  group('generation fence', () {
    test('write carrying the current generation is applied', () async {
      final store = newStore();
      await store.write(buildRecord(id: 'art-3', generation: 3));

      final update = buildRecord(
        id: 'art-3',
        generation: 3,
        owners: {'bookmark', 'tempCache'},
      );
      expect(
        await store.writeIfGeneration(update, 3),
        StoreWriteResult.applied,
      );
      expect((await store.read(ref('art-3')))!.owners, {
        'bookmark',
        'tempCache',
      });
    });

    test('stale-generation writes are rejected, record unchanged', () async {
      final store = newStore();
      await store.write(buildRecord(id: 'art-4', generation: 5));

      final stale = buildRecord(id: 'art-4', generation: 2, body: 'stale body');
      expect(
        await store.writeIfGeneration(stale, 2),
        StoreWriteResult.rejected,
      );
      expect((await store.read(ref('art-4')))!.body, 'Body of art-4');
    });

    test(
      'record whose generation mismatches the expected is rejected',
      () async {
        final store = newStore();
        await store.write(buildRecord(id: 'art-4b', generation: 5));
        final mismatch = buildRecord(id: 'art-4b', generation: 9);
        expect(
          await store.writeIfGeneration(mismatch, 5),
          StoreWriteResult.rejected,
        );
        expect((await store.read(ref('art-4b')))!.generation, 5);
      },
    );

    test('writes to a tombstoned record are rejected', () async {
      final store = newStore();
      await store.write(buildRecord(id: 'art-5', generation: 1));
      expect(await store.tombstone(ref('art-5')), StoreWriteResult.applied);
      expect(await store.isTombstoned(ref('art-5')), isTrue);

      final zombie = buildRecord(id: 'art-5', generation: 2);
      expect(
        await store.writeIfGeneration(zombie, 2),
        StoreWriteResult.rejected,
      );
      expect((await store.read(ref('art-5')))!.tombstoned, isTrue);
      expect((await store.read(ref('art-5')))!.body, isNull);
    });

    test('tombstone survives a restart', () async {
      await newStore().write(buildRecord(id: 'art-5b', generation: 1));
      await newStore().tombstone(ref('art-5b'));
      final read = await newStore().read(ref('art-5b'));
      expect(read!.tombstoned, isTrue);
      expect(read.generation, 2);
    });

    test('tombstoning a never-existing id still records the fence', () async {
      expect(
        await newStore().tombstone(ref('art-ghost')),
        StoreWriteResult.applied,
      );
      final read = await newStore().read(ref('art-ghost'));
      expect(read!.tombstoned, isTrue);
      expect(read.generation, 1);
      expect(
        await newStore().writeIfGeneration(
          buildRecord(id: 'art-ghost', generation: 1),
          1,
        ),
        StoreWriteResult.rejected,
      );
    });

    test('write into a never-created record is rejected', () async {
      final store = newStore();
      final ghost = buildRecord(id: 'art-6', generation: 1);
      expect(
        await store.writeIfGeneration(ghost, 1),
        StoreWriteResult.rejected,
      );
      expect(await store.read(ref('art-6')), isNull);
    });
  });

  group('ArticleMediaStore', () {
    test('written bytes read back identical and verify', () async {
      final media = ArticleMediaStore(root: mediaDir);
      final bytes = List.generate(64, (i) => i);

      final entry = await media.put('https://example.com/a.png', bytes);
      expect(entry.byteSize, 64);
      expect(await media.verify(entry), isTrue);
      expect(await media.read(entry), bytes);
    });

    test('same url resolves to the same file', () async {
      final media = ArticleMediaStore(root: mediaDir);
      final a = await media.put('https://example.com/a.png', [1, 2, 3]);
      final b = await media.put('https://example.com/a.png', [1, 2, 3]);
      expect(a.file, b.file);
      expect(a.file, matches(RegExp(r'^m_[0-9a-f]{16}$')));
      expect(
        ArticleMediaStore.fileNameFor('https://example.com/a.png'),
        a.file,
      );
    });

    test('pendingEntry marks the manifest before bytes land', () {
      final entry = ArticleMediaStore.pendingEntry('https://example.com/p.png');
      expect(entry.state, MediaState.pending);
      expect(entry.byteSize, 0);
      expect(entry.file, matches(RegExp(r'^m_[0-9a-f]{16}$')));
    });

    test('empty payloads are refused instead of persisted as ready', () async {
      final media = ArticleMediaStore(root: mediaDir);
      expect(
        () => media.put('https://example.com/empty.png', const []),
        throwsArgumentError,
      );
    });

    test('verify is false when the file is missing', () async {
      final media = ArticleMediaStore(root: mediaDir);
      const entry = MediaEntry(
        file: 'm_0000000000000000',
        byteSize: 10,
        state: MediaState.ready,
      );
      expect(await media.verify(entry), isFalse);
      expect(await media.read(entry), isNull);
    });

    test('tampered manifest file names cannot escape the pool', () async {
      final media = ArticleMediaStore(root: mediaDir);
      const entry = MediaEntry(
        file: '../../escape',
        byteSize: 1,
        state: MediaState.ready,
      );
      expect(await media.verify(entry), isFalse);
      expect(await media.read(entry), isNull);
      await media.delete('../../escape'); // must not throw
    });

    test(
      'unreferencedFiles skips files owned by any record and reports orphans',
      () async {
        final media = ArticleMediaStore(root: mediaDir);
        final shared = await media.put('https://example.com/shared.png', [1]);
        final orphan = await media.put('https://example.com/orphan.png', [2]);
        final own = await media.put('https://example.com/own.png', [3]);
        // A foreign file in the pool is never a cleanup target.
        File('${mediaDir.path}/notes.txt').writeAsStringSync('x');

        final records = [
          buildRecord(
            id: 'a',
            media: {'https://example.com/shared.png': shared},
          ),
          buildRecord(
            id: 'b',
            media: {
              'https://example.com/shared.png': shared,
              'https://example.com/own.png': own,
            },
          ),
        ];
        final orphans = await media.unreferencedFiles(records);
        expect(orphans, contains(orphan.file));
        expect(orphans, isNot(contains(shared.file)));
        expect(orphans, isNot(contains(own.file)));
        expect(orphans, isNot(contains('notes.txt')));
      },
    );

    test('delete removes the file', () async {
      final media = ArticleMediaStore(root: mediaDir);
      final entry = await media.put('https://example.com/x.png', [9]);
      await media.delete(entry.file);
      expect(await media.verify(entry), isFalse);
    });
  });
}
