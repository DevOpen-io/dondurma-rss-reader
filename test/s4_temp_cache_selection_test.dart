import 'dart:io';

import 'package:flutter/material.dart' show Color, Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';
import 'package:ice_cream_rss_reader/services/temp_cache_membership.dart';

void main() {
  late Directory tempDir;
  late File stateFile;
  late Directory mediaDir;
  var stamp = 0;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('s4_cache_test_');
  });

  setUp(() {
    stamp++;
    stateFile = File('${tempDir.path}/cache_$stamp.json');
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

  TempCacheMembership membership() => TempCacheMembership(
    records: newStore(),
    preparation: ArticlePreparationService(
      recordStore: newStore(),
      mediaStore: ArticleMediaStore(root: mediaDir),
      client: http_testing.MockClient((_) async => http.Response('x', 404)),
    ),
  );

  FeedItem item(
    String id, {
    String feedUrl = 'https://f.com/feed',
    DateTime? pubDate,
    String? link,
    String title = 't',
    String? description,
    bool isRead = false,
  }) => FeedItem(
    id: id,
    siteName: 'F',
    title: title,
    description: description ?? 'd $id',
    timeAgo: '1h',
    siteIcon: Icons.rss_feed,
    iconColor: const Color(0xFF000000),
    iconBackgroundColor: const Color(0xFFFFFFFF),
    link: link ?? 'https://example.com/$id',
    pubDate: pubDate,
    isRead: isRead,
    feedUrl: feedUrl,
  );

  Set<String> ownersOf(ArticleRecord? r) => r?.owners ?? const {};

  Future<Set<String>> reconcile({
    List<FeedItem> items = const [],
    Set<String> bookmarked = const {},
    Iterable<String> subscribedFeedUrls = const [
      'https://f.com/feed',
      'https://g.com/feed',
    ],
    int limit = 50,
    List<String> globalKeywords = const [],
    Map<String, List<String>> feedKeywords = const {},
    bool fullText = true,
    DateTime? now,
  }) => membership().reconcile(
    items: items,
    bookmarkedIds: bookmarked,
    subscribedFeedUrls: subscribedFeedUrls,
    globalKeywords: globalKeywords,
    feedKeywordsMap: feedKeywords,
    limit: limit,
    fullTextFor: (_) => fullText,
    now: now,
  );

  final day = DateTime.utc(2026, 1, 10, 12);

  group('selection contract (#37)', () {
    test('N=2: a bookmarked newest item never consumes a temp slot', () async {
      final selected = await reconcile(
        items: [
          item('d', pubDate: day),
          item('b', pubDate: day.subtract(const Duration(hours: 1))),
          item('c', pubDate: day.subtract(const Duration(hours: 2))),
          item('a', pubDate: day.subtract(const Duration(hours: 3))),
        ],
        bookmarked: {'d'},
        limit: 2,
      );
      expect(selected, {'b', 'c'});
      expect(
        ownersOf(await newStore().read('d')),
        isNot(contains('tempCache')),
      );
    });

    test('no per-feed share: a busier feed can hold more slots', () async {
      final selected = await reconcile(
        items: [
          item('a1', pubDate: day),
          item('a2', pubDate: day.subtract(const Duration(minutes: 1))),
          item('a3', pubDate: day.subtract(const Duration(minutes: 2))),
          item(
            'b1',
            feedUrl: 'https://g.com/feed',
            pubDate: day.subtract(const Duration(hours: 2)),
          ),
        ],
        limit: 2,
      );
      expect(selected, {'a1', 'a2'});
    });

    test('read state never affects selection', () async {
      final selected = await reconcile(
        items: [
          item('read-old', pubDate: day, isRead: true),
          item('unread-new', pubDate: day.subtract(const Duration(hours: 9))),
        ],
        limit: 1,
      );
      expect(selected, {'read-old'});
    });

    test(
      'equal dates resolve deterministically by id — no reshuffling',
      () async {
        final items = [
          item('z', pubDate: day),
          item('a', pubDate: day),
          item('m', pubDate: day),
        ];
        expect(await reconcile(items: items, limit: 2), {'a', 'm'});
        // Repeated passes agree — membership is stable.
        expect(await reconcile(items: items, limit: 2), {'a', 'm'});
      },
    );
  });

  group('dedup and keywords', () {
    test('the same normalized link from two feeds takes one slot', () async {
      final selected = await reconcile(
        items: [
          item(
            'copy-g',
            feedUrl: 'https://g.com/feed',
            link: 'https://example.com/same',
            pubDate: day,
          ),
          item('copy-f', link: 'https://example.com/same', pubDate: day),
          item('other', pubDate: day.subtract(const Duration(hours: 1))),
        ],
        limit: 2,
      );
      expect(selected, hasLength(2));
      expect(selected, contains('other'));
    });

    test(
      'a blocked copy cannot block an eligible copy of the same link',
      () async {
        final selected = await reconcile(
          items: [
            item(
              'blocked-copy',
              feedUrl: 'https://g.com/feed',
              link: 'https://example.com/same',
              title: 'banned word story',
              pubDate: day,
            ),
            item(
              'clean-copy',
              link: 'https://example.com/same',
              title: 'clean',
              pubDate: day.subtract(const Duration(minutes: 1)),
            ),
          ],
          globalKeywords: ['banned'],
          limit: 1,
        );
        expect(selected, {'clean-copy'});
      },
    );

    test('a keyword-excluded item never becomes a member', () async {
      await reconcile(
        items: [item('banned', title: 'banned thing', pubDate: day)],
        globalKeywords: ['banned'],
      );
      expect(ownersOf(await newStore().read('banned')), isEmpty);
    });
  });

  group('membership lifecycle', () {
    test('an item that vanished from feeds stays until pushed out', () async {
      await reconcile(
        items: [
          item('a', pubDate: day),
          item('b', pubDate: day),
        ],
        limit: 2,
      );
      // 'a' no longer arrives — it remains a candidate on the next pass.
      final selected = await reconcile(
        items: [item('b', pubDate: day)],
        limit: 2,
      );
      expect(selected, {'a', 'b'});
    });

    test('newer items push the oldest member out of N', () async {
      await reconcile(items: [item('old', pubDate: day)], limit: 1);
      final selected = await reconcile(
        items: [
          item('new', pubDate: day.add(const Duration(hours: 1))),
          item('old', pubDate: day),
        ],
        limit: 1,
      );
      expect(selected, {'new'});
      expect(ownersOf(await newStore().read('old')), isEmpty);
    });

    test('a stripped member loses only the tempCache owner', () async {
      final store = newStore();
      // A bookmark-owned member that also holds tempCache.
      await membership().reconcile(
        items: [item('x', pubDate: day)],
        bookmarkedIds: const {},
        subscribedFeedUrls: const ['https://f.com/feed'],
        globalKeywords: const [],
        feedKeywordsMap: const {},
        limit: 1,
        fullTextFor: (_) => true,
      );
      await store.mutate(
        'x',
        (c) => c!.copyWith(owners: {...c.owners, 'bookmark'}),
      );
      // Push it out of N with a newer candidate.
      await reconcile(
        items: [item('y', pubDate: day.add(const Duration(hours: 1)))],
        limit: 1,
      );
      expect(ownersOf(await store.read('x')), {'bookmark'});
    });

    test('shrinking N adapts membership immediately, N=0 empties it', () async {
      final items = [
        item('a', pubDate: day),
        item('b', pubDate: day.subtract(const Duration(hours: 1))),
        item('c', pubDate: day.subtract(const Duration(hours: 2))),
      ];
      await reconcile(items: items, limit: 3);
      expect(await reconcile(items: items, limit: 1), {'a'});
      expect(ownersOf(await newStore().read('c')), isEmpty);
      expect(await reconcile(items: items, limit: 0), isEmpty);
      for (final id in ['a', 'b', 'c']) {
        expect(ownersOf(await newStore().read(id)), isEmpty);
      }
    });

    test('an unsubscribed feed member loses the slot immediately', () async {
      final store = newStore();
      await reconcile(
        items: [
          item('gone', pubDate: day),
          item('stay', pubDate: day.subtract(const Duration(hours: 1))),
        ],
        subscribedFeedUrls: const ['https://f.com/feed', 'https://g.com/feed'],
        limit: 2,
      );
      // 'gone' leaves the feed listing but stays a member while subscribed…
      var selected = await reconcile(
        items: [item('stay', feedUrl: 'https://g.com/feed', pubDate: day)],
        subscribedFeedUrls: const ['https://f.com/feed', 'https://g.com/feed'],
        limit: 1,
      );
      expect(selected, {'gone'});
      // …but unsubscribing its feed drops the owner outright — it cannot
      // squat a slot for a feed that is no longer active.
      selected = await reconcile(
        items: [item('stay', feedUrl: 'https://g.com/feed', pubDate: day)],
        subscribedFeedUrls: const ['https://g.com/feed'],
        limit: 1,
      );
      expect(selected, {'stay'});
      expect(ownersOf(await store.read('gone')), isEmpty);
    });

    test(
      'a present-but-excluded member is not re-admitted via its record',
      () async {
        final store = newStore();
        await reconcile(items: [item('x', pubDate: day)], limit: 5);
        expect(ownersOf(await store.read('x')), {TempCacheMembership.owner});
        // A new keyword arrives matching only the live item's description;
        // the record's stored title ('t') stays clean — the live verdict
        // must still be authoritative.
        final selected = await reconcile(
          items: [item('x', pubDate: day, description: 'contains spam here')],
          globalKeywords: const ['spam'],
          limit: 5,
        );
        expect(selected, isEmpty);
        expect(ownersOf(await store.read('x')), isEmpty);
      },
    );

    test(
      'a vanished member is excluded when a keyword matches its record',
      () async {
        final store = newStore();
        await reconcile(items: [item('v', pubDate: day)], limit: 5);
        // 'v' vanished from the feed listing — kept as a member while clean…
        var selected = await reconcile(items: const [], limit: 5);
        expect(selected, {'v'});
        // …but a keyword added later still evicts it at the record level
        // (records store only the title — 't' here).
        selected = await reconcile(
          items: const [],
          globalKeywords: const ['t'],
          limit: 5,
        );
        expect(selected, isEmpty);
        expect(ownersOf(await store.read('v')), isEmpty);
      },
    );

    test('tombstoned records are never candidates again', () async {
      final store = newStore();
      await reconcile(items: [item('a', pubDate: day)], limit: 2);
      await store.tombstone('a');
      final selected = await reconcile(items: const [], limit: 2);
      expect(selected, isNot(contains('a')));
      expect((await store.read('a'))!.tombstoned, isTrue);
    });
  });

  group('firstSeen stability (#37)', () {
    test(
      'a dateless item sorts by recorded firstSeen, stable across passes',
      () async {
        final t0 = DateTime.utc(2026, 1, 10, 12);
        final t1 = DateTime.utc(2026, 1, 11);
        // 'dateless' observed at noon; 'dated' is older (06:00) — the recorded
        // observation wins the slot and must never be re-stamped later.
        await reconcile(
          items: [
            item('dateless', pubDate: null),
            item('dated', pubDate: DateTime.utc(2026, 1, 10, 6)),
          ],
          limit: 1,
          now: t0,
        );
        expect(await newStore().firstSeen('dateless'), t0);

        // A later pass must NOT re-stamp the observation time.
        final selected = await reconcile(
          items: [
            item('dateless', pubDate: null),
            item('dated', pubDate: DateTime.utc(2026, 1, 10, 6)),
          ],
          limit: 1,
          now: t1,
        );
        expect(selected, {'dateless'}); // still t0-newest, not re-stamped to t1
        expect(await newStore().firstSeen('dateless'), t0);
      },
    );

    test(
      'a non-canonical guid still hits its recorded firstSeen — no re-stamp',
      () async {
        final t0 = DateTime.utc(2026, 1, 10, 12);
        final t1 = DateTime.utc(2026, 1, 11);
        // 'HTTPS://EXAMPLE.COM/x' canonicalizes to a different-case key —
        // a raw-id lookup would miss the stored stamp every pass.
        await reconcile(
          items: [item('HTTPS://EXAMPLE.COM/x', pubDate: null)],
          now: t0,
        );
        final stamped = await newStore().firstSeen('HTTPS://EXAMPLE.COM/x');
        expect(stamped, t0);
        await reconcile(
          items: [item('HTTPS://EXAMPLE.COM/x', pubDate: null)],
          now: t1,
        );
        expect(await newStore().firstSeen('HTTPS://EXAMPLE.COM/x'), stamped);
      },
    );

    test('firstSeen survives a fresh store instance (restart)', () async {
      final t0 = DateTime.utc(2026, 1, 10);
      await reconcile(items: [item('dateless', pubDate: null)], now: t0);
      // A "restarted" store on the same file sees the same observation.
      expect(await newStore().firstSeen('dateless'), t0);
    });
  });

  group('full-text preference', () {
    test(
      'fullText=false marks the RSS body final — no extraction intent',
      () async {
        await reconcile(
          items: [item('a', pubDate: day)],
          limit: 1,
          fullText: false,
        );
        expect((await newStore().read('a'))!.bodyState, MediaState.ready);
      },
    );

    test('fullText=true leaves the body pending for the sweep', () async {
      await reconcile(items: [item('a', pubDate: day)], limit: 1);
      expect((await newStore().read('a'))!.bodyState, MediaState.pending);
    });

    test(
      'fullText off→on re-arms a settled RSS body — extracted stays put',
      () async {
        final store = newStore();
        // fullText=false settles the RSS body as final.
        await reconcile(items: [item('x', pubDate: day)], fullText: false);
        expect((await store.read('x'))!.bodyState, MediaState.ready);
        // Flipping the preference on re-pends it for the extraction sweep.
        await reconcile(items: [item('x', pubDate: day)], fullText: true);
        expect((await store.read('x'))!.bodyState, MediaState.pending);
        // An already-extracted body never loses its ready state.
        await store.mutate(
          'x',
          (c) => c!.copyWith(
            bodyState: MediaState.ready,
            bodySource: () => 'extracted',
          ),
        );
        await reconcile(items: [item('x', pubDate: day)], fullText: true);
        final record = (await store.read('x'))!;
        expect(record.bodyState, MediaState.ready);
        expect(record.bodySource, 'extracted');
      },
    );
  });
}
