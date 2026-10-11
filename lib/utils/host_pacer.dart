/// Minimum spacing between requests to the same host.
///
/// A global concurrency cap is not enough: a burst of requests at one
/// origin (a feed plus its article images, or several subscriptions on
/// the same site) is exactly the pattern rate limiters punish — Reddit
/// answers 429 within seconds of a burst. Different hosts keep running
/// in parallel; only same-host requests serialize with a gap.
///
/// Share ONE instance across every service that performs HTTP in an
/// isolate (feed refresh, article extraction, media downloads) so
/// same-host requests coordinate globally — separate instances would
/// let a feed fetch and an article fetch land in the same burst.
/// Foreground and background run in different isolates and therefore
/// cannot share the in-memory schedule; cross-isolate protection comes
/// from the persisted `FeedBackoff` host cooldowns.
class HostPacer {
  HostPacer({
    this.minGap = const Duration(milliseconds: 500),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Default spacing when a caller does not specify one — callers with
  /// stricter requirements pass their own gap to [pace].
  final Duration minGap;

  final DateTime Function() _now;
  final Map<String, DateTime> _idleAfter = {};
  final Map<String, Future<void>> _turn = {};

  /// Waits until [url]'s host is allowed another request, then reserves
  /// the next slot. [gap] overrides [minGap] for the spacing this call
  /// leaves behind — a caller needing more conservative spacing never
  /// shortens a stricter reservation already in place. Calls to the same
  /// host serialize FIFO; different hosts never block each other.
  Future<void> pace(String url, {Duration? gap}) {
    final host = Uri.tryParse(url)?.authority ?? '';
    final effective = gap ?? minGap;
    if (host.isEmpty || effective == Duration.zero) {
      return Future<void>.value();
    }
    final turn = (_turn[host] ?? Future<void>.value()).then((_) async {
      final notBefore = _idleAfter[host];
      final now = _now();
      if (notBefore != null && notBefore.isAfter(now)) {
        await Future<void>.delayed(notBefore.difference(now));
      }
      final slot = _now().add(effective);
      final existing = _idleAfter[host];
      _idleAfter[host] = existing != null && existing.isAfter(slot)
          ? existing
          : slot;
    });
    _turn[host] = turn;
    return turn;
  }
}
