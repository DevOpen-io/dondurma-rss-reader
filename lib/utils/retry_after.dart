import 'dart:io' show HttpDate;

/// Parses a `Retry-After` header into an absolute instant — integer
/// seconds or an HTTP-date. Unparseable or past values yield null.
///
/// Shared by every service that honors server-issued cooldowns so the
/// seconds/HTTP-date semantics can't drift apart.
DateTime? parseRetryAfter(String? header, DateTime now) {
  if (header == null) return null;
  final seconds = int.tryParse(header.trim());
  if (seconds != null && seconds >= 0) {
    return now.add(Duration(seconds: seconds));
  }
  try {
    final date = HttpDate.parse(header);
    return date.isAfter(now) ? date : null;
  } catch (_) {
    return null;
  }
}
