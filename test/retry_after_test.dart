import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/utils/retry_after.dart';

/// `parseRetryAfter` is the single choke point every service feeds
/// server cooldowns through — capping it here protects feed refresh,
/// extraction, and media downloads from absurd mandates at once.
void main() {
  final now = DateTime.now().toUtc();

  test('ordinary delta seconds parse unchanged', () {
    expect(parseRetryAfter('60', now), now.add(const Duration(seconds: 60)));
    expect(parseRetryAfter('0', now), now);
  });

  test('an enormous delta clamps to the 24h cap — no overflow', () {
    // ~3 years in seconds: must clamp, never wrap Duration microseconds.
    expect(parseRetryAfter('99999999', now), now.add(maxRetryAfter));
    expect(parseRetryAfter('9223372036854775807', now), now.add(maxRetryAfter));
  });

  test('a far-future HTTP-date clamps to the cap', () {
    final header = HttpDate.format(now.add(const Duration(days: 400)));
    expect(parseRetryAfter(header, now), now.add(maxRetryAfter));
  });

  test('a near-future HTTP-date is honored as-is', () {
    final target = now.add(const Duration(minutes: 45));
    // HTTP-dates carry second precision — sub-second drift is inherent.
    final parsed = parseRetryAfter(HttpDate.format(target), now);
    expect(
      parsed!.difference(target).abs(),
      lessThan(const Duration(seconds: 1)),
    );
  });

  test('the cap is exactly one day', () {
    expect(maxRetryAfter, const Duration(hours: 24));
  });

  test('past dates, negatives, and garbage yield null', () {
    expect(parseRetryAfter('-5', now), isNull);
    expect(
      parseRetryAfter(
        HttpDate.format(now.subtract(const Duration(hours: 1))),
        now,
      ),
      isNull,
    );
    expect(parseRetryAfter('soon', now), isNull);
    expect(parseRetryAfter('', now), isNull);
    expect(parseRetryAfter(null, now), isNull);
  });
}
