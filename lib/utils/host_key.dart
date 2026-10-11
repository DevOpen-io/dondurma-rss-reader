/// Canonical host key for rate-limit bookkeeping.
///
/// Spellings that resolve to the same origin must share one bucket:
/// `reddit.com` and `www.reddit.com` answer with the same rate limiter,
/// and `host` vs `host:80` on plain HTTP is the same origin too. The
/// key is the lowercased host minus a `www.` prefix plus the effective
/// port (scheme default when none is written).
String hostKey(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '';
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  final port = uri.hasPort
      ? uri.port
      : switch (uri.scheme) {
          'https' => 443,
          'http' => 80,
          _ => 0,
        };
  return port == 0 ? host : '$host:$port';
}
