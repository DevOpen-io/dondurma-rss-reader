import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/utils/host_pacer.dart';

/// One [HostPacer] instance shared by feed refresh, article extraction,
/// and media downloads is what turns "same-host pacing" from per-service
/// politeness into a global schedule — these tests prove a shared
/// instance serializes callers that know nothing about each other.
void main() {
  test('two callers on one shared pacer serialize on the same host', () async {
    final pacer = HostPacer(minGap: const Duration(milliseconds: 60));
    final done = <String>[];
    final sw = Stopwatch()..start();

    // A "feed refresh" call and an "article extraction" call arrive
    // back-to-back — the second must not start before the gap elapses.
    final feedFetch = pacer
        .pace('http://h/a.xml')
        .then((_) => done.add('feed'));
    final articleFetch = pacer
        .pace('http://h/article/1')
        .then((_) => done.add('article'));

    await Future.wait([feedFetch, articleFetch]);
    expect(done, ['feed', 'article']);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(60));
  });

  test('a stricter reservation is not shortened by a lax caller', () async {
    final pacer = HostPacer(minGap: const Duration(milliseconds: 20));
    final sw = Stopwatch()..start();

    // The media downloader reserves a 150ms slot; a feed fetch with the
    // lax default gap must wait for the stricter reservation, not its own.
    await pacer.pace(
      'http://h/img.png',
      gap: const Duration(milliseconds: 150),
    );
    await pacer.pace('http://h/feed.xml');
    // Timer slack can fire a millisecond early — the threshold still
    // proves the strict 150ms reservation beat the lax 20ms default.
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(140));
  });

  test('different hosts never block each other', () async {
    final pacer = HostPacer(minGap: const Duration(milliseconds: 60));
    final sw = Stopwatch()..start();

    await Future.wait([
      pacer.pace('http://a/x'),
      pacer.pace('http://b/x'),
      pacer.pace('http://c/x'),
    ]);
    expect(sw.elapsedMilliseconds, lessThan(60));
  });
}
