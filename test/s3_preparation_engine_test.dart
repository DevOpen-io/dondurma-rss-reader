import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Color, Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/feed_backoff.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

void main() {
  late Directory tempDir;
  late File stateFile;
  late Directory mediaDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('s3_prep_test_');
  });

  setUp(() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    stateFile = File('${tempDir.path}/prep_$stamp.json');
    mediaDir = Directory('${tempDir.path}/media_$stamp')
      ..createSync(recursive: true);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  ArticleRecordStore newStore() =>
      ArticleRecordStore(FileObservedArticlePersistence(stateFile: stateFile));

  FeedItem item({
    String id = 'art-1',
    String link = 'https://example.com/article/1',
    String? imageUrl,
    String? content,
  }) => FeedItem(
    id: id,
    siteName: 'Example',
    title: 'T $id',
    description: 'd',
    timeAgo: '1h',
    siteIcon: Icons.rss_feed,
    iconColor: const Color(0xFF000000),
    iconBackgroundColor: const Color(0xFFFFFFFF),
    link: link,
    imageUrl: imageUrl,
    content: content,
    feedUrl: 'https://example.com/feed.xml',
  );

  ArticlePreparationService service({
    http_testing.MockClient? client,
    Future<String?> Function(String url)? extract,
    Duration? minHostGap,
    FeedBackoff? backoff,
    DateTime Function()? now,
  }) => ArticlePreparationService(
    recordStore: newStore(),
    mediaStore: ArticleMediaStore(root: mediaDir),
    client:
        client ?? http_testing.MockClient((_) async => http.Response('', 404)),
    extractFullText: extract,
    minHostGap: minHostGap ?? Duration.zero,
    backoff: backoff,
    now: now,
  );

  group('registerArticle', () {
    test(
      'creates record with bookmark owner, RSS body, pending manifest',
      () async {
        final svc = service();
        final result = await svc.registerArticle(
          item(
            imageUrl: 'https://example.com/thumb.png',
            content: '<p>hi</p><img src="https://example.com/a.png">',
          ),
          const {'bookmark'},
        );
        expect(result, StoreWriteResult.applied);

        final record = (await newStore().read('art-1'))!;
        expect(record.owners, {'bookmark'});
        expect(record.body, contains('<p>hi</p>'));
        expect(record.link, 'https://example.com/article/1');
        expect(record.bodyState, MediaState.pending);
        expect(record.media.keys.toSet(), {
          'https://example.com/thumb.png',
          'https://example.com/a.png',
        });
        expect(
          record.media.values.every((e) => e.state == MediaState.pending),
          isTrue,
        );
      },
    );

    test(
      'is idempotent: unions owners, preserves content and ready pieces',
      () async {
        final svc = service();
        await svc.registerArticle(item(), const {'tempCache'});

        // Mark one media entry ready, then re-register.
        await newStore().mutate(
          'art-1',
          (c) => c!.copyWith(
            media: {
              'https://example.com/existing.png': const MediaEntry(
                file: 'm_0123456789abcdef',
                byteSize: 5,
                state: MediaState.ready,
              ),
            },
          ),
        );
        await svc.registerArticle(item(), const {'bookmark'});

        final record = (await newStore().read('art-1'))!;
        expect(record.owners, {'tempCache', 'bookmark'});
        expect(
          record.media['https://example.com/existing.png']!.state,
          MediaState.ready,
        );
      },
    );

    test('empty owners are rejected — ownerless records never exist', () async {
      expect(
        await service().registerArticle(item(), const {}),
        StoreWriteResult.rejected,
      );
      expect(await newStore().read('art-1'), isNull);
    });

    test('a tombstoned record is revived, not silently overwritten', () async {
      final svc = service();
      await svc.registerArticle(item(), const {'bookmark'});
      await newStore().tombstone('art-1');

      expect(
        await svc.registerArticle(item(), const {'bookmark'}),
        StoreWriteResult.applied,
      );
      final record = (await newStore().read('art-1'))!;
      expect(record.tombstoned, isFalse);
      expect(record.generation, greaterThan(2));
      // A stale writer fenced to the old generation still loses.
      expect(
        await newStore().writeIfGeneration(record.copyWith(generation: 1), 1),
        StoreWriteResult.rejected,
      );
    });
  });

  group('prepareArticle (explicit single-article permit)', () {
    test(
      'extraction success upgrades body; body images join the manifest',
      () async {
        http_testing.MockClient client = http_testing.MockClient((req) async {
          return http.Response('IMG:${req.url}', 200);
        });
        final svc = service(
          client: client,
          extract: (_) async =>
              '<p>full</p><img src="https://example.com/new.png">',
        );
        await svc.registerArticle(item(), const {'bookmark'});
        await svc.prepareArticle('art-1');

        final record = (await newStore().read('art-1'))!;
        expect(record.body, contains('<p>full</p>'));
        expect(record.bodyState, MediaState.ready);
        expect(
          record.media['https://example.com/new.png']!.state,
          MediaState.ready,
        );
        expect(
          await ArticleMediaStore(
            root: mediaDir,
          ).verify(record.media['https://example.com/new.png']!),
          isTrue,
        );
      },
    );

    test(
      'extraction failure keeps RSS body, marks failed, schedules retry',
      () async {
        final svc = service(extract: (_) async => null);
        await svc.registerArticle(item(content: '<p>rss body</p>'), const {
          'bookmark',
        });
        await svc.prepareArticle('art-1');

        final record = (await newStore().read('art-1'))!;
        expect(record.body, contains('rss body'));
        expect(record.bodyState, MediaState.failed);
        expect(record.nextRetryAt, isNotNull);
      },
    );

    test('same-host media requests are spaced by minHostGap', () async {
      const gap = Duration(milliseconds: 300);
      final hits = <DateTime>[];
      final client = http_testing.MockClient((req) async {
        hits.add(DateTime.now());
        return http.Response(
          'IMG',
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final svc = service(
        client: client,
        minHostGap: gap,
        extract: (_) async =>
            '<p>b</p><img src="https://h.example/1.png">'
            '<img src="https://h.example/2.png">',
      );
      await svc.registerArticle(item(), const {'bookmark'});
      await svc.prepareArticle('art-1');

      expect(hits.length, 2);
      expect(hits[1].difference(hits[0]), greaterThanOrEqualTo(gap * 0.8));
    });

    test('different hosts are not paced against each other', () async {
      const gap = Duration(milliseconds: 400);
      final hits = <DateTime>[];
      final client = http_testing.MockClient((req) async {
        hits.add(DateTime.now());
        return http.Response(
          'IMG',
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final svc = service(
        client: client,
        minHostGap: gap,
        extract: (_) async =>
            '<p>b</p><img src="https://a.example/1.png">'
            '<img src="https://b.example/2.png">',
      );
      await svc.registerArticle(item(), const {'bookmark'});
      await svc.prepareArticle('art-1');

      expect(hits.length, 2);
      expect(hits[1].difference(hits[0]), lessThan(gap));
    });

    test('each piece is attempted at most once per pass', () async {
      var calls = 0;
      final client = http_testing.MockClient((req) async {
        calls++;
        return http.Response('x', 500);
      });
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(
        item(imageUrl: 'https://example.com/a.png'),
        const {'bookmark'},
      );
      await svc.prepareArticle('art-1');
      expect(calls, 1); // one attempt per piece per pass, even on failure

      final record = (await newStore().read('art-1'))!;
      final entry = record.media['https://example.com/a.png']!;
      expect(entry.state, MediaState.failed);
      expect(entry.attempts, 1);
      expect(entry.nextRetryAt, isNotNull);
    });

    test('the explicit permit never bypasses a stored Retry-After', () async {
      var calls = 0;
      final client = http_testing.MockClient((_) async {
        calls++;
        return http.Response('x', 200);
      });
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(item(), const {'bookmark'});
      await newStore().mutate(
        'art-1',
        (c) => c!.copyWith(
          bodyState: MediaState.ready,
          media: {
            'https://e.com/i.png': MediaEntry(
              file: 'm_0123456789abcdef',
              byteSize: 0,
              state: MediaState.failed,
              attempts: 1,
              nextRetryAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          },
        ),
      );
      await svc.prepareArticle('art-1');
      expect(calls, 0);
    });

    test('a missing record is a no-op', () async {
      expect(await service().prepareArticle('ghost'), 0);
    });

    test('a host cooldown learned by feed refresh skips extraction and '
        'media without counting failures; the RSS body stays', () async {
      var extractCalls = 0;
      var httpCalls = 0;
      final client = http_testing.MockClient((_) async {
        httpCalls++;
        return http.Response('x', 200);
      });
      // The RSS feed on this origin was rate-limited — article body
      // extraction and image downloads on the same host must wait out
      // the shared cooldown instead of piling on.
      final backoff = FeedBackoff()
        ..recordFailure(
          'https://example.com/feed.xml',
          FeedFetchException(
            FeedFetchErrorKind.httpStatus,
            'status 429',
            statusCode: 429,
          ),
          DateTime.now(),
        );
      final svc = service(
        client: client,
        extract: (_) async {
          extractCalls++;
          return '<p>ok</p>';
        },
        backoff: backoff,
      );
      await svc.registerArticle(
        item(imageUrl: 'https://example.com/a.png', content: '<p>rss body</p>'),
        const {'bookmark'},
      );
      await svc.preparePending(unmetered: true);

      expect(extractCalls, 0); // extraction skipped
      expect(httpCalls, 0); // media download skipped
      final record = (await newStore().read('art-1'))!;
      // Nothing was attempted → no failure recorded; pieces stay
      // pending for a later pass and the RSS body is untouched.
      expect(record.bodyState, MediaState.pending);
      expect(record.attempts, 0);
      expect(record.body, '<p>rss body</p>');
      expect(
        record.media['https://example.com/a.png']!.state,
        MediaState.pending,
      );
    });

    test('a manual retry still honors a mandated host cooldown', () async {
      var httpCalls = 0;
      final client = http_testing.MockClient((_) async {
        httpCalls++;
        return http.Response('x', 200);
      });
      final backoff = FeedBackoff()
        ..recordFailure(
          'https://example.com/feed.xml',
          FeedFetchException(
            FeedFetchErrorKind.httpStatus,
            'status 429',
            retryAfter: DateTime.now().add(const Duration(minutes: 10)),
            statusCode: 429,
          ),
          DateTime.now(),
        );
      final svc = service(
        client: client,
        extract: (_) async => '<p>ok</p>',
        backoff: backoff,
      );
      await svc.registerArticle(
        item(imageUrl: 'https://example.com/a.png'),
        const {'bookmark'},
      );
      // prepareArticle is the explicit (manual) path.
      await svc.prepareArticle('art-1');
      expect(httpCalls, 0); // server mandate survives the explicit retry
    });

    test(
      'a manual retry may bypass a locally estimated host cooldown',
      () async {
        var extractCalls = 0;
        var httpCalls = 0;
        final client = http_testing.MockClient((_) async {
          httpCalls++;
          return http.Response('img', 200);
        });
        // 429 without Retry-After → local estimate, bypassable by the user.
        final backoff = FeedBackoff()
          ..recordFailure(
            'https://example.com/feed.xml',
            FeedFetchException(
              FeedFetchErrorKind.httpStatus,
              'status 429',
              statusCode: 429,
            ),
            DateTime.now(),
          );
        final svc = service(
          client: client,
          extract: (_) async {
            extractCalls++;
            return '<p>ok</p>';
          },
          backoff: backoff,
        );
        await svc.registerArticle(
          item(imageUrl: 'https://example.com/a.png'),
          const {'bookmark'},
        );
        await svc.prepareArticle('art-1');
        expect(extractCalls, 1);
        expect(httpCalls, 1);
      },
    );

    test('a media request cooled while queued is deferred — zero requests, '
        'no failure, stays pending', () async {
      var httpCalls = 0;
      final backoff = FeedBackoff();
      final client = http_testing.MockClient((_) async {
        httpCalls++;
        // The first download lands, then the host gets limited — the
        // sibling still sitting in the pacing queue must defer, not
        // fire and not fail.
        backoff.recordFailure(
          'https://example.com/feed.xml',
          FeedFetchException(
            FeedFetchErrorKind.httpStatus,
            'status 429',
            statusCode: 429,
          ),
          DateTime.now(),
        );
        return http.Response('img', 200);
      });
      // A nonzero gap is what keeps piece B queued long enough to see
      // the cooldown the sibling's response just recorded.
      final svc = service(
        client: client,
        // Extraction fails → the RSS body stays as the fallback.
        extract: (_) async => null,
        backoff: backoff,
        minHostGap: const Duration(milliseconds: 150),
      );
      await svc.registerArticle(
        item(
          imageUrl: 'https://example.com/a.png',
          content: '<p>rss body</p><img src="https://example.com/b.png">',
        ),
        const {'bookmark'},
      );
      await svc.preparePending(unmetered: true);

      expect(httpCalls, 1); // only the first piece ever hit the network
      final record = (await newStore().read('art-1'))!;
      final a = record.media['https://example.com/a.png']!;
      final b = record.media['https://example.com/b.png']!;
      expect(a.state, MediaState.ready);
      // B was deferred, not attempted: pending, zero attempts, no
      // rescheduled retry — and the RSS body is untouched.
      expect(b.state, MediaState.pending);
      expect(b.attempts, 0);
      expect(b.nextRetryAt, isNull);
      expect(record.body, contains('rss body'));
    });

    test('an extraction null inside a host cooldown is deferred, '
        'not counted as a failure', () async {
      final backoff = FeedBackoff();
      var extractCalls = 0;
      final svc = service(
        extract: (_) async {
          extractCalls++;
          // The extraction's own pace wait spanned a sibling request's
          // 429 — it saw the shared cooldown and returned null without
          // fetching. By the time prep inspects the result the host is
          // already cooled, so the attempt must be deferred, not failed.
          backoff.recordFailure(
            'https://example.com/feed.xml',
            FeedFetchException(
              FeedFetchErrorKind.httpStatus,
              'status 429',
              statusCode: 429,
            ),
            DateTime.now(),
          );
          return null;
        },
        backoff: backoff,
      );
      await svc.registerArticle(item(content: '<p>rss body</p>'), const {
        'bookmark',
      });
      await svc.preparePending(unmetered: true);

      expect(extractCalls, 1); // extraction ran, deferred mid-request
      final record = (await newStore().read('art-1'))!;
      expect(record.bodyState, MediaState.pending); // not failed
      expect(record.attempts, 0);
      expect(record.nextRetryAt, isNull);
      expect(record.body, '<p>rss body</p>');
    });

    test('a media 429 is reported to the shared host backoff — the '
        'whole origin cools down', () async {
      final backoff = FeedBackoff();
      var httpCalls = 0;
      final client = http_testing.MockClient((_) async {
        httpCalls++;
        return http.Response('x', 429, headers: {'retry-after': '300'});
      });
      final svc = service(
        client: client,
        extract: (_) async => '<p>ok</p>',
        backoff: backoff,
      );
      await svc.registerArticle(
        item(imageUrl: 'https://example.com/a.png'),
        const {'bookmark'},
      );
      await svc.preparePending(unmetered: true);

      expect(httpCalls, 1);
      // A host-level, server-mandated cooldown now covers the whole
      // origin — including a URL that never produced a failure.
      final now = DateTime.now();
      expect(backoff.isBackedOff('https://example.com/other.png', now), isTrue);
      expect(
        backoff.isMandatedBackedOff('https://example.com/other.png', now),
        isTrue,
      );
    });

    test('Retry-After is computed from response time, not the stale sweep '
        'clock', () async {
      var t = DateTime.now();
      final client = http_testing.MockClient((_) async {
        // The piece sat behind the semaphore/pacer for "30 minutes".
        t = t.add(const Duration(minutes: 30));
        return http.Response('x', 429, headers: {'retry-after': '300'});
      });
      final svc = service(
        client: client,
        extract: (_) async => 'ok',
        now: () => t,
      );
      await svc.registerArticle(
        item(imageUrl: 'https://example.com/a.png'),
        const {'bookmark'},
      );
      await svc.preparePending(unmetered: true);

      final record = (await newStore().read('art-1'))!;
      final entry = record.media['https://example.com/a.png']!;
      // Sweep-start math would store t0+5m (already past); the deadline
      // must anchor at the response instant ≈ t0+30m+5m.
      expect(
        entry.nextRetryAt!.isAfter(t.subtract(const Duration(minutes: 2))),
        isTrue,
      );
      expect(entry.waitSource, 'server');
    });

    test('a ready piece is never re-fetched on a later pass', () async {
      var calls = 0;
      final client = http_testing.MockClient((req) async {
        calls++;
        return http.Response('img', 200);
      });
      final svc = service(client: client, extract: (_) async => '<p>ok</p>');
      await svc.registerArticle(item(imageUrl: 'https://e.com/i.png'), const {
        'bookmark',
      });
      await svc.prepareArticle('art-1');
      expect(calls, 1);
      await svc.prepareArticle('art-1');
      await svc.preparePending(unmetered: true);
      expect(calls, 1); // ready is terminal for fetching
    });

    test('overlapping calls cannot double-attempt a piece', () async {
      var calls = 0;
      final client = http_testing.MockClient((req) async {
        calls++;
        return http.Response('img', 200);
      });
      final svc = service(client: client, extract: (_) async => '<p>ok</p>');
      await svc.registerArticle(item(imageUrl: 'https://e.com/i.png'), const {
        'bookmark',
      });
      // Two enqueued passes on the same instance run strictly in order.
      await Future.wait([
        svc.prepareArticle('art-1'),
        svc.preparePending(unmetered: true),
      ]);
      expect(calls, 1);
    });
  });

  group('permanent failures', () {
    test('a 404 marks the piece gone and it is never retried', () async {
      var calls = 0;
      final client = http_testing.MockClient((_) async {
        calls++;
        return http.Response('not found', 404);
      });
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(
        item(imageUrl: 'https://e.com/dead.png'),
        const {'bookmark'},
      );
      await svc.prepareArticle('art-1');
      expect(
        (await newStore().read(
          'art-1',
        ))!.media['https://e.com/dead.png']!.state,
        MediaState.gone,
      );
      // Gone pieces leave the due-work scan: later sweeps never retry.
      expect(await svc.preparePending(unmetered: true), 0);
      expect(calls, 1);
    });

    test('a soft-404 HTML payload is not stored as ready media', () async {
      final client = http_testing.MockClient(
        (_) async => http.Response(
          '<html><body>not found</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      );
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(
        item(imageUrl: 'https://e.com/soft.png'),
        const {'bookmark'},
      );
      await svc.prepareArticle('art-1');
      expect(
        (await newStore().read(
          'art-1',
        ))!.media['https://e.com/soft.png']!.state,
        MediaState.gone,
      );
    });

    test(
      'an over-limit payload is rejected without touching the pool',
      () async {
        final client = http_testing.MockClient(
          (_) async => http.Response.bytes(
            List.filled(ArticlePreparationService.maxMediaBytes + 1, 1),
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        final svc = service(client: client, extract: (_) async => 'ok');
        await svc.registerArticle(
          item(imageUrl: 'https://e.com/huge.png'),
          const {'bookmark'},
        );
        await svc.prepareArticle('art-1');
        expect(
          (await newStore().read(
            'art-1',
          ))!.media['https://e.com/huge.png']!.state,
          MediaState.gone,
        );
        expect(mediaDir.listSync().whereType<File>(), isEmpty);
      },
    );

    test('a racing transient failure cannot re-arm a gone piece', () async {
      // Two instances on the same store file emulate the foreground /
      // background-isolate race: A's fetch is still in flight when B
      // already classified the piece as gone.
      final gate = Completer<void>();
      final clientA = http_testing.MockClient((_) async {
        await gate.future;
        return http.Response('err', 500);
      });
      final clientB = http_testing.MockClient(
        (_) async => http.Response('nf', 404),
      );
      final svcA = service(client: clientA, extract: (_) async => 'ok');
      final svcB = service(client: clientB, extract: (_) async => 'ok');

      await svcA.registerArticle(
        item(imageUrl: 'https://e.com/race.png'),
        const {'bookmark'},
      );
      final passA = svcA.prepareArticle('art-1');
      await svcB.prepareArticle('art-1'); // finishes first → gone
      expect(
        (await newStore().read(
          'art-1',
        ))!.media['https://e.com/race.png']!.state,
        MediaState.gone,
      );
      gate.complete();
      await passA; // A's 500 lands after B's 404
      final entry = (await newStore().read(
        'art-1',
      ))!.media['https://e.com/race.png']!;
      expect(entry.state, MediaState.gone); // never re-armed
      expect(entry.nextRetryAt, isNull);
    });

    test('one record failure does not abort the sweep', () async {
      final client = http_testing.MockClient((req) async {
        if (req.url.host == 'bad.com') throw const SocketException('down');
        return http.Response('img', 200);
      });
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(
        item(id: 'a-bad', imageUrl: 'https://bad.com/i.png'),
        const {'bookmark'},
      );
      await svc.registerArticle(
        item(id: 'a-good', imageUrl: 'https://e.com/i.png'),
        const {'bookmark'},
      );
      expect(await svc.preparePending(unmetered: true), 2);
      final good = (await newStore().read('a-good'))!;
      expect(good.media['https://e.com/i.png']!.state, MediaState.ready);
    });
  });

  group('preparePending (automatic sweep)', () {
    test('metered network blocks the automatic sweep entirely', () async {
      var calls = 0;
      final client = http_testing.MockClient((_) async {
        calls++;
        return http.Response('x', 200);
      });
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(item(imageUrl: 'https://e.com/i.png'), const {
        'bookmark',
      });

      expect(await svc.preparePending(unmetered: false), 0);
      expect(calls, 0);
    });

    test('an unmetered sweep prepares due records end to end', () async {
      var imageCalls = 0;
      final client = http_testing.MockClient((req) async {
        imageCalls++;
        return http.Response('img', 200);
      });
      final svc = service(client: client, extract: (_) async => '<p>ok</p>');
      await svc.registerArticle(item(imageUrl: 'https://e.com/i.png'), const {
        'bookmark',
      });
      expect(await svc.preparePending(unmetered: true), 1);
      expect(imageCalls, 1);
      final record = (await newStore().read('art-1'))!;
      expect(record.bodyState, MediaState.ready);
      expect(record.media['https://e.com/i.png']!.state, MediaState.ready);
    });

    test('ownerless records are skipped even when work remains', () async {
      var calls = 0;
      final client = http_testing.MockClient((_) async {
        calls++;
        return http.Response('x', 200);
      });
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(item(), const {'bookmark'});
      await newStore().mutate('art-1', (c) => c!.copyWith(owners: const {}));
      expect(await svc.preparePending(unmetered: true), 0);
      expect(calls, 0);
    });

    test('records with a future nextRetryAt are skipped', () async {
      final client = http_testing.MockClient(
        (_) async => http.Response('x', 200),
      );
      final svc = service(client: client, extract: (_) async => 'ok');
      await svc.registerArticle(item(), const {'bookmark'});
      // Body already ready, one media piece scheduled into the future.
      await newStore().mutate(
        'art-1',
        (c) => c!.copyWith(
          bodyState: MediaState.ready,
          media: {
            'https://e.com/i.png': MediaEntry(
              file: 'm_0123456789abcdef',
              byteSize: 0,
              state: MediaState.failed,
              attempts: 1,
              nextRetryAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          },
        ),
      );
      expect(await svc.preparePending(unmetered: true), 0);
    });

    test('tombstoned records are never resurrected by the sweep', () async {
      final svc = service(extract: (_) async => 'ok');
      await svc.registerArticle(item(), const {'bookmark'});
      await newStore().tombstone('art-1');
      expect(await svc.preparePending(unmetered: true), 0);
      expect((await newStore().read('art-1'))!.tombstoned, isTrue);
    });

    test('at most three transfers run in parallel', () async {
      var inFlight = 0;
      var peak = 0;
      final client = http_testing.MockClient((req) async {
        inFlight++;
        peak = inFlight > peak ? inFlight : peak;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        inFlight--;
        return http.Response('img', 200);
      });
      final svc = service(client: client, extract: (_) async => '<p>x</p>');
      await svc.registerArticle(
        item(
          content:
              '<img src="https://e.com/1.png"><img src="https://e.com/2.png">'
              '<img src="https://e.com/3.png"><img src="https://e.com/4.png">'
              '<img src="https://e.com/5.png">',
        ),
        const {'bookmark'},
      );
      await svc.prepareArticle('art-1');
      expect(peak, lessThanOrEqualTo(3));
    });
  });

  group('backoff + Retry-After', () {
    test('backoff doubles per attempt, capped at 60 minutes', () {
      expect(
        ArticlePreparationService.backoffFor(1),
        const Duration(minutes: 1),
      );
      expect(
        ArticlePreparationService.backoffFor(2),
        const Duration(minutes: 2),
      );
      expect(
        ArticlePreparationService.backoffFor(3),
        const Duration(minutes: 4),
      );
      expect(
        ArticlePreparationService.backoffFor(6),
        const Duration(minutes: 32),
      );
      expect(
        ArticlePreparationService.backoffFor(7),
        const Duration(minutes: 60),
      );
      expect(
        ArticlePreparationService.backoffFor(20),
        const Duration(minutes: 60),
      );
    });

    test('a longer Retry-After is honored over the computed backoff', () async {
      final client = http_testing.MockClient((req) async {
        return http.Response('', 429, headers: {'retry-after': '3600'});
      });
      final now = DateTime.utc(2026, 1, 1);
      final svc = ArticlePreparationService(
        recordStore: newStore(),
        mediaStore: ArticleMediaStore(root: mediaDir),
        client: client,
        extractFullText: (_) async => 'ok',
        now: () => now,
      );
      await svc.registerArticle(item(imageUrl: 'https://e.com/r.png'), const {
        'bookmark',
      });
      await svc.prepareArticle('art-1');

      final entry = (await newStore().read(
        'art-1',
      ))!.media['https://e.com/r.png']!;
      expect(entry.nextRetryAt, now.add(const Duration(seconds: 3600)));
    });

    test('a shorter Retry-After loses to the computed backoff', () async {
      final client = http_testing.MockClient((req) async {
        return http.Response('', 429, headers: {'retry-after': '5'});
      });
      final now = DateTime.utc(2026, 1, 1);
      final svc = ArticlePreparationService(
        recordStore: newStore(),
        mediaStore: ArticleMediaStore(root: mediaDir),
        client: client,
        extractFullText: (_) async => 'ok',
        now: () => now,
      );
      await svc.registerArticle(item(imageUrl: 'https://e.com/r.png'), const {
        'bookmark',
      });
      // First attempt → attempts=1 → backoff 1min > 5s Retry-After.
      await svc.prepareArticle('art-1');
      final entry = (await newStore().read(
        'art-1',
      ))!.media['https://e.com/r.png']!;
      expect(entry.nextRetryAt, now.add(const Duration(minutes: 1)));
    });
  });

  group('network eligibility', () {
    test('unmeteredNetwork: unmetered transport required, metered vetoes', () {
      expect(
        ArticlePreparationService.unmeteredNetwork([ConnectivityResult.wifi]),
        isTrue,
      );
      expect(
        ArticlePreparationService.unmeteredNetwork([
          ConnectivityResult.ethernet,
        ]),
        isTrue,
      );
      expect(
        ArticlePreparationService.unmeteredNetwork([
          ConnectivityResult.wifi,
          ConnectivityResult.vpn,
        ]),
        isTrue,
      );
      // VPN over cellular still reports mobile — metering wins.
      expect(
        ArticlePreparationService.unmeteredNetwork([
          ConnectivityResult.mobile,
          ConnectivityResult.vpn,
        ]),
        isFalse,
      );
      expect(
        ArticlePreparationService.unmeteredNetwork([ConnectivityResult.mobile]),
        isFalse,
      );
      // VPN alone says nothing about cost — unknown waits.
      expect(
        ArticlePreparationService.unmeteredNetwork([ConnectivityResult.vpn]),
        isFalse,
      );
      expect(
        ArticlePreparationService.unmeteredNetwork([ConnectivityResult.other]),
        isFalse,
      );
      expect(ArticlePreparationService.unmeteredNetwork(const []), isFalse);
      expect(
        ArticlePreparationService.unmeteredNetwork([ConnectivityResult.none]),
        isFalse,
      );
    });
  });
}
