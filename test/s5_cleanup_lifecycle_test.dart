import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Color, Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_cleanup_service.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';
import 'package:ice_cream_rss_reader/services/observed_article_store.dart';
import 'package:ice_cream_rss_reader/services/temp_cache_membership.dart';

/// Store that lets a test run [onMutate] once right before the next
/// [mutate] — simulates a competing isolate writing between the sweep's
/// snapshot read and its locked tombstone mutation.
class _HookedStore extends ArticleRecordStore {
  _HookedStore(super.persistence);

  Future<void> Function()? onMutate;

  @override
  Future<StoreWriteResult> mutate(
    ArticleRef ref,
    ArticleRecord? Function(ArticleRecord? current) update, {
    int? expectedEpoch,
  }) async {
    final hook = onMutate;
    if (hook != null) {
      onMutate = null;
      await hook();
    }
    return super.mutate(ref, update, expectedEpoch: expectedEpoch);
  }
}

/// Media store whose deletions can be failed on demand.
class _FailingMedia extends ArticleMediaStore {
  _FailingMedia({super.root});

  var fail = false;

  @override
  Future<bool> delete(String file) =>
      fail ? Future<bool>.value(false) : super.delete(file);
}

void main() {
  late Directory tempDir;
  late File stateFile;
  late Directory mediaDir;
  var stamp = 0;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('s5_cleanup_test_');
  });

  setUp(() {
    stamp++;
    stateFile = File('${tempDir.path}/state_$stamp.json');
    mediaDir = Directory('${tempDir.path}/media_$stamp')
      ..createSync(recursive: true);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  ArticleRef ref(String id) => ArticleRef('https://f.com/feed', id);

  ArticleRecordStore newStore() =>
      ArticleRecordStore(FileObservedArticlePersistence(stateFile: stateFile));

  ArticlePreparationService newPrep() => ArticlePreparationService(
    recordStore: newStore(),
    mediaStore: ArticleMediaStore(root: mediaDir),
    client: http_testing.MockClient((_) async => http.Response('x', 404)),
  );

  ArticleCleanupService newSweep() => ArticleCleanupService(
    records: newStore(),
    media: ArticleMediaStore(root: mediaDir),
  );

  ArticleRecord record(
    String id, {
    Set<String> owners = const {'tempCache'},
    Map<String, MediaEntry> media = const {},
    bool tombstoned = false,
  }) => ArticleRecord(
    id: id,
    feedUrl: 'https://f.com/feed',
    owners: owners,
    media: media,
    tombstoned: tombstoned,
    generation: 1,
  );

  MediaEntry readyEntry(String url, int bytes) => MediaEntry(
    file: ArticleMediaStore.fileNameFor(url),
    byteSize: bytes,
    state: MediaState.ready,
  );

  File mediaFile(String url) =>
      File('${mediaDir.path}/${ArticleMediaStore.fileNameFor(url)}');

  Future<void> writeMedia(String url, List<int> bytes) =>
      mediaFile(url).writeAsBytes(bytes, flush: true);

  group('sweep — tombstone + release', () {
    test(
      'ownerless record is tombstoned and its exclusive file deleted',
      () async {
        final store = newStore();
        await store.write(record('a', media: {'u1': readyEntry('u1', 3)}));
        await store.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));
        await writeMedia('u1', [1, 2, 3]);
        mediaFile('u1').setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 10)),
        );

        final result = await newSweep().sweep();

        expect(result.failed, isFalse);
        expect(result.tombstoned, 1);
        expect((await store.read(ref('a')))!.tombstoned, isTrue);
        expect(mediaFile('u1').existsSync(), isFalse);
        expect(result.deletedFiles, 1);
      },
    );

    test('file shared with a still-owned record survives the sweep', () async {
      final store = newStore();
      await store.write(record('a', media: {'u1': readyEntry('u1', 3)}));
      await store.write(record('b', media: {'u1': readyEntry('u1', 3)}));
      await store.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));
      await writeMedia('u1', [1, 2, 3]);

      // The sweep can't collect instantly — orphans need the grace period.
      // Backdate the file past the grace to simulate a settled write.
      mediaFile('u1').setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );

      await newSweep().sweep();

      expect(mediaFile('u1').existsSync(), isTrue);
    });

    test('exclusive file older than the grace period is collected', () async {
      final store = newStore();
      await store.write(record('a', media: {'u1': readyEntry('u1', 3)}));
      await store.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));
      await writeMedia('u1', [1, 2, 3]);
      mediaFile('u1').setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );

      final result = await newSweep().sweep();

      expect(result.deletedFiles, 1);
      expect(mediaFile('u1').existsSync(), isFalse);
    });

    test('freshly landed orphan survives — it may be mid-commit', () async {
      final store = newStore();
      await store.write(record('a', media: {'u1': readyEntry('u1', 3)}));
      await store.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));
      await writeMedia('u1', [1, 2, 3]); // mtime = now, inside the grace

      await newSweep().sweep();

      expect(mediaFile('u1').existsSync(), isTrue);
    });

    test('still-owned record and its files are untouched', () async {
      final store = newStore();
      await store.write(record('a', media: {'u1': readyEntry('u1', 3)}));
      await writeMedia('u1', [1, 2, 3]);
      mediaFile('u1').setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );

      final result = await newSweep().sweep();

      expect(result.tombstoned, 0);
      expect(result.deletedFiles, 0);
      expect((await store.read(ref('a')))!.tombstoned, isFalse);
      expect(mediaFile('u1').existsSync(), isTrue);
    });

    test('foreign files in the media directory are never touched', () async {
      final store = newStore();
      await store.write(record('a', media: {'u1': readyEntry('u1', 3)}));
      await store.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));
      final foreign = File('${mediaDir.path}/user_photo.jpg')
        ..writeAsBytesSync([9, 9]);
      foreign.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 7)),
      );

      await newSweep().sweep();

      expect(foreign.existsSync(), isTrue);
    });
  });

  group('sweep — fail closed', () {
    test(
      'undecodable store state deletes nothing and reports failure',
      () async {
        stateFile.writeAsStringSync('{"schema": 999, "junk": true}');
        await writeMedia('u1', [1, 2, 3]);
        mediaFile('u1').setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 10)),
        );

        final result = await newSweep().sweep();

        expect(result.failed, isTrue);
        expect(result.deletedFiles, 0);
        expect(mediaFile('u1').existsSync(), isTrue);
      },
    );

    test('a corrupt records container is not coerced to empty — nothing is '
        'deleted or mutated', () async {
      // Valid schema, wrong container type: coercing to {} would let the
      // GC "prove" every managed file unreferenced.
      stateFile.writeAsStringSync(
        '{"schema": ${ArticleRecordStore.schemaVersion}, "records": "garbage", '
        '"seen": {}, "epoch": 5}',
      );
      await writeMedia('u1', [1, 2, 3]);
      mediaFile('u1').setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );

      final gc = await newStore().listRecordsForGc();
      expect(gc.clean, isFalse);

      final result = await newSweep().sweep();
      expect(result.failed, isTrue);
      expect(result.deletedFiles, 0);
      expect(mediaFile('u1').existsSync(), isTrue);

      // Mutations also fail closed — unknown data is never overwritten.
      final write = await newStore().mutate(ref('a'), (current) => record('a'));
      expect(write, StoreWriteResult.failed);
    });
  });

  group('sweep — observation stamps', () {
    test('seen entry of a tombstoned record is pruned', () async {
      final store = newStore();
      await store.write(record('a'));
      await store.recordFirstSeen(ref('a'), DateTime.utc(2026, 1, 1));
      await store.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));

      final result = await newSweep().sweep();

      expect(result.prunedSeen, 1);
      expect(await store.firstSeen(ref('a')), isNull);
    });

    test('seen entry with no record is kept — the subscription may still '
        'carry that dateless candidate', () async {
      final store = newStore();
      await store.recordFirstSeen(ref('ghost'), DateTime.utc(2026, 1, 1));

      final result = await newSweep().sweep();

      expect(result.prunedSeen, 0);
      expect(await store.firstSeen(ref('ghost')), isNotNull);
    });
  });

  FeedItem item(String id) => FeedItem(
    id: id,
    siteName: 'F',
    title: 't',
    description: 'd',
    timeAgo: 'now',
    siteIcon: Icons.rss_feed,
    iconColor: const Color(0xFF000000),
    iconBackgroundColor: const Color(0xFFFFFFFF),
    link: 'https://f.com/$id',
    feedUrl: 'https://f.com/feed',
    pubDate: DateTime.utc(2026, 1, 1),
  );

  group('register-queue ordering — no resurrection', () {
    test(
      'strip enqueued after a delayed register still wins the final state',
      () async {
        final store = newStore();
        final prep = newPrep();
        // The register runs first on the FIFO register queue, then the
        // strip — mirroring a fast add→remove toggle.
        final registered = prep.registerArticle(item('a'), const {'bookmark'});
        final stripped = prep.mutateRecord(ref('a'), (current) {
          if (current == null) return current;
          final owners = {...current.owners}..remove('bookmark');
          return current.copyWith(owners: owners);
        });
        await registered;
        await stripped;

        expect((await store.read(ref('a')))!.owners, isEmpty);
      },
    );

    test('register enqueued after a strip revives as a new claim', () async {
      final store = newStore();
      final prep = newPrep();
      await store.write(record('a', owners: const {'bookmark'}));
      await prep.mutateRecord(ref('a'), (current) {
        final owners = {...current!.owners}..remove('bookmark');
        return current.copyWith(owners: owners);
      });
      await prep.sweepCleanup(); // ownerless → tombstoned
      expect((await store.read(ref('a')))!.tombstoned, isTrue);

      // A re-bookmark is a deliberate new claim — revive is legitimate.
      await prep.registerArticle(item('a'), const {'bookmark'});

      final revived = await store.read(ref('a'));
      expect(revived!.tombstoned, isFalse);
      expect(revived.owners, contains('bookmark'));
    });

    test('resetFence no-ops mutations enqueued before the reset', () async {
      final store = newStore();
      final prep = newPrep();
      // The register captures the queue epoch at enqueue time; the queued
      // work runs on a later microtask, so resetFence — synchronous here —
      // always lands first. This mirrors a reset mid-registration.
      final stale = prep.registerArticle(item('a'), const {'bookmark'});
      prep.resetFence();

      expect(await stale, StoreWriteResult.rejected);
      expect(await store.read(ref('a')), isNull);
    });
  });

  group('lifecycle epoch — reset fencing', () {
    test('wipeAll bumps the epoch', () async {
      final store = newStore();
      final before = await store.currentEpoch();
      await store.wipeAll();
      expect(await store.currentEpoch(), greaterThan(before));
    });

    test('mutation carrying a pre-wipe epoch is rejected', () async {
      final store = newStore();
      final epoch = await store.currentEpoch();
      await store.wipeAll();

      final result = await store.mutate(
        ref('a'),
        expectedEpoch: epoch,
        (current) => record('a'),
      );

      expect(result, StoreWriteResult.rejected);
      expect(await store.read(ref('a')), isNull);
    });

    test('mutation without a fence still applies after the wipe', () async {
      final store = newStore();
      await store.wipeAll();
      final result = await store.mutate(ref('a'), (current) => record('a'));
      expect(result, StoreWriteResult.applied);
    });

    test(
      'bumpEpoch rejects pre-bump fences without touching records',
      () async {
        final store = newStore();
        await store.write(record('a', owners: const {'tempCache'}));
        final epoch = await store.currentEpoch();

        expect(await store.bumpEpoch(), isTrue);

        // A mutation fenced to the pre-bump epoch is rejected…
        final stale = await store.mutate(
          ref('a'),
          expectedEpoch: epoch,
          (current) => current!.copyWith(owners: const {}),
        );
        expect(stale, StoreWriteResult.rejected);
        // …while the record itself is untouched — this is a fence, not a wipe.
        expect((await store.read(ref('a')))!.owners, contains('tempCache'));
        // Monotonic even against a same-microsecond rewrite.
        expect(await store.currentEpoch(), greaterThan(epoch));
      },
    );

    test(
      'reconcile carrying a pre-reset epoch registers nothing after the wipe',
      () async {
        final store = newStore();
        final prep = newPrep();
        final membership = TempCacheMembership(
          records: store,
          preparation: prep,
        );
        final epoch = await store.currentEpoch();
        await store.wipeAll();

        await membership.reconcile(
          items: [item('a')],
          isBookmarked: (_) => false,
          subscribedFeedUrls: const ['https://f.com/feed'],
          globalKeywords: const [],
          feedKeywordsMap: const {},
          limit: 10,
          fullTextFor: (_) => false,
          epoch: epoch,
        );

        expect(await store.read(ref('a')), isNull);
      },
    );
  });

  group('deleteAllManaged', () {
    test('removes managed and staging files, keeps foreign content', () async {
      await writeMedia('u1', [1, 2, 3]);
      File('${mediaDir.path}/m_abc.tmp.123_0_9').writeAsBytesSync([7]);
      File('${mediaDir.path}/user_note.txt').writeAsBytesSync([1]);

      final deleted = await ArticleMediaStore(
        root: mediaDir,
      ).deleteAllManaged();

      expect(deleted, 2);
      expect(mediaFile('u1').existsSync(), isFalse);
      expect(File('${mediaDir.path}/user_note.txt').existsSync(), isTrue);
    });
  });

  group('stale staging sweep', () {
    test('lists the pool once per store, not on every access', () async {
      final store = ArticleMediaStore(root: mediaDir);
      final stale = DateTime.now().subtract(const Duration(days: 2));
      const entry = MediaEntry(
        file: 'm_0000000000000000',
        byteSize: 1,
        state: MediaState.ready,
      );
      File staleTemp(String name) =>
          File('${mediaDir.path}/$name.tmp.1_0_0')
            ..writeAsBytesSync([1])
            ..setLastModifiedSync(stale);

      final first = staleTemp('m_a');
      await store.verify(entry);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(first.existsSync(), isFalse);

      final second = staleTemp('m_b');
      await store.verify(entry);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(second.existsSync(), isTrue);
    });
  });

  group('sweep — conditional tombstone', () {
    test('an owner claimed between the snapshot and the locked tombstone '
        'mutation survives — the recheck must win', () async {
      final hooked = _HookedStore(
        FileObservedArticlePersistence(stateFile: stateFile),
      );
      final competing = newStore();
      await hooked.write(record('a'));
      await hooked.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));

      final sweep = ArticleCleanupService(
        records: hooked,
        media: ArticleMediaStore(root: mediaDir),
      );
      // The sweep's first mutate is its tombstone attempt — a competing
      // claim lands just before the lock is taken, exactly the cross-
      // isolate ordering the conditional check exists for.
      hooked.onMutate = () => competing.mutate(
        ref('a'),
        (c) => c!.copyWith(owners: const {'tempCache'}),
      );

      final result = await sweep.sweep();

      final a = await competing.read(ref('a'));
      expect(a!.tombstoned, isFalse);
      expect(a.owners, contains('tempCache'));
      expect(result.tombstoned, 0);
    });
  });

  group('register — claimCheck', () {
    test('rescinded claim inside the lock adds no owner to a record', () async {
      final store = newStore();
      final prep = newPrep();
      await store.write(record('a', owners: const {'tempCache'}));

      await prep.registerArticle(item('a'), const {
        'bookmark',
      }, claimCheck: () => false);

      expect((await store.read(ref('a')))!.owners, isNot(contains('bookmark')));
    });

    test('rescinded claim creates no record at all', () async {
      final store = newStore();
      final prep = newPrep();

      await prep.registerArticle(item('b'), const {
        'bookmark',
      }, claimCheck: () => false);

      expect(await store.read(ref('b')), isNull);
    });

    test('live claim registers normally', () async {
      final store = newStore();
      final prep = newPrep();

      final result = await prep.registerArticle(item('c'), const {
        'bookmark',
      }, claimCheck: () => true);

      expect(result, StoreWriteResult.applied);
      expect((await store.read(ref('c')))!.owners, contains('bookmark'));
    });
  });

  group('sweep — stale bookmark reconcile', () {
    test('a bookmark claim the live set denies is stripped, then tombstoned '
        'on the next pass', () async {
      final store = newStore();
      await store.write(record('a', owners: const {'bookmark'}));

      await newSweep().sweep(isBookmarked: (_) => false);
      expect((await store.read(ref('a')))!.owners, isNot(contains('bookmark')));
      // The tombstone pass saw the pre-strip snapshot — the next sweep
      // completes the lifecycle for the now-ownerless record.
      await newSweep().sweep();
      expect((await store.read(ref('a')))!.tombstoned, isTrue);
    });

    test('a bookmark claim the live set confirms is kept', () async {
      final store = newStore();
      await store.write(record('a', owners: const {'bookmark'}));

      await newSweep().sweep(isBookmarked: (r) => r == ref('a'));

      final a = await store.read(ref('a'));
      expect(a!.tombstoned, isFalse);
      expect(a.owners, contains('bookmark'));
    });

    test('a lost bookmark claim the live set confirms is restored — nothing '
        'else re-adds it', () async {
      final store = newStore();
      // Owner was dropped by a stale strip or failed register — the
      // record is live but missing its 'bookmark' claim.
      await store.write(record('a', owners: const {'tempCache'}));

      await newSweep().sweep(isBookmarked: (r) => r == ref('a'));

      expect((await store.read(ref('a')))!.owners, contains('bookmark'));
    });
  });

  group('prepare — lifecycle epoch fence', () {
    test('a media commit finishing after wipeAll cannot mark the new-era '
        'record ready', () async {
      final store = newStore();
      final manifest = <String, MediaEntry>{
        'u': MediaEntry(
          file: ArticleMediaStore.fileNameFor('u'),
          byteSize: 9,
          state: MediaState.pending,
        ),
      };
      await store.write(record('a', media: manifest));

      final fetchStarted = Completer<void>();
      final gate = Completer<http.Response>();
      final prep = ArticlePreparationService(
        recordStore: store,
        mediaStore: ArticleMediaStore(root: mediaDir),
        client: http_testing.MockClient((_) async {
          if (!fetchStarted.isCompleted) fetchStarted.complete();
          return gate.future;
        }),
        extractFullText: (_) async => null,
      );

      final running = prep.prepareArticle(ref('a'));
      // The fetch is in flight — the record read and epoch capture of
      // this pass both belong to the pre-wipe era.
      await fetchStarted.future;

      await store.wipeAll();
      // New era: the member is legitimately re-claimed with a pending
      // manifest — the stale commit must not resolve it.
      await store.write(record('a', media: manifest));

      gate.complete(http.Response('img-bytes', 200));
      await running;

      final a = await store.read(ref('a'));
      expect(a!.media['u']!.state, MediaState.pending);
    });
  });

  group('sweep — failed media deletion', () {
    test('a refused delete is counted honestly as a failure', () async {
      final store = newStore();
      await store.write(record('a', media: {'u1': readyEntry('u1', 3)}));
      await store.mutate(ref('a'), (c) => c!.copyWith(owners: const {}));
      await writeMedia('u1', [1, 2, 3]);
      mediaFile('u1').setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );

      final media = _FailingMedia(root: mediaDir)..fail = true;
      final result = await ArticleCleanupService(
        records: store,
        media: media,
      ).sweep();

      expect(result.failed, isTrue);
      expect(result.deletedFiles, 0);
      expect(mediaFile('u1').existsSync(), isTrue);
    });
  });

  group('observed store — reset boundary', () {
    test('wipeAll forgets observation history entirely', () async {
      final obsFile = File('${tempDir.path}/obs_$stamp.json');
      final observed = ObservedArticleStore(
        FileObservedArticlePersistence(stateFile: obsFile),
      );
      const feedUrl = 'https://f.com/feed';
      await observed.claimFeedBatch(feedUrl: feedUrl, items: [item('a')]);
      final steady = await observed.claimFeedBatch(
        feedUrl: feedUrl,
        items: [item('b')],
      );
      expect(steady.claimedItems, isNotEmpty); // initialized state works

      await observed.wipeAll();

      final after = await observed.claimFeedBatch(
        feedUrl: feedUrl,
        items: [item('b')],
      );
      // A wiped store behaves like first launch: re-initializes, claims
      // nothing — the old "already seen" proof is gone.
      expect(after.initializedFeed, isTrue);
      expect(after.claimedItems, isEmpty);
    });
  });
}
