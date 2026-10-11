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

  test('a sibling success cannot clear an active host cooldown', () {
    final b = FeedBackoff();
    // 429 WITHOUT Retry-After — even a locally estimated host cooldown
    // is origin-wide evidence: an in-flight sibling's 200 cannot remove
    // it before expiry.
    b.recordFailure('https://x.com/a.xml', rateLimit(), now);
    expect(b.isBackedOff('https://x.com/b.xml', now), isTrue);

    b.recordSuccess('https://x.com/b.xml');
    expect(b.isBackedOff('https://x.com/b.xml', now), isTrue);
    expect(b.isBackedOff('https://x.com/a.xml', now), isTrue);
  });

  test('equivalent host spellings share one cooldown (www vs apex, '
      'default vs explicit port)', () {
    final b = FeedBackoff();
    b.recordFailure('https://www.reddit.com/r/a/.rss', rateLimit(), now);
    // www.reddit.com ↔ reddit.com — the same rate limiter answers both.
    expect(b.isBackedOff('https://reddit.com/r/b/.rss', now), isTrue);
    expect(b.isBackedOff('https://www.reddit.com/r/c/.rss', now), isTrue);
    // Explicit default port is the same origin.
    expect(b.isBackedOff('https://www.reddit.com:443/r/d/.rss', now), isTrue);
    // A genuinely different host is unaffected.
    expect(b.isBackedOff('https://old.reddit.com/r/e/.rss', now), isFalse);
  });

  test('isMandatedBackedOff distinguishes server and local cooldowns', () {
    final b = FeedBackoff();
    b.recordFailure(
      'https://m.com/a.xml',
      rateLimit(retryAfter: now.add(const Duration(minutes: 10))),
      now,
    );
    b.recordFailure('https://l.com/a.xml', rateLimit(), now);

    expect(b.isMandatedBackedOff('https://m.com/b.xml', now), isTrue);
    expect(b.isMandatedBackedOff('https://l.com/b.xml', now), isFalse);
    // Both are still blocked for automatic passes.
    expect(b.isBackedOff('https://l.com/b.xml', now), isTrue);
  });

  test('a sibling success cannot cut a server-mandated host cooldown', () {
    final b = FeedBackoff();
    // Feed A got 429 + Retry-After: the server restricted the ORIGIN.
    final deadline = now.add(const Duration(minutes: 10));
    b.recordFailure(
      'https://reddit.com/r/a/.rss',
      rateLimit(retryAfter: deadline),
      now,
    );

    // Feed B was already in flight and completes successfully — the
    // server-issued host restriction still stands.
    b.recordSuccess('https://reddit.com/r/b/.rss');
    expect(b.isBackedOff('https://reddit.com/r/c/.rss', now), isTrue);
    // A's own feed record survives too — B's success says nothing about A.
    expect(b.isBackedOff('https://reddit.com/r/a/.rss', now), isTrue);

    // After the deadline the host is eligible again.
    expect(
      b.isBackedOff(
        'https://reddit.com/r/c/.rss',
        now.add(const Duration(minutes: 11)),
      ),
      isFalse,
    );
  });

  test('expired cooldowns stop blocking without any clear', () {
    final b = FeedBackoff();
    b.recordFailure(
      'https://x.com/a.xml',
      rateLimit(retryAfter: now.add(const Duration(minutes: 2))),
      now,
    );
    expect(
      b.isBackedOff('https://x.com/a.xml', now.add(const Duration(minutes: 3))),
      isFalse,
    );
  });

  test('later failures extend, never shorten, a feed deadline', () {
    final b = FeedBackoff();
    b.recordFailure(
      'https://x.com/a.xml',
      rateLimit(retryAfter: now.add(const Duration(minutes: 60))),
      now,
    );
    // A second failure with a *shorter* server wait must not shrink the
    // deadline already in place.
    b.recordFailure(
      'https://x.com/a.xml',
      rateLimit(retryAfter: now.add(const Duration(minutes: 5))),
      now.add(const Duration(minutes: 1)),
    );
    expect(
      b.isBackedOff(
        'https://x.com/a.xml',
        now.add(const Duration(minutes: 30)),
      ),
      isTrue,
    );
  });

  group('persistence ordering', () {
    test('failure → success → stale snapshot does not resurrect the '
        'cleared feed record', () {
      final b = FeedBackoff();
      // 10:00 — plain 429 → feed AND host records, since=10:00.
      b.recordFailure('https://x.com/a.xml', rateLimit(), now);
      // Snapshot written before the success carries the records.
      final stale = b.snapshot();
      // 10:06 — success clears the feed record; the host cooldown
      // stays (success never clears host cooldowns).
      final clearAt = now.add(const Duration(minutes: 6));
      b.recordSuccess('https://x.com/a.xml', at: clearAt);

      // 10:07 — the stale snapshot reloads: the feed record's
      // *creation* predates the clear → it must not come back.
      b.load(stale);
      final merged = b.snapshot();
      expect(
        (merged['feeds'] as Map).containsKey('https://x.com/a.xml'),
        isFalse,
      );
      // The host cooldown legitimately survives — that is policy, not
      // resurrection — and it is what still backs off the URL while
      // its (short, local) window lasts.
      expect((merged['hosts'] as Map).containsKey('x.com:443'), isTrue);
      expect(
        b.isBackedOff(
          'https://x.com/b.xml',
          now.add(const Duration(seconds: 30)),
        ),
        isTrue,
      );
    });

    test('a stale snapshot of a server-mandated record still cannot resurrect '
        'a cleared feed entry', () {
      final b = FeedBackoff();
      // Mandated failure — the exact shape of the reported race:
      // deadline (T+30m) outlives the clear (T+6m) on any naive
      // expiry-vs-clear comparison.
      b.recordFailure(
        'https://x.com/a.xml',
        rateLimit(retryAfter: now.add(const Duration(minutes: 30))),
        now,
      );
      final stale = b.snapshot();
      final clearAt = now.add(const Duration(minutes: 6));
      b.recordSuccess('https://x.com/a.xml', at: clearAt);
      b.load(stale);
      // Feed-level record stays cleared — creation predates the clear.
      // The HOST record legitimately survives (server mandate), which
      // is what still backs off the feed URL.
      expect(b.isBackedOff('https://x.com/a.xml', clearAt), isTrue);
      expect(b.isBackedOff('https://x.com/b.xml', clearAt), isTrue);
    });

    test('a genuinely new 429 outlives an older clear marker', () {
      final b = FeedBackoff();
      b.recordSuccess('https://x.com/a.xml', at: now);
      // A failure AFTER the clear creates since > cleared → it stands.
      b.recordFailure(
        'https://x.com/a.xml',
        rateLimit(),
        now.add(const Duration(minutes: 1)),
      );
      expect(
        b.isBackedOff(
          'https://x.com/a.xml',
          now.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });

    test('a clear learned from another isolate retires the feed record; '
        'the host cooldown still stands', () {
      final bg = FeedBackoff();
      bg.recordFailure('https://x.com/a.xml', rateLimit(), now);
      // Foreground succeeds and persists its clear.
      final fg = FeedBackoff();
      fg.recordSuccess(
        'https://x.com/a.xml',
        at: now.add(const Duration(minutes: 5)),
      );
      // Background loads the foreground slot → the superseded feed
      // record is dropped from memory AND from the next snapshot; the
      // host cooldown is origin policy and is untouched by success.
      bg.load(fg.snapshot());
      final merged = bg.snapshot();
      expect(
        (merged['feeds'] as Map).containsKey('https://x.com/a.xml'),
        isFalse,
      );
      // Host record survives the success — still within its window.
      expect((merged['hosts'] as Map).containsKey('x.com:443'), isTrue);
      expect(
        bg.isBackedOff(
          'https://x.com/b.xml',
          now.add(const Duration(seconds: 30)),
        ),
        isTrue,
      );
    });

    test(
      'concurrent writers converge: union of records, newest clears win',
      () {
        // fg learns a 429 on feed A; bg learns one on feed B — each
        // writes its own slot, then both merge the other's snapshot.
        final fg = FeedBackoff();
        final bg = FeedBackoff();
        fg.recordFailure('https://x.com/a.xml', rateLimit(), now);
        bg.recordFailure(
          'https://x.com/b.xml',
          rateLimit(retryAfter: now.add(const Duration(minutes: 20))),
          now,
        );
        final fgSnap = fg.snapshot();
        final bgSnap = bg.snapshot();
        fg.load(bgSnap);
        bg.load(fgSnap);
        for (final b in [fg, bg]) {
          expect(b.isBackedOff('https://x.com/a.xml', now), isTrue);
          expect(b.isBackedOff('https://x.com/b.xml', now), isTrue);
        }
      },
    );

    test('restart round-trips records AND clear markers', () {
      final first = FeedBackoff();
      // Local estimate on x.com — cleared by the later success.
      first.recordFailure('https://x.com/a.xml', rateLimit(), now);
      first.recordSuccess(
        'https://x.com/a.xml',
        at: now.add(const Duration(minutes: 5)),
      );
      // Server-mandated cooldown on y.com — survives the restart.
      first.recordFailure(
        'https://y.com/c.xml',
        rateLimit(retryAfter: now.add(const Duration(minutes: 9))),
        now,
      );

      final restarted = FeedBackoff()..load(first.snapshot());
      final t = now.add(const Duration(minutes: 6));
      // The cleared FEED record stays cleared — the marker round-tripped.
      final snap = restarted.snapshot();
      expect(
        (snap['feeds'] as Map).containsKey('https://x.com/a.xml'),
        isFalse,
      );
      // The host cooldown survived the success AND the restart — still
      // inside its local window it backs off every feed on the host.
      expect((snap['hosts'] as Map).containsKey('x.com:443'), isTrue);
      expect(
        restarted.isBackedOff(
          'https://x.com/b.xml',
          now.add(const Duration(seconds: 30)),
        ),
        isTrue,
      );
      // The still-active mandated cooldown on the other host survived
      // too — and its deadline reaches past t.
      expect(restarted.isBackedOff('https://y.com/c.xml', t), isTrue);
    });

    test('a server-mandated host cooldown survives both a sibling success '
        'and a restart', () {
      final first = FeedBackoff();
      first.recordFailure(
        'https://reddit.com/r/a/.rss',
        rateLimit(retryAfter: now.add(const Duration(minutes: 30))),
        now,
      );
      // Sibling success before the snapshot — mandate must persist.
      first.recordSuccess(
        'https://reddit.com/r/b/.rss',
        at: now.add(const Duration(minutes: 2)),
      );
      final restarted = FeedBackoff()..load(first.snapshot());
      final t = now.add(const Duration(minutes: 3));
      expect(restarted.isBackedOff('https://reddit.com/r/c/.rss', t), isTrue);
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

    test('legacy v2 snapshots load; a recorded clear supersedes them', () {
      // v2 carried no creation time, so a known clear wins over it —
      // without `since`, assuming stale is the only safe reading.
      final b = FeedBackoff();
      b.recordSuccess('https://x.com/a.xml', at: now);
      b.load({
        'feeds': {
          'https://x.com/a.xml': now
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'https://x.com/new.xml': now
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        },
        'hosts': <String, int>{},
      });
      expect(b.isBackedOff('https://x.com/a.xml', now), isFalse);
      // Untouched keys still load normally.
      expect(b.isBackedOff('https://x.com/new.xml', now), isTrue);
    });

    test('snapshot drops expired records so state stays bounded', () {
      var t = now;
      final b = FeedBackoff(now: () => t);
      b.recordFailure(
        'https://x.com/a.xml',
        rateLimit(retryAfter: t.add(const Duration(minutes: 1))),
        t,
      );
      t = t.add(const Duration(minutes: 5)); // cooldown expired
      final snap = b.snapshot();
      expect(snap['feeds'], isEmpty);
      expect(snap['hosts'], isEmpty);
    });
  });
}
