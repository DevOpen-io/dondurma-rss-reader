import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/article_status.dart';
import 'package:ice_cream_rss_reader/services/feed_backoff.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/full_text_extraction_service.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';
import 'package:ice_cream_rss_reader/services/temp_cache_membership.dart';
import 'package:ice_cream_rss_reader/utils/host_pacer.dart';

FeedItem _article() => FeedItem(
  id: 'upgrade-article',
  siteName: 'Example',
  title: 'Previously saved article',
  description: 'Legacy summary',
  content: '<p>Legacy body</p>',
  timeAgo: '1h',
  siteIcon: Icons.rss_feed,
  iconColor: Colors.blue,
  iconBackgroundColor: Colors.blueGrey,
  link: 'https://example.test/article',
  feedUrl: 'https://example.test/feed',
  isBookmarked: true,
);

class _DelayedEpochPreparation extends ArticlePreparationService {
  _DelayedEpochPreparation({required super.recordStore});

  final resume = Completer<void>();

  @override
  Future<int> currentRecordEpoch() async {
    await resume.future;
    return super.currentRecordEpoch();
  }
}

// Real isolates exercise the filesystem protocol, not just a shared Dart queue.
Future<void> _incrementWorker((String, SendPort) message) async {
  final (path, reply) = message;
  final persistence = FileObservedArticlePersistence(
    stateFile: File(path),
    lockTimeout: const Duration(seconds: 5),
    retryDelay: const Duration(milliseconds: 1),
  );
  try {
    for (var i = 0; i < 20; i++) {
      final result = await persistence.runExclusive(() async {
        final value = int.parse(await persistence.read() ?? '0');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await persistence.write('${value + 1}');
      });
      if (!result.acquired) throw StateError('Lock timed out');
    }
    reply.send('ok');
  } catch (error) {
    reply.send('$error');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ArticleRecordStore records;
  late ArticleMediaStore media;
  late ArticlePreparationService preparation;
  late HostPacer pacer;
  late FeedBackoff backoff;
  late MockClient client;
  late Future<http.Response> Function(http.Request) respond;
  late HostPacer previousPacer;
  late FeedBackoff? previousBackoff;
  final requests = <String>[];
  const imageUrl = 'https://example.test/image.png';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('release-regression-');
    Hive.init('${root.path}/hive');
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    previousPacer = FullTextExtractionService.instance.pacer;
    previousBackoff = FullTextExtractionService.instance.backoff;
    records = ArticleRecordStore.forBox(Hive.box('feeds'));
    media = ArticleMediaStore(root: Directory('${root.path}/offline_media'));
    pacer = HostPacer(minGap: const Duration(milliseconds: 1));
    backoff = FeedBackoff();
    requests.clear();
    respond = (_) async => http.Response.bytes(
      [1, 2, 3],
      200,
      headers: {'content-type': 'image/png'},
    );
    client = MockClient((request) async {
      requests.add(request.url.toString());
      return respond(request);
    });
    preparation = ArticlePreparationService(
      recordStore: records,
      mediaStore: media,
      client: client,
      hostPacer: pacer,
      backoff: backoff,
      minHostGap: const Duration(milliseconds: 1),
      extractFullText: (_) async => '<p>Extracted body</p>',
    );
  });

  tearDown(() async {
    preparation.dispose();
    client.close();
    FullTextExtractionService.instance.pacer = previousPacer;
    FullTextExtractionService.instance.backoff = previousBackoff;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await Hive.close();
    // Only this test's uniquely created temporary directory is removed.
    await root.delete(recursive: true);
  });

  Future<void> seedBookmark() async {
    await Hive.box(
      'bookmarks',
    ).put('bookmarkedItemsJson', jsonEncode([_article().toJson()]));
  }

  FeedProvider feedProvider() {
    final feed = FeedProvider(
      preparation: preparation,
      hostPacer: pacer,
      backoff: backoff,
    );
    addTearDown(feed.dispose);
    return feed;
  }

  Future<void> seedMedia(String id, {bool ready = false}) async {
    expect(
      await records.write(
        ArticleRecord(
          id: id,
          feedUrl: _article().feedUrl,
          link: _article().link,
          body: '<p>Saved body</p><img src="$imageUrl">',
          bodyState: MediaState.ready,
          bodySource: 'extracted',
          media: {
            imageUrl: MediaEntry(
              file: ArticleMediaStore.fileNameFor(imageUrl),
              byteSize: ready ? 3 : 0,
              state: ready ? MediaState.ready : MediaState.pending,
            ),
          },
          owners: const {'bookmark'},
          generation: 1,
        ),
      ),
      StoreWriteResult.applied,
    );
  }

  test('legacy bookmark restores locally and survives cache cleanup', () async {
    await seedBookmark();
    final bookmarks = BookmarkProvider(
      preparation: preparation,
      fullTextFor: (_) => false,
    );
    addTearDown(bookmarks.dispose);
    await bookmarks.restoration;
    expect(requests, isEmpty, reason: 'Migration is not a metered permit');
    await TempCacheMembership(
      records: records,
      preparation: preparation,
    ).reconcile(
      items: [_article()],
      bookmarkedIds: bookmarks.bookmarkedItemIds,
      subscribedFeedUrls: [_article().feedUrl],
      globalKeywords: const [],
      feedKeywordsMap: const {},
      limit: 0,
      fullTextFor: (_) => false,
    );
    await preparation.sweepCleanup(isBookmarked: bookmarks.isBookmarked);
    final restored = await records.read(_article().id);
    expect(restored, isNotNull);
    expect(restored!.owners, {'bookmark'});
    expect(restored.body, '<p>Legacy body</p>');
    final page = ArticlePageProvider(item: _article());
    addTearDown(page.dispose);
    await page.loadSavedCopy(records: records, media: media);
    expect(page.recordStatus!.scope, ArticleScope.savedReady);
    expect(page.rawContent, '<p>Legacy body</p>');
  });

  test(
    'restoration preserves an existing extracted body and ready image',
    () async {
      await seedBookmark();
      await seedMedia(_article().id, ready: true);
      final savedImage = await media.put(imageUrl, [1, 2, 3]);
      final bookmarks = BookmarkProvider(
        preparation: preparation,
        fullTextFor: (_) => true,
      );
      await bookmarks.restoration;
      bookmarks.dispose();
      final restarted = BookmarkProvider(
        preparation: preparation,
        fullTextFor: (_) => true,
      );
      addTearDown(restarted.dispose);
      await restarted.restoration;
      final record = (await records.read(_article().id))!;
      expect(record.body, contains('Saved body'));
      expect(record.bodySource, 'extracted');
      expect(record.media[imageUrl]!.state, MediaState.ready);
      expect(await media.verify(savedImage), isTrue);
      expect(requests, isEmpty);
    },
  );

  test('reset during restoration cannot resurrect an old bookmark', () async {
    await seedBookmark();
    final delayed = _DelayedEpochPreparation(recordStore: records);
    addTearDown(delayed.dispose);
    final bookmarks = BookmarkProvider(preparation: delayed);
    addTearDown(bookmarks.dispose);
    await bookmarks.factoryReset();
    delayed.resume.complete();
    await bookmarks.restoration;
    expect(bookmarks.bookmarkedItems, isEmpty);
    expect(await records.read(_article().id), isNull);
    expect(requests, isEmpty);
  });

  test(
    'real prepareArticleNow repairs missing-ready media on first tap',
    () async {
      await seedMedia(_article().id, ready: true);
      final page = ArticlePageProvider(item: _article());
      addTearDown(page.dispose);
      await page.loadSavedCopy(records: records, media: media);
      expect(page.recordStatus!.hasActionable, isTrue);
      expect(page.recordStatus!.readyMedia, 0);
      final feed = feedProvider();
      await feed.prepareArticleNow(_article().id);
      await page.refreshSavedCopy(records: records, media: media);
      expect(requests, [imageUrl]);
      expect(page.recordStatus!.scope, ArticleScope.savedReady);
      expect(page.recordStatus!.readyMedia, 1);
      expect(
        await media.verify(
          (await records.read(_article().id))!.media[imageUrl]!,
        ),
        isTrue,
      );
    },
  );

  test('feed Retry-After also blocks explicitly requested media', () async {
    await seedMedia(_article().id);
    final feed = feedProvider();
    expect(FullTextExtractionService.instance.pacer, same(pacer));
    expect(FullTextExtractionService.instance.backoff, same(backoff));
    backoff.recordFailure(
      _article().feedUrl,
      FeedFetchException(
        FeedFetchErrorKind.httpStatus,
        'Rate limited',
        statusCode: 429,
        retryAfter: DateTime.now().add(const Duration(minutes: 5)),
      ),
      DateTime.now(),
    );
    await feed.prepareArticleNow(_article().id);
    expect(requests, isEmpty);
    final entry = (await records.read(_article().id))!.media[imageUrl]!;
    expect(entry.state, MediaState.pending);
    expect(entry.attempts, 0);
  });

  test('media 429 cools the shared host and holds a sibling article', () async {
    await seedMedia('first');
    await seedMedia('second');
    final feed = feedProvider();
    respond = (_) async =>
        http.Response('', 429, headers: {'retry-after': '300'});
    await feed.prepareArticleNow('first');
    expect(
      backoff.isMandatedBackedOff(_article().feedUrl, DateTime.now()),
      isTrue,
    );
    await feed.prepareArticleNow('second');
    expect(requests, [imageUrl]);
    expect((await records.read('second'))!.media[imageUrl]!.attempts, 0);
  });

  test('stale-lock recovery keeps 400 contending actions exclusive', () async {
    for (var trial = 0; trial < 100; trial++) {
      final stateFile = File('${root.path}/race-$trial.json');
      await File(
        '${stateFile.path}.lock',
      ).writeAsString('orphan\n2000-01-01T00:00:00Z');
      if (trial % 3 != 0) {
        final guard = Directory('${stateFile.path}.lock.guard');
        await guard.create();
        if (trial % 3 == 1) {
          await File(
            '${guard.path}/owner-1-1-1',
          ).writeAsString('2000-01-01T00:00:00Z');
        }
      }
      var holders = 0;
      final results = await Future.wait(
        List.generate(4, (_) {
          return FileObservedArticlePersistence(
            stateFile: stateFile,
            retryDelay: const Duration(milliseconds: 1),
          ).runExclusive(() async {
            holders++;
            expect(holders, 1, reason: 'Overlapping owners on trial $trial');
            await Future<void>.delayed(const Duration(milliseconds: 1));
            holders--;
          });
        }),
      );
      expect(results.every((result) => result.acquired), isTrue);
    }
  });

  test(
    'four real isolates preserve all 80 read-modify-write increments',
    () async {
      final stateFile = File('${root.path}/isolate-counter');
      await File(
        '${stateFile.path}.lock',
      ).writeAsString('orphan\n2000-01-01T00:00:00Z');
      final replies = ReceivePort();
      final workers = <Isolate>[];
      try {
        for (var i = 0; i < 4; i++) {
          workers.add(
            await Isolate.spawn(_incrementWorker, (
              stateFile.path,
              replies.sendPort,
            )),
          );
        }
        final results = await replies
            .take(4)
            .toList()
            .timeout(const Duration(seconds: 15));
        expect(results, everyElement('ok'));
        expect(await stateFile.readAsString(), '80');
      } finally {
        replies.close();
        for (final worker in workers) {
          worker.kill(priority: Isolate.immediate);
        }
      }
    },
  );

  for (final empty in [false, true]) {
    test(
      'abandoned ${empty ? 'empty' : 'populated'} guard is recoverable',
      () async {
        final stateFile = File('${root.path}/abandoned.json');
        final guard = Directory('${stateFile.path}.lock.guard');
        await guard.create();
        if (!empty) {
          await File(
            '${guard.path}/owner-1-1-1',
          ).writeAsString('2000-01-01T00:00:00Z');
        }
        final result = await FileObservedArticlePersistence(
          stateFile: stateFile,
        ).runExclusive(() async => 'recovered');
        expect(result.acquired, isTrue);
        expect(result.value, 'recovered');
        expect(await guard.exists(), isFalse);
      },
    );
  }

  test(
    'fresh guard times out without deleting the active owner marker',
    () async {
      final stateFile = File('${root.path}/active.json');
      final guard = Directory('${stateFile.path}.lock.guard');
      await guard.create();
      final marker = File('${guard.path}/owner-1-1-1');
      final stamp = DateTime.now().toUtc().toIso8601String();
      await marker.writeAsString(stamp);
      var entered = false;
      final result =
          await FileObservedArticlePersistence(
            stateFile: stateFile,
            lockTimeout: const Duration(milliseconds: 30),
            retryDelay: const Duration(milliseconds: 1),
          ).runExclusive(() async {
            entered = true;
          });
      expect(result.acquired, isFalse);
      expect(entered, isFalse);
      expect(await marker.readAsString(), stamp);
    },
  );
}
