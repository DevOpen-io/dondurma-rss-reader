import 'dart:io' show HttpDate;

/// Longest server-issued wait this client honors: **24 hours**.
///
/// `Retry-After` is clamped to it — a misconfigured or hostile server
/// could otherwise ban an origin for months via one response, and the
/// mandate would persist into Hive and survive restarts. Trade-off: a
/// genuinely longer mandate is shortened to a day — acceptable, because
/// a rate limiter that locks clients out for >24h is indistinguishable
/// from a broken one, and a stale-day-old ban self-heals on the next
/// fetch instead of bricking the host for the app's lifetime.
///
/// Also guards `Duration` construction: parsing `seconds` before the
/// clamp keeps absurd integer literals from overflowing microseconds.
const maxRetryAfter = Duration(hours: 24);

/// Parses a `Retry-After` header into an absolute instant — integer
/// seconds or an HTTP-date, clamped to [maxRetryAfter] in the future.
/// Unparseable or past values yield null.
///
/// Shared by every service that honors server-issued cooldowns so the
/// seconds/HTTP-date semantics can't drift apart.
DateTime? parseRetryAfter(String? header, DateTime now) {
  if (header == null) return null;
  final cap = now.add(maxRetryAfter);
  final seconds = int.tryParse(header.trim());
  if (seconds != null) {
    if (seconds < 0) return null;
    // Compare before constructing the Duration — a huge literal would
    // overflow microseconds silently.
    return seconds >= maxRetryAfter.inSeconds
        ? cap
        : now.add(Duration(seconds: seconds));
  }
  try {
    final date = HttpDate.parse(header);
    if (!date.isAfter(now)) return null;
    return date.isAfter(cap) ? cap : date;
  } catch (_) {
    return null;
  }
}

/// 1→2→4→8… minute doubling, capped at 60 — the earliest next attempt, not
/// a guaranteed run time.
Duration retryBackoff(int attempts) {
  if (attempts < 1) return Duration.zero;
  final minutes = 1 << (attempts - 1).clamp(0, 6);
  return Duration(minutes: minutes > 60 ? 60 : minutes);
}
