import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/feed_backoff.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';

FeedFetchException rateLimit({DateTime? retryAfter, int status = 429}) =>
    FeedFetchException(
      FeedFetchErrorKind.httpStatus,
      'status $status',
      retryAfter: retryAfter,
      statusCode: status,
    );

void main() {
  final now = DateTime.now();

  test('a 429 on one feed cools its whole host, not other hosts', () {
    final b = FeedBackoff();
    b.recordFailure('https://reddit.com/r/a/.rss', rateLimit(), now);

    expect(b.isBackedOff('https://reddit.com/r/a/.rss', now), isTrue);
    // Sibling subreddit on the same authority is protected too.
    expect(b.isBackedOff('https://reddit.com/r/b/.rss', now), isTrue);
    // A different authority is unaffected.
    expect(b.isBackedOff('https://example.com/f.xml', now), isFalse);
  });

  test('a feed-specific failure does not cool sibling feeds', () {
    final b = FeedBackoff();
    b.recordFailure(
      'https://x.com/a.xml',
      FeedFetchException(FeedFetchErrorKind.gone, '404', statusCode: 404),
      now,
    );

    expect(b.isBackedOff('https://x.com/b.xml', now), isFalse);
  });

  test('a sibling success clears the shared host cooldown', () {
    final b = FeedBackoff();
    b.recordFailure('https://x.com/a.xml', rateLimit(), now);
    expect(b.isBackedOff('https://x.com/b.xml', now), isTrue);

    // A 200 from the same origin proves the limit lifted — siblings are
    // fetchable again. The failed feed keeps its own entry: its 429 was
    // feed-specific evidence the sibling's success can't erase.
    b.recordSuccess('https://x.com/b.xml');
    expect(b.isBackedOff('https://x.com/b.xml', now), isFalse);
    expect(b.isBackedOff('https://x.com/a.xml', now), isTrue);
  });

  test('snapshot round-trips host and feed cooldowns', () {
    final b = FeedBackoff();
    b.recordFailure(
      'https://x.com/a.xml',
      rateLimit(retryAfter: now.add(const Duration(minutes: 10))),
      now,
    );

    final restored = FeedBackoff()..load(b.snapshot());
    expect(restored.isBackedOff('https://x.com/a.xml', now), isTrue);
    expect(restored.isBackedOff('https://x.com/b.xml', now), isTrue);
  });

  test('legacy flat snapshots still load as feed cooldowns', () {
    final b = FeedBackoff()
      ..load({
        'https://x.com/a.xml': now
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      });
    expect(b.isBackedOff('https://x.com/a.xml', now), isTrue);
    // Legacy snapshots carry no host data — siblings stay fetchable.
    expect(b.isBackedOff('https://x.com/b.xml', now), isFalse);
  });

  test('load merges later deadlines, never shortens them', () {
    final b = FeedBackoff();
    b.recordFailure(
      'https://x.com/a.xml',
      rateLimit(retryAfter: now.add(const Duration(minutes: 60))),
      now,
    );
    // A stale shorter persisted deadline must not shrink the local one.
    b.load({
      'feeds': {
        'https://x.com/a.xml': now
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      },
      'hosts': <String, int>{},
    });
    expect(
      b.isBackedOff(
        'https://x.com/a.xml',
        now.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
  });

  test(
    'a persisted deadline older than a cleared success is not resurrected',
    () {
      final b = FeedBackoff();
      // Simulate: host cooled at T, then a success at T+1m cleared it.
      b.recordSuccess('https://x.com/a.xml');
      b.load({
        'hosts': {'x.com': now.millisecondsSinceEpoch - 1000},
        'feeds': <String, int>{},
      });
      expect(b.isBackedOff('https://x.com/b.xml', now), isFalse);
    },
  );
}
