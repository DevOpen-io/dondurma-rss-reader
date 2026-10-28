import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_cleanup_service.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/lifecycle_coordinator.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';
import 'package:ice_cream_rss_reader/services/observed_article_store.dart';
import 'package:ice_cream_rss_reader/services/temp_cache_membership.dart';

FeedItem _item(String source) => FeedItem(
  id: 'shared-guid',
  siteName: source,
  title: 'Title $source',
  description: '',
  feedUrl: 'https://$source.test/feed',
  link: 'https://$source.test/article',
  content: '<p>Body $source</p>',
  pubDate: DateTime.utc(2026, 10, 24),
);

ArticleRecordStore _fileStore(String path) =>
    ArticleRecordStore(FileObservedArticlePersistence(stateFile: File(path)));

// Pauses a writer before lock acquisition, not inside its critical section.
// Another store can complete wipeAll while the stale mutation is waiting.
class _BeforeLock implements ObservedArticlePersistence {
  _BeforeLock(this.delegate, {this.pauseOn = 1});
  final ObservedArticlePersistence delegate;
  final int pauseOn;
  final waiting = Completer<void>();
  final release = Completer<void>();
  int _calls = 0;
  @override
  Future<String?> read() => delegate.read();
  @override
  Future<void> write(String value) => delegate.write(value);
  @override
  Future<ExclusiveResult<T>> runExclusive<T>(
    Future<T> Function() action,
  ) async {
    if (++_calls == pauseOn) {
      waiting.complete();
      await release.future;
    }
    return delegate.runExclusive(action);
  }
}

class _BeforeWrite implements ObservedArticlePersistence {
  _BeforeWrite(this.delegate);
  final ObservedArticlePersistence delegate;
  final writing = Completer<void>();
  final release = Completer<void>();
  bool _paused = false;
  @override
  Future<String?> read() => delegate.read();
  @override
  Future<void> write(String value) async {
    if (!_paused) {
      _paused = true;
      writing.complete();
      await release.future;
    }
    await delegate.write(value);
  }

  @override
  Future<ExclusiveResult<T>> runExclusive<T>(Future<T> Function() action) =>
      delegate.runExclusive(action);
}

class _AfterOrphanScanMedia extends ArticleMediaStore {
  _AfterOrphanScanMedia({required super.root, required this.afterScan});
  final Future<void> Function() afterScan;

  @override
  Future<List<String>> unreferencedFiles(
    Iterable<ArticleRecord> records, {
    Duration minAge = Duration.zero,
  }) async {
    final candidates = await super.unreferencedFiles(records, minAge: minAge);
    await afterScan();
    return candidates;
  }
}

class _SnapshotHookStore extends ArticleRecordStore {
  _SnapshotHookStore(super.persistence);
  Future<void> Function()? afterSnapshot;
  Future<void> _hook() async {
    final action = afterSnapshot;
    afterSnapshot = null;
    await action?.call();
  }

  @override
  Future<ArticleRecord?> read(ArticleRef ref) async {
    final result = await super.read(ref);
    await _hook();
    return result;
  }

  @override
  Future<List<ArticleRecord>> listRecords() async {
    final result = await super.listRecords();
    await _hook();
    return result;
  }
}

Future<void> _registerRemote(String path, Map<String, dynamic> json) async {
  final prep = ArticlePreparationService(recordStore: _fileStore(path));
  try {
    await prep.registerArticle(FeedItem.fromJson(json), {
      'tempCache',
    }, fullText: false);
  } finally {
    prep.dispose();
  }
}

