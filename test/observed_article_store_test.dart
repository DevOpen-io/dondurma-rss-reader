import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';
import 'package:ice_cream_rss_reader/services/observed_article_store.dart';

FeedItem _item(String feed, String id, DateTime date) => FeedItem(
  id: id,
  siteName: feed,
  title: id,
  description: '',
  timeAgo: '',
  siteIcon: Icons.rss_feed,
  iconColor: Colors.blue,
  iconBackgroundColor: Colors.blueGrey,
  feedUrl: feed,
  pubDate: date,
);

void main() {
  late Directory directory;
  late File stateFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dondurma-observed-');
    stateFile = File('${directory.path}/observed.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  ObservedArticleStore store({
    Duration timeout = const Duration(seconds: 1),
    Future<void> Function()? afterLockAcquired,
  }) => ObservedArticleStore(
    FileObservedArticlePersistence(
      stateFile: stateFile,
      lockTimeout: timeout,
      retryDelay: const Duration(milliseconds: 5),
      afterLockAcquired: afterLockAcquired,
    ),
  );

  group('initialization and durable deduplication', () {
    test(
      '304 cannot initialize empty legacy feed before authoritative 200',
      () async {
        final now = DateTime.utc(2026, 8, 24, 10);
        const feed = 'https://feed.example/rss';

        final notModified = await store().claimFeedBatch(
          feedUrl: feed,
          items: const [],
          allowInitialization: false,
          observedAt: now,
        );
        final history = List.generate(
          50,
          (index) => _item(feed, 'old-$index', now),
        );
        final authoritative = await store().claimFeedBatch(
          feedUrl: feed,
          items: history,
          observedAt: now.add(const Duration(minutes: 1)),
        );
        final genuinelyNew = await store().claimFeedBatch(
          feedUrl: feed,
          items: [...history, _item(feed, 'new', now)],
          observedAt: now.add(const Duration(minutes: 2)),
        );

        expect(notModified.initializedFeed, isFalse);
        expect(notModified.claimedItems, isEmpty);
        expect(authoritative.initializedFeed, isTrue);
        expect(authoritative.claimedItems, isEmpty);
        expect(genuinelyNew.claimedItems.map((item) => item.id), ['new']);
      },
    );

    test('304 partial cache cannot initialize legacy feed', () async {
      final now = DateTime.utc(2026, 8, 24, 10);
      const feed = 'https://feed.example/rss';

      final result = await store().claimFeedBatch(
        feedUrl: feed,
        items: [_item(feed, 'cached-only', now)],
        allowInitialization: false,
        observedAt: now,
      );
      final authoritative = await store().claimFeedBatch(
        feedUrl: feed,
        items: [_item(feed, 'cached-only', now)],
        observedAt: now.add(const Duration(minutes: 1)),
      );

      expect(result.initializedFeed, isFalse);
      expect(result.claimedItems, isEmpty);
      expect(authoritative.initializedFeed, isTrue);
      expect(authoritative.claimedItems, isEmpty);
    });

    test(
      'missing state initializes feed silently, then claims only new item',
      () async {
        final now = DateTime.utc(2026, 8, 24, 10);
        final initial = List.generate(
          50,
          (index) => _item('https://feed.example/rss', 'old-$index', now),
        );

        final first = await store().claimFeedBatch(
          feedUrl: 'https://feed.example/rss',
          items: initial,
          observedAt: now,
        );
        final next = await store().claimFeedBatch(
          feedUrl: 'https://feed.example/rss',
          items: [...initial, _item('https://feed.example/rss', 'new', now)],
          observedAt: now.add(const Duration(minutes: 1)),
        );

        expect(first.initializedFeed, isTrue);
        expect(first.claimedItems, isEmpty);
        expect(next.claimedItems.map((item) => item.id), ['new']);
      },
    );

    test('empty and corrupt state initialize silently', () async {
      await stateFile.create(recursive: true);
      final empty = await store().claimFeedBatch(
        feedUrl: 'https://a',
        items: [_item('https://a', 'a', DateTime.utc(2026))],
      );
      expect(empty.claimedItems, isEmpty);

      await stateFile.writeAsString('{broken');
      final corrupt = await store().claimFeedBatch(
        feedUrl: 'https://b',
        items: [_item('https://b', 'b', DateTime.utc(2026))],
      );
      expect(corrupt.claimedItems, isEmpty);
    });

    test('same article stays observed across store restart', () async {
      final now = DateTime.utc(2026, 8, 24);
      final article = _item('https://a', 'stable', now);
      await store().claimFeedBatch(feedUrl: 'https://a', items: [article]);

      final restarted = store();
      final repeated = await restarted.claimFeedBatch(
        feedUrl: 'https://a',
        items: [article],
      );

      expect(repeated.claimedItems, isEmpty);
    });

    test(
      'article leaving latest 50 and returning inside retention is not new',
      () async {
        final now = DateTime.utc(2026, 8, 1);
        final feed = 'https://busy.example/rss';
        final firstWindow = List.generate(
          50,
          (index) => _item(feed, 'item-$index', now),
        );
        await store().claimFeedBatch(
          feedUrl: feed,
          items: firstWindow,
          observedAt: now,
        );
        await store().claimFeedBatch(
          feedUrl: feed,
          items: List.generate(50, (index) => _item(feed, 'next-$index', now)),
          observedAt: now.add(const Duration(days: 1)),
        );

        final returned = await store().claimFeedBatch(
          feedUrl: feed,
          items: [_item(feed, 'item-0', now)],
          observedAt: now.add(const Duration(days: 13)),
        );

        expect(returned.claimedItems, isEmpty);
      },
    );

    test('duplicate IDs in one batch produce one claim', () async {
      final now = DateTime.utc(2026, 8, 24);
      const feed = 'https://a';
      await store().claimFeedBatch(feedUrl: feed, items: const []);

      final result = await store().claimFeedBatch(
        feedUrl: feed,
        items: [_item(feed, 'x', now), _item(feed, 'x', now)],
      );

      expect(result.claimedItems, hasLength(1));
    });

    test('identity is retained only for bounded retention window', () async {
      final now = DateTime.utc(2026, 8, 1);
      const feed = 'https://a';
      final article = _item(feed, 'x', now);
      await store().claimFeedBatch(
        feedUrl: feed,
        items: [article],
        observedAt: now,
      );

      final withinWindow = await store().claimFeedBatch(
        feedUrl: feed,
        items: [article],
        observedAt: now.add(const Duration(days: 13)),
      );
      await store().claimFeedBatch(
        feedUrl: feed,
        items: const [],
        observedAt: now.add(const Duration(days: 28)),
      );
      final afterWindow = await store().claimFeedBatch(
        feedUrl: feed,
        items: [article],
        observedAt: now.add(const Duration(days: 28, minutes: 1)),
      );

      expect(withinWindow.claimedItems, isEmpty);
      expect(afterWindow.claimedItems, hasLength(1));
    });

    test(
      'new subscription epoch silently initializes same URL again',
      () async {
        final now = DateTime.utc(2026, 8, 24);
        const feed = 'https://a';
        final history = [_item(feed, 'old', now)];
        await store().claimFeedBatch(
          feedUrl: feed,
          observationEpoch: 'subscription-1',
          items: history,
        );
        final firstSubscriptionNew = await store().claimFeedBatch(
          feedUrl: feed,
          observationEpoch: 'subscription-1',
          items: [...history, _item(feed, 'later', now)],
        );
        final resubscribed = await store().claimFeedBatch(
          feedUrl: feed,
          observationEpoch: 'subscription-2',
          items: [...history, _item(feed, 'later', now)],
        );

        expect(firstSubscriptionNew.claimedItems, hasLength(1));
        expect(resubscribed.initializedFeed, isTrue);
        expect(resubscribed.claimedItems, isEmpty);
      },
    );
  });

  group('failed-feed history', () {
    test(
      'alternating success and omitted failure never erases history',
      () async {
        final now = DateTime.utc(2026, 8, 24);
        const feedA = 'https://a';
        const feedB = 'https://b';
        final articleA = _item(feedA, 'a-1', now);
        final articleB = _item(feedB, 'b-1', now);
        await store().claimFeedBatch(feedUrl: feedA, items: [articleA]);
        await store().claimFeedBatch(feedUrl: feedB, items: [articleB]);

        // B fails: caller submits only successful A.
        await store().claimFeedBatch(feedUrl: feedA, items: [articleA]);
        final bRecovers = await store().claimFeedBatch(
          feedUrl: feedB,
          items: [articleB],
        );
        // A fails, then recovers.
        await store().claimFeedBatch(feedUrl: feedB, items: [articleB]);
        final aRecovers = await store().claimFeedBatch(
          feedUrl: feedA,
          items: [articleA],
        );

        expect(bRecovers.claimedItems, isEmpty);
        expect(aRecovers.claimedItems, isEmpty);
      },
    );

    test('mixed 200, 304, and failure preserves history', () async {
      final now = DateTime.utc(2026, 8, 24);
      final a1 = _item('https://a', 'a-1', now);
      final b1 = _item('https://b', 'b-1', now);
      final c1 = _item('https://c', 'c-1', now);
      await store().claimFeedBatch(feedUrl: 'https://a', items: [a1]);
      await store().claimFeedBatch(feedUrl: 'https://b', items: [b1]);
      await store().claimFeedBatch(feedUrl: 'https://c', items: [c1]);

      final a200 = await store().claimFeedBatch(
        feedUrl: 'https://a',
        items: [a1, _item('https://a', 'a-2', now)],
      );
      final b304 = await store().claimFeedBatch(
        feedUrl: 'https://b',
        items: [b1],
      );
      // C failure is represented by no store call. Recovery must remain known.
      final cRecovery = await store().claimFeedBatch(
        feedUrl: 'https://c',
        items: [c1],
      );

      expect(a200.claimedItems.map((item) => item.id), ['a-2']);
      expect(b304.claimedItems, isEmpty);
      expect(cRecovery.claimedItems, isEmpty);
    });
  });

  group('exclusive-create concurrency', () {
    test('simultaneous stores allow exactly one claim', () async {
      final now = DateTime.utc(2026, 8, 24);
      const feed = 'https://a';
      await store().claimFeedBatch(feedUrl: feed, items: const []);
      final article = _item(feed, 'x', now);

      final results = await Future.wait([
        store().claimFeedBatch(feedUrl: feed, items: [article]),
        store().claimFeedBatch(feedUrl: feed, items: [article]),
      ]);

      expect(results.expand((result) => result.claimedItems), hasLength(1));
    });

    test('independent isolates allow exactly one claim', () async {
      final now = DateTime.utc(2026, 8, 24);
      const feed = 'https://a';
      await store().claimFeedBatch(feedUrl: feed, items: const []);
      final path = stateFile.path;

      Future<int> claimFromIsolate() => Isolate.run(() async {
        final isolatedStore = ObservedArticleStore(
          FileObservedArticlePersistence(stateFile: File(path)),
        );
        final result = await isolatedStore.claimFeedBatch(
          feedUrl: feed,
          items: [_item(feed, 'x', now)],
        );
        return result.claimedItems.length;
      });

      final claims = await Future.wait([
        claimFromIsolate(),
        claimFromIsolate(),
      ]);

      expect(claims.reduce((a, b) => a + b), 1);
    });

    test('contender times out without stealing active lock', () async {
      final now = DateTime.utc(2026, 8, 24);
      const feed = 'https://a';
      await store().claimFeedBatch(feedUrl: feed, items: const []);

      final acquired = Completer<void>();
      final release = Completer<void>();
      final holder = store(
        afterLockAcquired: () async {
          acquired.complete();
          await release.future;
        },
      );
      final holderFuture = holder.claimFeedBatch(
        feedUrl: feed,
        items: [_item(feed, 'x', now)],
      );
      await acquired.future;

      final contender = await store(
        timeout: const Duration(milliseconds: 40),
      ).claimFeedBatch(feedUrl: feed, items: [_item(feed, 'x', now)]);

      expect(contender.lockTimedOut, isTrue);
      expect(contender.claimedItems, isEmpty);
      expect(await File('${stateFile.path}.lock').exists(), isTrue);

      release.complete();
      final holderResult = await holderFuture;
      expect(holderResult.claimedItems, hasLength(1));
      expect(await File('${stateFile.path}.lock').exists(), isFalse);

      final finalCheck = await store().claimFeedBatch(
        feedUrl: feed,
        items: [_item(feed, 'x', now)],
      );
      expect(finalCheck.claimedItems, isEmpty);
    });

    test('pre-existing orphan lock is never stolen', () async {
      final lock = File('${stateFile.path}.lock');
      await lock.create(recursive: true, exclusive: true);
      await lock.writeAsString('orphan\n2000-01-01T00:00:00Z');

      final result = await store(timeout: const Duration(milliseconds: 30))
          .claimFeedBatch(
            feedUrl: 'https://a',
            items: [_item('https://a', 'x', DateTime.utc(2026))],
          );

      expect(result.lockTimedOut, isTrue);
      expect(await lock.exists(), isTrue);
    });
  });
}
