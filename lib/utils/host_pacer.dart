/// Minimum spacing between requests to the same host.
///
/// A global concurrency cap is not enough: a burst of requests at one
/// origin (a feed plus its article images, or several subscriptions on
/// the same site) is exactly the pattern rate limiters punish — Reddit
/// answers 429 within seconds of a burst. Different hosts keep running
/// in parallel; only same-host requests serialize with a gap.
class HostPacer {
  HostPacer({this.minGap = const Duration(milliseconds: 500)});

  /// Minimum wall-clock spacing between two requests to one authority.
  final Duration minGap;

  final Map<String, DateTime> _idleAfter = {};
  final Map<String, Future<void>> _turn = {};

  /// Waits until [url]'s host is allowed another request, then reserves
  /// the next slot. Calls to the same host serialize FIFO; different
  /// hosts never block each other.
  Future<void> pace(String url) {
    final host = Uri.tryParse(url)?.authority ?? '';
    if (host.isEmpty || minGap == Duration.zero) {
      return Future<void>.value();
    }
    final turn = (_turn[host] ?? Future<void>.value()).then((_) async {
      final notBefore = _idleAfter[host];
      final now = DateTime.now();
      if (notBefore != null && notBefore.isAfter(now)) {
        await Future<void>.delayed(notBefore.difference(now));
      }
      _idleAfter[host] = DateTime.now().add(minGap);
    });
    _turn[host] = turn;
    return turn;
  }
}