Future<void> _lateRemoteWriter(List<Object> args) async {
  // Optional lifecycle directory: a gated writer captures its ticket first,
  // before any input or epoch read, exactly like a background task.
  final gate = args.length > 3
      ? LifecycleCoordinator(directory: Directory(args[3] as String))
      : null;
  final ticket = await gate?.beginWork();
  final archive = _fileStore(args[0] as String);
  final observation = ObservedArticleStore(
    FileObservedArticlePersistence(stateFile: File(args[1] as String)),
    gate: gate,
  );
  final output = args[2] as SendPort;
  final continuePort = ReceivePort();
  final epoch = await archive.currentEpoch();
  output.send(continuePort.sendPort);
  await continuePort.first;
  continuePort.close();
  final service = ArticlePreparationService(recordStore: archive);
  final registered = await service.registerArticle(
    _item('a'),
    {'tempCache'},
    expectedEpoch: epoch,
    fullText: false,
  );
  final claimed = await observation.claimFeedBatch(
    feedUrl: _item('a').feedUrl,
    observationEpoch: 'old-subscription',
    items: [_item('a')],
    ticket: ticket,
  );
  service.dispose();
  output.send([registered.name, claimed.initializedFeed]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String path;
  late ArticleRecordStore records;
  late ArticleMediaStore media;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('durable-identity-followup-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
    path = '${root.path}/archive.json';
    records = _fileStore(path);
    media = ArticleMediaStore(root: Directory('${root.path}/media'));
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  ArticlePreparationService prep({
    ArticleRecordStore? store,
    Future<String?> Function(String)? extract,
  }) => ArticlePreparationService(
    recordStore: store ?? records,
    mediaStore: media,
    client: MockClient((_) async => http.Response('', 404)),
    extractFullText: extract,
    minHostGap: Duration.zero,
  );

  // Formerly KNOWN characterizations of the shared-GUID defect. Setups are
  // unchanged; the assertions now require independent source identity.
  test('FeedItem equality is per source, like ArticleRef', () {
    final a = _item('a');
    final b = _item('b');
    expect(a.id, b.id);
    expect(a == b, isFalse);
    expect({a, b}, hasLength(2));
    // Same source, same normalized id: the same article instance.
    final again = a.copyWith(id: ' shared-guid ', title: 'Edited');
    expect(again, a);
    expect(again.hashCode, a.hashCode);
  });

  group('source-local durable identity (formerly KNOWN limitations)', () {
    test(
      'independent bookmark snapshots restore into separate offline records',
      () async {
        final a = _item('a');
        final b = _item('b');
        await Hive.box('bookmarks').put(
          'bookmarkedItemsJson',
          jsonEncode([
            a.copyWith(isBookmarked: true).toJson(),
            b.copyWith(isBookmarked: true).toJson(),
          ]),
        );
        final service = prep();
        final bookmarks = BookmarkProvider(
          preparation: service,
          fullTextFor: (_) => false,
        );
        await bookmarks.restoration;
        expect(bookmarks.bookmarkedItems.length, 2);
        final archive = await records.listRecords();
        expect(
          archive.length,
          2,
          reason: 'A shared GUID must not alias durable identity',
        );
        final byFeed = {for (final r in archive) r.feedUrl: r};
        expect(byFeed[a.feedUrl]!.body, a.content);
        expect(byFeed[a.feedUrl]!.link, a.link);
        expect(byFeed[b.feedUrl]!.body, b.content);
        expect(byFeed[b.feedUrl]!.title, b.title);
        final page = ArticlePageProvider(item: b.copyWith(isBookmarked: true));
        await page.loadSavedCopy(records: records, media: media);
        expect(
          page.rawContent,
          b.content,
          reason: 'B displays its own saved body',
        );
        page.dispose();
        bookmarks.dispose();
        service.dispose();
      },
    );

    test(
      'interrupted restoration preserves snapshots and restart restores both instances',
      () async {
        final snapshots = [_item('a').toJson(), _item('b').toJson()];
        await Hive.box(
          'bookmarks',
        ).put('bookmarkedItemsJson', jsonEncode(snapshots));
        final paused = _BeforeLock(
          FileObservedArticlePersistence(stateFile: File(path)),
          pauseOn: 2,
        );
        final interrupted = prep(store: ArticleRecordStore(paused));
        final first = BookmarkProvider(
          preparation: interrupted,
          fullTextFor: (_) => false,
        );
        await paused.waiting.future; // A committed; B waiting for the lock.
        expect((await records.listRecords()).single.body, _item('a').content);
        interrupted.resetFence();
        paused.release.complete();
        await first.restoration;
        first.dispose();
        interrupted.dispose();
        expect(
          jsonDecode(
            Hive.box('bookmarks').get('bookmarkedItemsJson') as String,
          ),
          snapshots,
        );
        final resumed = prep();
        final restarted = BookmarkProvider(
          preparation: resumed,
          fullTextFor: (_) => false,
        );
        await restarted.restoration;
        expect(restarted.bookmarkedItems.length, 2);
        final byFeed = {
          for (final r in await records.listRecords()) r.feedUrl: r,
        };
        expect(byFeed.length, 2);
        expect(byFeed[_item('a').feedUrl]!.body, _item('a').content);
        expect(byFeed[_item('b').feedUrl]!.body, _item('b').content);
        expect(byFeed[_item('b').feedUrl]!.title, _item('b').title);
        restarted.dispose();
        resumed.dispose();
      },
    );

    test('legacy global read ids bind once to the cached instances', () async {
      await Hive.box('feeds').put('readItemIds', ['shared-guid']);
      await Hive.box(
        'feeds',
      ).put('cachedItemsJson', jsonEncode([_item('a').toJson()]));
      final first = FeedProvider();
      await first.refreshAll(); // Waits for startup, no dependencies/no fetch.
      expect(first.isRead(_item('a')), isTrue);
      // A source that later brings the same GUID inherits nothing.
      expect(first.isRead(_item('b')), isFalse);
      first.dispose();
      expect(Hive.box('feeds').get('readItemIds'), ['shared-guid']);
      final restarted = FeedProvider();
      await restarted.refreshAll();
      expect(restarted.isRead(_item('a')), isTrue);
      restarted.dispose();
    });

    test(
      'read state is per source instance and survives restart (formerly KNOWN)',
      () async {
        await Hive.box('feeds').put(
          'cachedItemsJson',
          jsonEncode([_item('a').toJson(), _item('b').toJson()]),
        );
        final first = FeedProvider();
        await first
            .refreshAll(); // Waits for startup, no dependencies/no fetch.
        await first.markAsRead(
          first.filteredItems.firstWhere(
            (item) => item.feedUrl == _item('a').feedUrl,
          ),
        );
        expect(first.filteredItems.length, 2);
        Map<String, bool> reads(FeedProvider feed) => {
          for (final item in feed.filteredItems) item.feedUrl: item.isRead,
        };
        expect(reads(first), {
          _item('a').feedUrl: true,
          _item('b').feedUrl: false,
        }, reason: 'Marking A must not mark B');
        first.dispose();
        final restarted = FeedProvider();
        await restarted.refreshAll();
        expect(reads(restarted), {
          _item('a').feedUrl: true,
          _item('b').feedUrl: false,
        });
        // The legacy global key is never written by the new schema.
        expect(Hive.box('feeds').get('readItemIds'), isNull);
        restarted.dispose();
      },
    );

    test(
      'temp-cache membership keeps per-source records across unsubscribe',
      () async {
        final service = prep();
        final membership = TempCacheMembership(
          records: records,
          preparation: service,
        );
        Future<Set<ArticleRef>> reconcile(List<FeedItem> items) =>
            membership.reconcile(
              items: items,
              isBookmarked: (_) => false,
              subscribedFeedUrls: items.map((i) => i.feedUrl),
              globalKeywords: [],
              feedKeywordsMap: {},
              limit: 10,
              fullTextFor: (_) => false,
              epoch: null,
            );
        await reconcile([_item('a'), _item('b')]);
        expect(await records.listRecords(), hasLength(2));
        await reconcile([_item('a')]);
        final surviving = (await records.read(ArticleRef.of(_item('a'))))!;
        expect(
          surviving.feedUrl,
          _item('a').feedUrl,
          reason: 'Active A keeps its own archive provenance',
        );
        expect(surviving.body, _item('a').content);
        expect(surviving.owners, {'tempCache'});
        // B's instance lost only its temp claim; its content stays its own.
        final released = (await records.read(ArticleRef.of(_item('b'))))!;
        expect(released.owners, isEmpty);
        expect(released.body, _item('b').content);
        service.dispose();
      },
    );

    test(
      'foreground/background isolates keep owners of different articles apart',
      () async {
        final service = prep();
        await service.registerArticle(_item('a'), {
          'bookmark',
        }, fullText: false);
        final remotePath = path;
        final json = _item('b').toJson();
        await Isolate.run(() => _registerRemote(remotePath, json));
        final a = (await records.read(ArticleRef.of(_item('a'))))!;
        final b = (await records.read(ArticleRef.of(_item('b'))))!;
        expect(a.owners, {'bookmark'});
        expect(b.owners, {'tempCache'});
        expect(a.body, _item('a').content);
        expect(b.title, _item('b').title);
        service.dispose();
      },
    );
  });

  test(
    'ungated writer (no lifecycle gate, reset outside it) recreates history; archive epoch still rejects old ownership',
    () async {
      final observedPath = '${root.path}/observed.json';
      final observation = ObservedArticleStore(
        FileObservedArticlePersistence(stateFile: File(observedPath)),
      );
      final output = ReceivePort();
      final messages = StreamIterator(output);
      await Isolate.spawn(_lateRemoteWriter, <Object>[
        path,
        observedPath,
        output.sendPort,
      ]);
      expect(await messages.moveNext(), isTrue);
      final release = messages.current as SendPort;
      expect(await records.wipeAll(), isTrue);
      expect(await observation.wipeAll(), isTrue);
      await records.write(
        ArticleRecord(
          id: 'shared-guid',
          feedUrl: _item('b').feedUrl,
          body: _item('b').content,
          owners: {'bookmark'},
          generation: 1,
        ),
      );
      release.send(true);
      expect(await messages.moveNext(), isTrue);
      expect(
        messages.current,
        ['rejected', true],
        reason:
            'Without a gate only the archive epoch fences; acceptance B covers the gated path',
      );
      expect(
        (await records.read(ArticleRef.of(_item('b'))))!.body,
        _item('b').content,
      );
      final observedState =
          jsonDecode(await File(observedPath).readAsString()) as Map;
      expect((observedState['feeds'] as Map).length, 1);
      await messages.cancel();
      output.close();
    },
  );

  test(
    'shared media URL keeps one physical file across distinct records',
    () async {
      const image = 'https://images.test/shared.png';
      final a = _item('a').copyWith(id: 'unique-a', imageUrl: image);
      final b = _item('b').copyWith(id: 'unique-b', imageUrl: image);
      final service = ArticlePreparationService(
        recordStore: records,
        mediaStore: media,
        minHostGap: Duration.zero,
        client: MockClient(
          (_) async => http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );
      await service.registerArticle(a, {'bookmark'}, fullText: false);
      await service.registerArticle(b, {'tempCache'}, fullText: false);
      await service.preparePending(unmetered: true);
      final entries = (await records.listRecords())
          .map((r) => r.media[image]!)
          .toList();
      expect(entries.map((e) => e.file).toSet().length, 1);
      expect(await media.verify(entries[0]), isTrue);
      expect(await media.verify(entries[1]), isTrue);
      service.dispose();
    },
  );

  test('media bytes cannot land after reset (formerly KNOWN)', () async {
    final requested = Completer<void>();
    final release = Completer<http.Response>();
    const image = 'https://images.test/old-private.png';
    final service = ArticlePreparationService(
      recordStore: records,
      mediaStore: media,
      minHostGap: Duration.zero,
      client: MockClient((_) {
        requested.complete();
        return release.future;
      }),
    );
    await service.registerArticle(_item('a').copyWith(imageUrl: image), {
      'bookmark',
    }, fullText: false);
    final pending = service.prepareArticle(ArticleRef.of(_item('a')));
    await requested.future;
    service.resetFence();
    expect(await records.wipeAll(), isTrue);
    await media.deleteAllManaged();
    release.complete(
      http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'image/png'},
      ),
    );
    await pending;
    expect(
      await records.listRecords(),
      isEmpty,
    ); // Epoch fence protects the manifest.
    final file = File(
      (await media.pathFor(ArticleMediaStore.fileNameFor(image)))!,
    );
    expect(
      await file.exists(),
      isFalse,
      reason: 'Stale bytes publish only inside the gated era check',
    );
    service.dispose();
  });

  // Positive acceptance assertions, deliberately NOT KNOWN characterizations.
  // These must remain red until the cross-isolate publication protocol exists.
  group('reset publication acceptance', () {
    test(
      'A old media response after completed reset cannot publish a managed file',
      () async {
        final requested = Completer<void>();
        final release = Completer<http.Response>();
        const image = 'https://images.test/pre-reset.png';
        final service = ArticlePreparationService(
          recordStore: records,
          mediaStore: media,
          minHostGap: Duration.zero,
          client: MockClient((_) {
            requested.complete();
            return release.future;
          }),
        );
        addTearDown(service.dispose);
        await service.registerArticle(_item('a').copyWith(imageUrl: image), {
          'bookmark',
        }, fullText: false);
        final pending = service.prepareArticle(ArticleRef.of(_item('a')));
        await requested.future;
        service.resetFence();
        expect(await records.wipeAll(), isTrue);
        await media.deleteAllManaged();
        release.complete(
          http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        await pending;
        expect(await records.listRecords(), isEmpty);
        final file = File(
          (await media.pathFor(ArticleMediaStore.fileNameFor(image)))!,
        );
        expect(
          await file.exists(),
          isFalse,
          reason:
              'A completed reset must fence publication, not only manifest writes',
        );
      },
    );

    test(
      'B real old isolate cannot initialize observation after completed reset',
      () async {
        final observedPath = '${root.path}/observation-acceptance.json';
        final observation = ObservedArticleStore(
          FileObservedArticlePersistence(stateFile: File(observedPath)),
        );
        await observation.claimFeedBatch(
          feedUrl: _item('a').feedUrl,
          observationEpoch: 'old-subscription',
          items: [_item('a')],
        );
        final output = ReceivePort();
        final messages = StreamIterator(output);
        addTearDown(() async {
          await messages.cancel();
          output.close();
        });
        final lifecycle = '${root.path}/lifecycle';
        final gate = LifecycleCoordinator(directory: Directory(lifecycle));
        await Isolate.spawn(_lateRemoteWriter, <Object>[
          path,
          observedPath,
          output.sendPort,
          lifecycle,
        ]);
        expect(await messages.moveNext(), isTrue);
        final release = messages.current as SendPort;
        final reset = await gate.beginReset(
          cleanupStages: ['archive', 'observation'],
        );
        await gate.performCleanupStage(reset, 'archive', () async {
          expect(await records.wipeAll(), isTrue);
        });
        await gate.performCleanupStage(reset, 'observation', () async {
          expect(await observation.wipeAll(), isTrue);
        });
        await gate.completeReset(reset);
        release.send(true);
        expect(await messages.moveNext(), isTrue);
        final result = messages.current as List;
        expect(result.first, 'rejected');
        final state =
            jsonDecode(await File(observedPath).readAsString()) as Map;
        expect(
          state['feeds'],
          isEmpty,
          reason:
              'Archive epoch rejection must also protect observation initialization',
        );
      },
    );

    test(
      'D valid new-generation media download succeeds after reset',
      () async {
        expect(await records.wipeAll(), isTrue);
        await media.deleteAllManaged();
        const image = 'https://images.test/new-generation.png';
        final service = ArticlePreparationService(
          recordStore: records,
          mediaStore: media,
          minHostGap: Duration.zero,
          client: MockClient(
            (_) async => http.Response.bytes(
              [7, 8, 9],
              200,
              headers: {'content-type': 'image/png'},
            ),
          ),
        );
        addTearDown(service.dispose);
        await service.registerArticle(_item('b').copyWith(imageUrl: image), {
          'bookmark',
        }, fullText: false);
        await service.prepareArticle(ArticleRef.of(_item('b')));
        final entry = (await records.read(
          ArticleRef.of(_item('b')),
        ))!.media[image]!;
        expect(entry.state, MediaState.ready);
        expect(await media.read(entry), orderedEquals([7, 8, 9]));
      },
    );

    test(
      'E cleanup rereads references before collecting a newly shared asset',
      () async {
        const image = 'https://images.test/shared-by-current-record.png';
        final entry = await media.put(image, [7, 8, 9]);
        final file = File((await media.pathFor(entry.file))!);
        await file.setLastModified(DateTime(2020));
        await records.write(
          ArticleRecord(
            id: 'old-owner',
            feedUrl: _item('a').feedUrl,
            owners: {},
            generation: 1,
            media: {image: entry},
          ),
        );
        // A second live reference lands after the cleanup snapshot but before
        // its tombstone mutation. Both records reference the SAME managed URL.
        final paused = _BeforeLock(
          FileObservedArticlePersistence(stateFile: File(path)),
        );
        final cleanup = ArticleCleanupService(
          records: ArticleRecordStore(paused),
          media: media,
        );
        final pending = cleanup.sweep();
        await paused.waiting.future;
        await records.write(
          ArticleRecord(
            id: 'current-owner',
            feedUrl: _item('b').feedUrl,
            owners: {'bookmark'},
            generation: 1,
            media: {image: entry},
          ),
        );
        paused.release.complete();
        final result = await pending;
        expect(result.failed, isFalse);
        expect(await file.exists(), isTrue);
        expect(await media.verify(entry), isTrue);
      },
    );

    test(
      'E2 cleanup must not delete an asset claimed after its orphan scan',
      () async {
        const image = 'https://images.test/claimed-after-scan.png';
        final entry = await media.put(image, [7, 8, 9]);
        final file = File((await media.pathFor(entry.file))!);
        await file.setLastModified(DateTime(2020));
        await records.write(
          ArticleRecord(
            id: 'old-owner',
            feedUrl: _item('a').feedUrl,
            owners: {},
            generation: 1,
            media: {image: entry},
          ),
        );
        final racingMedia = _AfterOrphanScanMedia(
          root: Directory('${root.path}/media'),
          afterScan: () => records
              .write(
                ArticleRecord(
                  id: 'new-owner',
                  feedUrl: _item('b').feedUrl,
                  owners: {'bookmark'},
                  generation: 1,
                  media: {image: entry},
                ),
              )
              .then((result) => expect(result, StoreWriteResult.applied)),
        );
        await ArticleCleanupService(
          records: records,
          media: racingMedia,
        ).sweep();
        expect(
          (await records.read(
            ArticleRef(_item('b').feedUrl, 'new-owner'),
          ))!.owners,
          {'bookmark'},
        );
        expect(
          await file.exists(),
          isTrue,
          reason:
              'A new reference must invalidate a stale orphan deletion verdict',
        );
      },
    );

    test(
      'H archive epochs from multiple previous resets never regain authorization',
      () async {
        final oldEpochs = <int>[];
        for (var i = 0; i < 4; i++) {
          oldEpochs.add(await records.currentEpoch());
          expect(await records.wipeAll(), isTrue);
        }
        final epoch = await _fileStore(path).currentEpoch();
        expect(oldEpochs.every((old) => old < epoch), isTrue);
        for (final old in oldEpochs) {
          expect(
            await records.mutate(
              ArticleRef.of(_item('a')),
              (_) => ArticleRecord(
                id: 'shared-guid',
                feedUrl: _item('a').feedUrl,
                owners: {'bookmark'},
              ),
              expectedEpoch: old,
            ),
            StoreWriteResult.rejected,
          );
        }
        expect(await records.listRecords(), isEmpty);
      },
    );

    test(
      'J stale download cannot overwrite new-generation bytes at the same media URL',
      () async {
        const image = 'https://images.test/reused-url.png';
        final requested = Completer<void>();
        final release = Completer<http.Response>();
        final old = ArticlePreparationService(
          recordStore: records,
          mediaStore: media,
          minHostGap: Duration.zero,
          client: MockClient((_) {
            requested.complete();
            return release.future;
          }),
        );
        final current = ArticlePreparationService(
          recordStore: _fileStore(path),
          mediaStore: media,
          minHostGap: Duration.zero,
          client: MockClient(
            (_) async => http.Response.bytes(
              [7, 8, 9],
              200,
              headers: {'content-type': 'image/png'},
            ),
          ),
        );
        addTearDown(old.dispose);
        addTearDown(current.dispose);
        await old.registerArticle(_item('a').copyWith(imageUrl: image), {
          'bookmark',
        }, fullText: false);
        final pending = old.prepareArticle(ArticleRef.of(_item('a')));
        await requested.future;
        old.resetFence();
        expect(await records.wipeAll(), isTrue);
        await media.deleteAllManaged();
        await current.registerArticle(_item('b').copyWith(imageUrl: image), {
          'bookmark',
        }, fullText: false);
        await current.prepareArticle(ArticleRef.of(_item('b')));
        release.complete(
          http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        await pending;
        final record = (await records.read(ArticleRef.of(_item('b'))))!;
        expect(record.feedUrl, _item('b').feedUrl);
        expect(record.media[image]!.state, MediaState.ready);
        // Equal byte lengths make verify() alone insufficient to catch this.
        expect(
          await media.read(record.media[image]!),
          orderedEquals([7, 8, 9]),
        );
      },
    );
  });

  group('adversarial reset regressions', () {
    test(
      'write already inside critical section finishes before locked reset wins',
      () async {
        final paused = _BeforeWrite(
          FileObservedArticlePersistence(stateFile: File(path)),
        );
        final writer = ArticleRecordStore(paused);
        final pending = writer.write(
          ArticleRecord(
            id: 'shared-guid',
            feedUrl: _item('a').feedUrl,
            owners: {'bookmark'},
            generation: 1,
          ),
        );
        await paused.writing.future;
        final wiping = records.wipeAll();
        paused.release.complete();
        expect(await pending, StoreWriteResult.applied);
        expect(await wiping, isTrue);
        expect(await records.listRecords(), isEmpty);
      },
    );
    for (final mutation in [false, true]) {
      test(
        '${mutation ? 'owner mutation' : 'registration'} already awaiting lock cannot survive resetFence',
        () async {
          final paused = _BeforeLock(
            FileObservedArticlePersistence(stateFile: File(path)),
          );
          final service = prep(store: ArticleRecordStore(paused));
          if (mutation) {
            await records.write(
              ArticleRecord(
                id: 'shared-guid',
                feedUrl: _item('a').feedUrl,
                owners: {'tempCache'},
                generation: 1,
              ),
            );
          }
          final pending = mutation
              ? service.mutateRecord(
                  ArticleRef.of(_item('a')),
                  (_) => ArticleRecord(
                    id: 'shared-guid',
                    feedUrl: _item('a').feedUrl,
                    owners: {'bookmark'},
                  ),
                )
              : service.registerArticle(_item('a'), {
                  'bookmark',
                }, fullText: false);
          await paused.waiting.future;
          service.resetFence();
          expect(await records.wipeAll(), isTrue);
          paused.release.complete();
          // A fenced no-op must never report success to claim listeners.
          expect(await pending, StoreWriteResult.rejected);
          expect(await records.listRecords(), isEmpty);
          service.dispose();
        },
      );
    }

    for (final reset in [false, true]) {
      test(
        'body extraction finishing after ${reset ? 'wipe' : 'tombstone/revive'} cannot overwrite new lifetime',
        () async {
          final requested = Completer<void>();
          final release = Completer<String?>();
          final service = prep(
            extract: (_) {
              requested.complete();
              return release.future;
            },
          );
          final ref = ArticleRef.of(_item('a'));
          await service.registerArticle(_item('a'), {'bookmark'});
          final pending = service.prepareArticle(ref);
          await requested.future;
          if (reset) {
            expect(await records.wipeAll(), isTrue);
          } else {
            await records.tombstone(ref);
          }
          // The same instance's new lifetime, with different content.
          await service.registerArticle(
            _item('b').copyWith(feedUrl: _item('a').feedUrl),
            {'bookmark'},
          );
          release.complete('<p>STALE BODY</p>');
          await pending;
          expect((await records.read(ref))!.body, _item('b').content);
          service.dispose();
        },
      );
    }

    test(
      'media finishing after tombstone/revive cannot mark the new manifest ready',
      () async {
        final requested = Completer<void>();
        final release = Completer<http.Response>();
        const image = 'https://images.test/shared.png';
        final service = ArticlePreparationService(
          recordStore: records,
          mediaStore: media,
          minHostGap: Duration.zero,
          client: MockClient((_) {
            requested.complete();
            return release.future;
          }),
        );
        await service.registerArticle(_item('a').copyWith(imageUrl: image), {
          'bookmark',
        }, fullText: false);
        final ref = ArticleRef.of(_item('a'));
        final pending = service.prepareArticle(ref);
        await requested.future;
        await records.tombstone(ref);
        // The same instance revived with new content.
        await service.registerArticle(
          _item('b').copyWith(feedUrl: _item('a').feedUrl, imageUrl: image),
          {'bookmark'},
          fullText: false,
        );
        release.complete(
          http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        await pending;
        expect(
          (await records.read(ref))!.media[image]!.state,
          MediaState.pending,
        );
        service.dispose();
      },
    );

    for (final sweep in [false, true]) {
      test(
        'reset between ${sweep ? 'sweep' : 'article'} snapshot and epoch read cannot contaminate new record',
        () async {
          final old = _item('a');
          final fresh = _item('b');
          final hooked = _SnapshotHookStore(
            FileObservedArticlePersistence(stateFile: File(path)),
          );
          final service = prep(
            store: hooked,
            extract: (url) async => '<p>STALE $url</p>',
          );
          await service.registerArticle(old, {'bookmark'});
          hooked.afterSnapshot = () async {
            expect(await records.wipeAll(), isTrue);
            await records.write(
              ArticleRecord(
                // The same instance's new-era record, with new content.
                id: fresh.id,
                feedUrl: old.feedUrl,
                link: fresh.link,
                body: fresh.content,
                owners: {'bookmark'},
                generation: 1,
              ),
            );
          };
          if (sweep) {
            await service.preparePending(unmetered: true);
          } else {
            await service.prepareArticle(ArticleRef.of(old));
          }
          expect((await records.read(ArticleRef.of(old)))!.body, fresh.content);
          service.dispose();
        },
      );
    }
  });
}
