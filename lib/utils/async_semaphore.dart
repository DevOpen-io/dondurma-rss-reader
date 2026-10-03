import 'dart:async';
import 'dart:collection';

/// Simple semaphore that gates access to at most [maxCount] concurrent slots.
///
/// Used to limit parallel HTTP requests so the device's connection pool and
/// memory aren't overwhelmed when many feeds are subscribed.
class AsyncSemaphore {
  final int maxCount;
  int _current = 0;
  final Queue<Completer<void>> _waitQueue = Queue();

  AsyncSemaphore(this.maxCount);

  Future<void> acquire() async {
    if (_current < maxCount) {
      _current++;
      return;
    }
    final c = Completer<void>();
    _waitQueue.add(c);
    await c.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeFirst().complete();
    } else {
      _current--;
    }
  }
}
