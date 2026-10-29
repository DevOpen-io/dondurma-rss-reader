import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/article_status.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

void main() {
  late Directory tempDir;
  late File stateFile;
  late Directory mediaDir;
  var stamp = 0;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('s6_status_test_');
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

  ArticleRef ref(String id) => ArticleRef('https://e.com/feed', id);

  ArticleRecordStore newStore() =>
      ArticleRecordStore(FileObservedArticlePersistence(stateFile: stateFile));

  MediaEntry mediaEntry(
    String url, {
    MediaState state = MediaState.pending,
    DateTime? nextRetryAt,
    String? waitSource,
  }) => MediaEntry(
    file: ArticleMediaStore.fileNameFor(url),
    byteSize: 0,
    state: state,
    nextRetryAt: nextRetryAt,
    waitSource: waitSource,
  );

  ArticleRecord rec(
    String id, {
    Set<String> owners = const {'bookmark'},
    String? body,
    MediaState bodyState = MediaState.ready,
    String? bodySource = 'extracted',
    String link = 'https://e.com/a',
    Map<String, MediaEntry> media = const {},
    DateTime? nextRetryAt,
    bool tombstoned = false,
  }) => ArticleRecord(
    id: id,
    feedUrl: 'https://e.com/feed',
    link: link,
    body: body,
    bodyState: bodyState,
    bodySource: bodySource,
    media: media,
    owners: owners,
    nextRetryAt: nextRetryAt,
    tombstoned: tombstoned,
    generation: 1,
  );

  group('ArticleStatus scope', () {
    test('bookmark + body + all media ready -> savedReady', () {
      final s = ArticleStatus.fromRecord(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            'u1': mediaEntry('u1', state: MediaState.ready),
            'u2': mediaEntry('u2', state: MediaState.ready),
          },
        ),
      );
      expect(s.scope, ArticleScope.savedReady);
      expect(s.fullyReady, isTrue);
      expect(s.readyMedia, 2);
      expect(s.totalMedia, 2);
    });

    test('bookmark + body + pending media -> savedText', () {
      final s = ArticleStatus.fromRecord(
        rec('a', body: '<p>x</p>', media: {'u1': mediaEntry('u1')}),
      );
      expect(s.scope, ArticleScope.savedText);
      expect(s.fullyReady, isFalse);
      expect(s.hasReadableBody, isTrue);
    });

    test('bookmark + no body -> saveRequested, not ready', () {
      final s = ArticleStatus.fromRecord(
        rec('a', body: null, bodyState: MediaState.pending),
      );
      expect(s.scope, ArticleScope.saveRequested);
      expect(s.hasReadableBody, isFalse);
      expect(s.fullyReady, isFalse);
    });

    test('tempCache + body + all ready -> cachedReady', () {
      final s = ArticleStatus.fromRecord(
        rec('a', owners: {'tempCache'}, body: '<p>x</p>'),
      );
      expect(s.scope, ArticleScope.cachedReady);
      expect(s.fullyReady, isTrue);
    });

    test('tempCache + body + incomplete media -> cachedText', () {
      final s = ArticleStatus.fromRecord(
        rec(
          'a',
          owners: {'tempCache'},
          body: '<p>x</p>',
          media: {'u': mediaEntry('u', state: MediaState.failed)},
        ),
      );
      expect(s.scope, ArticleScope.cachedText);
    });

    test('tempCache without body -> no label', () {
      final s = ArticleStatus.fromRecord(
        rec(
          'a',
          owners: {'tempCache'},
          body: null,
          bodyState: MediaState.pending,
        ),
      );
      expect(s.scope, ArticleScope.none);
    });

    test('ownerless record -> no label', () {
      final s = ArticleStatus.fromRecord(
        rec('a', owners: {}, body: '<p>x</p>'),
      );
      expect(s.scope, ArticleScope.none);
    });

    test('tombstoned record -> no label even with body', () {
      final s = ArticleStatus.fromRecord(
        rec('a', body: '<p>x</p>', tombstoned: true),
      );
      expect(s.scope, ArticleScope.none);
      expect(s.hasReadableBody, isFalse);
    });

    test('failed extraction with retained RSS body stays readable', () {
      final s = ArticleStatus.fromRecord(
        rec('a', body: '<p>rss</p>', bodyState: MediaState.failed),
      );
      expect(s.hasReadableBody, isTrue);
      expect(s.scope, ArticleScope.savedText);
      expect(s.fullyReady, isFalse);
    });

    test('empty link means body work is final -> fullyReady possible', () {
      final s = ArticleStatus.fromRecord(
        rec('a', body: '<p>x</p>', bodyState: MediaState.pending, link: ''),
      );
      expect(s.bodyDue, isFalse);
      expect(s.fullyReady, isTrue);
    });

    test('bodySource passes through for RSS-vs-extracted labels', () {
      final rss = ArticleStatus.fromRecord(
        rec('a', body: '<p>x</p>', bodySource: 'rss'),
      );
      expect(rss.bodySource, 'rss');
    });

    test('gone media counts against readiness', () {
      final s = ArticleStatus.fromRecord(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            'u1': mediaEntry('u1', state: MediaState.ready),
            'u2': mediaEntry('u2', state: MediaState.gone),
          },
        ),
      );
      expect(s.fullyReady, isFalse);
      expect(s.goneMedia, 1);
    });
  });

  group('ArticleStatus wait reason', () {
    final now = DateTime.utc(2025, 1, 1, 12);

    ArticleWait wait(ArticleRecord r, {bool unmetered = true, DateTime? at}) =>
        ArticleStatus.fromRecord(
          r,
        ).waitFor(unmeteredNow: unmetered, now: at ?? now);

    test('gone media or body -> unavailable', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {'u': mediaEntry('u', state: MediaState.gone)},
      );
      expect(wait(s), ArticleWait.unavailable);
    });

    test('server waitSource + future nextRetryAt -> serverWait', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {
          'u': mediaEntry(
            'u',
            state: MediaState.failed,
            nextRetryAt: now.add(const Duration(minutes: 5)),
            waitSource: 'server',
          ),
        },
      );
      expect(wait(s), ArticleWait.serverWait);
    });

    test('backoff waitSource + future nextRetryAt -> retry', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {
          'u': mediaEntry(
            'u',
            state: MediaState.failed,
            nextRetryAt: now.add(const Duration(minutes: 5)),
            waitSource: 'backoff',
          ),
        },
      );
      expect(wait(s), ArticleWait.retry);
    });

    test('body-level nextRetryAt is always a local retry wait', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        bodyState: MediaState.failed,
        nextRetryAt: now.add(const Duration(minutes: 2)),
      );
      expect(wait(s), ArticleWait.retry);
    });

    test('past nextRetryAt is not a wait', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {
          'u': mediaEntry(
            'u',
            state: MediaState.failed,
            nextRetryAt: now.subtract(const Duration(minutes: 5)),
            waitSource: 'server',
          ),
        },
      );
      expect(wait(s), ArticleWait.preparing);
    });

    test('due work + unmetered -> preparing; metered -> unmetered', () {
      final s = rec('a', body: '<p>x</p>', media: {'u': mediaEntry('u')});
      expect(wait(s, unmetered: true), ArticleWait.preparing);
      expect(wait(s, unmetered: false), ArticleWait.unmetered);
    });

    test('nothing due -> none', () {
      final s = rec('a', body: '<p>x</p>');
      expect(wait(s), ArticleWait.none);
    });

    test('unavailable beats retry and preparing', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {
          'gone': mediaEntry('gone', state: MediaState.gone),
          'wait': mediaEntry(
            'wait',
            state: MediaState.failed,
            nextRetryAt: now.add(const Duration(hours: 1)),
            waitSource: 'server',
          ),
          'pend': mediaEntry('pend'),
        },
      );
      expect(wait(s), ArticleWait.unavailable);
    });

    test('serverWait beats backoff retry', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {
          'a1': mediaEntry(
            'a1',
            state: MediaState.failed,
            nextRetryAt: now.add(const Duration(minutes: 5)),
            waitSource: 'backoff',
          ),
          'a2': mediaEntry(
            'a2',
            state: MediaState.failed,
            nextRetryAt: now.add(const Duration(hours: 2)),
            waitSource: 'server',
          ),
        },
      );
      expect(wait(s), ArticleWait.serverWait);
    });

    test(
      'legacy waitSource null + future wait -> retry label, not actionable',
      () {
        final s = rec(
          'a',
          body: '<p>x</p>',
          media: {
            'u': mediaEntry(
              'u',
              state: MediaState.failed,
              nextRetryAt: now.add(const Duration(minutes: 5)),
              // Unknown provenance — pre-S6 records carry no waitSource.
            ),
          },
        );
        final status = ArticleStatus.fromRecord(s);
        expect(wait(s), ArticleWait.retry);
        // No dead retry button: a manual pass cannot reach this piece.
        expect(status.hasActionable, isFalse);
      },
    );

    test('earliestServerRetryAt only tracks server-stamped waits', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {
          'local': mediaEntry(
            'local',
            state: MediaState.failed,
            nextRetryAt: now.add(const Duration(minutes: 1)),
            waitSource: 'backoff',
          ),
          'remote': mediaEntry(
            'remote',
            state: MediaState.failed,
            nextRetryAt: now.add(const Duration(hours: 3)),
            waitSource: 'server',
          ),
        },
      );
      final status = ArticleStatus.fromRecord(s);
      expect(status.earliestServerRetryAt, now.add(const Duration(hours: 3)));
      // The overall earliest stays the earlier local wait.
      expect(status.earliestRetryAt, now.add(const Duration(minutes: 1)));
    });

    test('gone entries never pollute the earliest-wait fields', () {
      final s = rec(
        'a',
        body: '<p>x</p>',
        media: {
          'u': mediaEntry(
            'u',
            state: MediaState.gone,
            nextRetryAt: now.add(const Duration(minutes: 5)),
            waitSource: 'server',
          ),
        },
      );
      final status = ArticleStatus.fromRecord(s);
      expect(status.earliestRetryAt, isNull);
      expect(status.earliestServerRetryAt, isNull);
    });
  });

  group('listStatusSummaries', () {
    test('returns summaries keyed by id; skips tombstones', () async {
      final store = newStore();
      await store.write(rec('live', body: '<p>x</p>'));
      await store.write(rec('dead', body: '<p>x</p>', tombstoned: true));
      await store.tombstone(ref('dead'));
      final map = await listArticleStatuses(store);
      expect(map.keys, contains(ref('live')));
      expect(map.keys, isNot(contains(ref('dead'))));
      expect(map[ref('live')]!.scope, ArticleScope.savedReady);
    });

    test('corrupt state fails closed to empty map', () async {
      stateFile.writeAsStringSync('{not json');
      final map = await listArticleStatuses(newStore());
      expect(map, isEmpty);
    });

    test('a ready entry whose file is missing is demoted for repair', () async {
      final store = newStore();
      const url = 'https://e.com/i.png';
      await store.write(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            url: MediaEntry(
              file: ArticleMediaStore.fileNameFor(url),
              byteSize: 10,
              state: MediaState.ready,
            ),
          },
        ),
      );
      // No file on disk — the "ready" claim is unbacked.
      final map = await listArticleStatuses(
        store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(map[ref('a')]!.fullyReady, isFalse);
      expect(map[ref('a')]!.scope, ArticleScope.savedText);
      // The manifest was repaired — the engine can retry the piece.
      final r = await store.read(ref('a'));
      expect(r!.media[url]!.state, MediaState.pending);
      expect(r.media[url]!.nextRetryAt, isNull);
    });

    test('a verified ready file still backs the ready label', () async {
      final store = newStore();
      const url = 'https://e.com/i.png';
      final name = ArticleMediaStore.fileNameFor(url);
      File('${mediaDir.path}/$name').writeAsBytesSync([1, 2, 3]);
      await store.write(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            url: MediaEntry(file: name, byteSize: 3, state: MediaState.ready),
          },
        ),
      );
      final map = await listArticleStatuses(
        store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(map[ref('a')]!.fullyReady, isTrue);
      expect(map[ref('a')]!.scope, ArticleScope.savedReady);
    });
  });

  group('manual retry gate', () {
    ArticlePreparationService newPrep(http_testing.MockClient client) =>
        ArticlePreparationService(
          recordStore: newStore(),
          mediaStore: ArticleMediaStore(root: mediaDir),
          client: client,
          extractFullText: (_) async => '<p>full</p>',
        );

    test('manual retry bypasses local backoff wait on media', () async {
      var fetched = 0;
      final client = http_testing.MockClient((req) async {
        fetched++;
        return http.Response.bytes([1, 2, 3], 200);
      });
      final store = newStore();
      final prep = newPrep(client);
      await store.write(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            'https://e.com/i.png': mediaEntry(
              'https://e.com/i.png',
              state: MediaState.failed,
              nextRetryAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
              waitSource: 'backoff',
            ),
          },
        ),
      );
      await prep.prepareArticle(ref('a'));
      expect(fetched, 1);
      final r = await store.read(ref('a'));
      expect(r!.media['https://e.com/i.png']!.state, MediaState.ready);
    });

    test('manual retry never bypasses a server Retry-After wait', () async {
      var fetched = 0;
      final client = http_testing.MockClient((req) async {
        fetched++;
        return http.Response.bytes([1, 2, 3], 200);
      });
      final store = newStore();
      final prep = newPrep(client);
      await store.write(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            'https://e.com/i.png': mediaEntry(
              'https://e.com/i.png',
              state: MediaState.failed,
              nextRetryAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
              waitSource: 'server',
            ),
          },
        ),
      );
      await prep.prepareArticle(ref('a'));
      expect(fetched, 0);
    });

    test('manual retry bypasses body-level backoff', () async {
      var extracted = 0;
      final client = http_testing.MockClient((req) async {
        return http.Response.bytes([1], 200);
      });
      final store = newStore();
      final prep = ArticlePreparationService(
        recordStore: store,
        mediaStore: ArticleMediaStore(root: mediaDir),
        client: client,
        extractFullText: (_) async {
          extracted++;
          // Longer than the RSS body, so it counts as full text.
          return '<p>full</p><p>${'Story paragraph. ' * 20}</p>';
        },
      );
      await store.write(
        rec(
          'a',
          body: '<p>x</p>',
          bodyState: MediaState.failed,
          nextRetryAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      await prep.prepareArticle(ref('a'));
      expect(extracted, 1);
      final r = await store.read(ref('a'));
      expect(r!.bodyState, MediaState.ready);
      expect(r.bodySource, 'extracted');
    });

    test('automatic sweep still honors backoff waits', () async {
      var fetched = 0;
      final client = http_testing.MockClient((req) async {
        fetched++;
        return http.Response.bytes([1, 2, 3], 200);
      });
      final store = newStore();
      final prep = newPrep(client);
      await store.write(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            'https://e.com/i.png': mediaEntry(
              'https://e.com/i.png',
              state: MediaState.failed,
              nextRetryAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
              waitSource: 'backoff',
            ),
          },
        ),
      );
      await prep.preparePending(unmetered: true);
      expect(fetched, 0);
    });

    test('settling onto the RSS body clears the stale retry stamp', () async {
      final store = newStore();
      final prep = newPrep(
        http_testing.MockClient((req) async => http.Response.bytes([1], 200)),
      );
      await store.write(
        rec(
          'a',
          body: '<p>rss</p>',
          bodyState: MediaState.failed,
          nextRetryAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      // The feed's full-text preference switched off → the failed
      // extraction intent settles on the RSS body.
      await prep.registerArticle(
        FeedItem(
          id: 'a',
          siteName: 'Site',
          title: 'Title',
          description: 'd',
          link: 'https://e.com/a',
          category: 'Tech',
          feedUrl: 'https://e.com/feed',
          content: '<p>rss</p>',
        ),
        const {'bookmark'},
        fullText: false,
      );
      final r = await store.read(ref('a'));
      expect(r!.bodyState, MediaState.ready);
      expect(
        r.nextRetryAt,
        isNull,
        reason: 'a settled body must not keep a phantom retry wait',
      );
    });

    test(
      'a 200 with an empty payload is structurally gone, not retryable',
      () async {
        var fetched = 0;
        final client = http_testing.MockClient((req) async {
          fetched++;
          return http.Response.bytes(const [], 200);
        });
        final store = newStore();
        final prep = newPrep(client);
        await store.write(
          rec(
            'a',
            body: '<p>x</p>',
            media: {
              'https://e.com/empty.png': mediaEntry('https://e.com/empty.png'),
            },
          ),
        );
        await prep.prepareArticle(ref('a'));
        final r = await store.read(ref('a'));
        expect(
          r!.media['https://e.com/empty.png']!.state,
          MediaState.gone,
          reason: 'an empty 200 cannot ever become bytes on disk',
        );
        // No backoff loop — one fetch was enough to learn it is gone.
        expect(fetched, 1);
      },
    );
  });

  group('article page saved copy', () {
    FeedItem pageItem({
      String id = 'a',
      String? content,
      bool isBookmarked = false,
    }) => FeedItem(
      id: id,
      siteName: 'Site',
      title: 'Title',
      description: 'desc',
      link: 'https://e.com/a',
      category: 'Tech',
      feedUrl: 'https://e.com/feed',
      content: content,
      isBookmarked: isBookmarked,
    );

    test('bookmark renders its saved body, not the feed body', () async {
      final store = newStore();
      await store.write(
        rec('a', body: '<p>saved copy</p>', owners: {'bookmark'}),
      );
      final p = ArticlePageProvider(
        item: pageItem(content: '<p>feed version</p>', isBookmarked: true),
      );
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(p.rawContent, '<p>saved copy</p>');
      expect(p.recordStatus!.scope, ArticleScope.savedReady);
      expect(p.usingArchivedCopy, isFalse);
      p.dispose();
    });

    test(
      'feed item keeps its current body — no unneeded archive swap',
      () async {
        final store = newStore();
        await store.write(
          rec('a', body: '<p>saved copy</p>', owners: {'tempCache'}),
        );
        final p = ArticlePageProvider(
          item: pageItem(content: '<p>feed version</p>'),
        );
        await p.loadSavedCopy(
          records: store,
          media: ArticleMediaStore(root: mediaDir),
        );
        expect(p.rawContent, '<p>feed version</p>');
        expect(p.usingArchivedCopy, isFalse);
        p.dispose();
      },
    );

    test(
      'missing current body falls back to the saved copy + notice',
      () async {
        final store = newStore();
        await store.write(
          rec('a', body: '<p>saved copy</p>', owners: {'tempCache'}),
        );
        final p = ArticlePageProvider(item: pageItem(content: null));
        await p.loadSavedCopy(
          records: store,
          media: ArticleMediaStore(root: mediaDir),
        );
        expect(p.rawContent, '<p>saved copy</p>');
        expect(p.usingArchivedCopy, isTrue);
        p.dispose();
      },
    );

    /// Writes a real media-pool file so the verify() gate passes.
    String writeMediaFile(String url, List<int> bytes) {
      final name = ArticleMediaStore.fileNameFor(url);
      File('${mediaDir.path}/$name').writeAsBytesSync(bytes);
      return name;
    }

    test('ready manifest media rewrites img src to file://', () async {
      final store = newStore();
      final url = 'https://e.com/i.png';
      final fileName = writeMediaFile(url, [1, 2, 3]);
      await store.write(
        rec(
          'a',
          body: '<p>x</p><img src="$url">',
          owners: {'tempCache'},
          media: {
            url: MediaEntry(
              file: fileName,
              byteSize: 3,
              state: MediaState.ready,
            ),
          },
        ),
      );
      final p = ArticlePageProvider(item: pageItem(content: null));
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      final out = p.displayContent;
      expect(out, contains('src="file://'));
      expect(out, contains('m_'));
      expect(out, isNot(contains('src="https://e.com/i.png"')));
      p.dispose();
    });

    test('pending media keeps its remote src', () async {
      final store = newStore();
      final url = 'https://e.com/i.png';
      await store.write(
        rec(
          'a',
          body: '<p>x</p><img src="$url">',
          owners: {'tempCache'},
          media: {
            url: MediaEntry(
              file: ArticleMediaStore.fileNameFor(url),
              byteSize: 0,
              state: MediaState.pending,
            ),
          },
        ),
      );
      final p = ArticlePageProvider(item: pageItem(content: null));
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(p.displayContent, contains('src="https://e.com/i.png"'));
      p.dispose();
    });

    test('no record -> status null, feed content untouched', () async {
      final p = ArticlePageProvider(
        item: pageItem(content: '<p>feed version</p>'),
      );
      expect(p.savedCopyLoaded, isFalse);
      await p.loadSavedCopy(
        records: newStore(),
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(p.savedCopyLoaded, isTrue);
      expect(p.recordStatus, isNull);
      expect(p.rawContent, '<p>feed version</p>');
      p.dispose();
    });

    test('RSS body stays usable while extraction is still pending', () async {
      final store = newStore();
      await store.write(
        rec(
          'a',
          body: '<p>rss copy</p>',
          bodyState: MediaState.pending,
          bodySource: 'rss',
          owners: {'tempCache'},
        ),
      );
      final p = ArticlePageProvider(item: pageItem(content: null));
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(p.rawContent, '<p>rss copy</p>');
      expect(p.usingArchivedCopy, isTrue);
      p.dispose();
    });

    test('a refresh after the record vanished clears saved state', () async {
      final store = newStore();
      await store.write(
        rec('a', body: '<p>saved copy</p>', owners: {'bookmark'}),
      );
      final p = ArticlePageProvider(
        item: pageItem(content: '<p>feed version</p>', isBookmarked: true),
      );
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(p.rawContent, '<p>saved copy</p>');

      await store.tombstone(ref('a'));
      await p.refreshSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(p.savedCopyLoaded, isTrue);
      expect(p.recordStatus, isNull);
      expect(p.rawContent, '<p>feed version</p>');
      p.dispose();
    });

    test('consecutive carousel images rewrite inside data-urls', () async {
      final store = newStore();
      const u1 = 'https://e.com/one.png';
      const u2 = 'https://e.com/two.png';
      writeMediaFile(u1, [1]);
      writeMediaFile(u2, [2]);
      await store.write(
        rec(
          'a',
          body: '<p>x</p><img src="$u1"><img src="$u2">',
          owners: {'tempCache'},
          media: {
            u1: MediaEntry(
              file: ArticleMediaStore.fileNameFor(u1),
              byteSize: 1,
              state: MediaState.ready,
            ),
            u2: MediaEntry(
              file: ArticleMediaStore.fileNameFor(u2),
              byteSize: 1,
              state: MediaState.ready,
            ),
          },
        ),
      );
      final p = ArticlePageProvider(item: pageItem(content: null));
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      final out = p.displayContent;
      // Grouped into a carousel whose data-urls must carry the local
      // paths — not the dead remote URLs.
      expect(out, contains('data-urls="file://'));
      expect(out, isNot(contains('https://e.com/one.png')));
      expect(out, isNot(contains('https://e.com/two.png')));
      p.dispose();
    });

    test('a link href sharing the image URL is never rewritten', () async {
      final store = newStore();
      const url = 'https://e.com/i.png';
      writeMediaFile(url, [1, 2, 3]);
      await store.write(
        rec(
          'a',
          body: '<a href="$url"><img src="$url"></a>',
          owners: {'tempCache'},
          media: {
            url: MediaEntry(
              file: ArticleMediaStore.fileNameFor(url),
              byteSize: 3,
              state: MediaState.ready,
            ),
          },
        ),
      );
      final p = ArticlePageProvider(item: pageItem(content: null));
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      final out = p.displayContent;
      expect(out, contains('src="file://'));
      // The surrounding anchor keeps pointing at the source — it is a
      // navigation link, not an image to store.
      expect(out, contains('href="$url"'));
      p.dispose();
    });

    test('entity-encoded img src still rewrites to the local file', () async {
      final store = newStore();
      const url = 'https://e.com/i.png?a=1&b=2';
      writeMediaFile(url, [9]);
      await store.write(
        rec(
          'a',
          body: '<p>x</p><img src="$url">',
          owners: {'tempCache'},
          media: {
            url: MediaEntry(
              file: ArticleMediaStore.fileNameFor(url),
              byteSize: 1,
              state: MediaState.ready,
            ),
          },
        ),
      );
      final p = ArticlePageProvider(item: pageItem(content: null));
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      // The DOM parser hands us the decoded attribute — matching the
      // manifest key regardless of &amp; encoding in the source.
      expect(p.displayContent, contains('src="file://'));
      p.dispose();
    });

    test('a ready manifest whose file is gone does not rewrite', () async {
      final store = newStore();
      const url = 'https://e.com/i.png';
      // No file written — the manifest claims bytes the disk lacks.
      await store.write(
        rec(
          'a',
          body: '<p>x</p><img src="$url">',
          owners: {'tempCache'},
          media: {
            url: MediaEntry(
              file: ArticleMediaStore.fileNameFor(url),
              byteSize: 3,
              state: MediaState.ready,
            ),
          },
        ),
      );
      final p = ArticlePageProvider(item: pageItem(content: null));
      await p.loadSavedCopy(
        records: store,
        media: ArticleMediaStore(root: mediaDir),
      );
      expect(p.displayContent, isNot(contains('file://')));
      p.dispose();
    });

    test(
      'a ready manifest whose file is gone cannot claim ready on the strip',
      () async {
        final store = newStore();
        const url = 'https://e.com/i.png';
        await store.write(
          rec(
            'a',
            body: '<p>x</p><img src="$url">',
            owners: {'bookmark'},
            media: {
              url: MediaEntry(
                file: ArticleMediaStore.fileNameFor(url),
                byteSize: 3,
                state: MediaState.ready,
              ),
            },
          ),
        );
        final p = ArticlePageProvider(
          item: pageItem(content: null, isBookmarked: true),
        );
        await p.loadSavedCopy(
          records: store,
          media: ArticleMediaStore(root: mediaDir),
        );
        // Manifest says ready, disk says otherwise — the strip must show
        // text-saved, converging with the list surface's verify-repair.
        expect(p.recordStatus!.fullyReady, isFalse);
        expect(p.recordStatus!.scope, ArticleScope.savedText);
        expect(p.recordStatus!.readyMedia, 0);
        p.dispose();
      },
    );
  });

  group('managed file src validation', () {
    test('accepts a managed m_ path', () {
      final f = ArticleMediaStore.managedFileFromSrc(
        'file:///data/m_${'a' * 16}',
      );
      expect(f, isNotNull);
      expect(f!.path.endsWith('m_${'a' * 16}'), isTrue);
    });

    test('rejects non-managed names, traversal, and malformed input', () {
      expect(
        ArticleMediaStore.managedFileFromSrc('file:///etc/passwd'),
        isNull,
      );
      expect(
        ArticleMediaStore.managedFileFromSrc('file:///x/../m_${'a' * 16}'),
        isNull,
      );
      expect(ArticleMediaStore.managedFileFromSrc('file:///x/m_%zz'), isNull);
      expect(
        ArticleMediaStore.managedFileFromSrc('https://e.com/i.png'),
        isNull,
      );
    });
  });

  group('status equality', () {
    test('same record derives an equal status', () {
      final a = ArticleStatus.fromRecord(
        rec('a', body: '<p>x</p>', media: {'u': mediaEntry('u')}),
      );
      final b = ArticleStatus.fromRecord(
        rec('a', body: '<p>x</p>', media: {'u': mediaEntry('u')}),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differing records derive different statuses', () {
      final a = ArticleStatus.fromRecord(rec('a', body: '<p>x</p>'));
      final b = ArticleStatus.fromRecord(
        rec('a', body: '<p>x</p>', media: {'u': mediaEntry('u')}),
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('waitSource persistence', () {
    test('server Retry-After stamp survives a store roundtrip', () async {
      final store = newStore();
      await store.write(
        rec(
          'a',
          body: '<p>x</p>',
          media: {
            'u': mediaEntry(
              'u',
              state: MediaState.failed,
              nextRetryAt: DateTime.utc(2025, 1, 1, 13),
              waitSource: 'server',
            ),
          },
        ),
      );
      final r = await newStore().read(ref('a'));
      expect(r!.media['u']!.waitSource, 'server');
    });
  });
}
