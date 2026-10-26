@DefaultAsset('package:ice_cream_rss_reader/services/lifecycle_mutex.dart')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

// Compiled for every native target by hook/build.dart. There is no fallback
// to expiring leases or process-scoped Dart file locks.
@Native<Int32 Function()>(symbol: 'lifecycle_mutex_abi')
external int _abi();

@Native<Pointer<Void> Function(IntPtr)>(symbol: 'lifecycle_allocate')
external Pointer<Void> _allocate(int size);

@Native<Void Function(Pointer<Void>)>(symbol: 'lifecycle_free')
external void _free(Pointer<Void> pointer);

@Native<Pointer<Void> Function(Pointer<Uint8>)>(symbol: 'lifecycle_mutex_open')
external Pointer<Void> _open(Pointer<Uint8> path);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'lifecycle_mutex_try_lock')
external int _tryLock(Pointer<Void> mutex);

@Native<Void Function(Pointer<Void>)>(symbol: 'lifecycle_mutex_close')
external void _close(Pointer<Void> mutex);

@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'lifecycle_sync_directory')
external int _syncDirectory(Pointer<Uint8> path);

final _finalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(_close).cast(),
);

/// Platform mutex backend: flock(2) on POSIX, LockFileEx on Windows.
/// Verified on Linux; other native targets compile the same source.
final class LifecycleMutexBindings {
  LifecycleMutexBindings() {
    if (_abi() != 1) throw StateError('Unsupported lifecycle mutex ABI');
  }

  T _withPath<T>(String path, T Function(Pointer<Uint8>) action) {
    if (path.contains('\u0000')) throw ArgumentError('NUL in lifecycle path');
    final bytes = utf8.encode(path);
    final pointer = _allocate(bytes.length + 1).cast<Uint8>();
    if (pointer == nullptr) throw StateError('Cannot allocate lifecycle path');
    try {
      pointer.asTypedList(bytes.length + 1)
        ..setAll(0, bytes)
        ..[bytes.length] = 0;
      return action(pointer);
    } finally {
      _free(pointer.cast());
    }
  }

  LifecycleMutexHandle open(String path) {
    final pointer = _withPath(path, _open);
    if (pointer == nullptr) {
      throw FileSystemException('Cannot open lifecycle mutex', path);
    }
    return LifecycleMutexHandle._(pointer);
  }

  void syncDirectory(String path) {
    final result = _withPath(path, _syncDirectory);
    if (result != 0) {
      throw FileSystemException(
        'Cannot sync lifecycle directory (errno ${-result})',
        path,
      );
    }
  }
}

/// Kept alive across the complete awaited critical section. Normal release is
/// deterministic; native finalization is a safety net, not a timed lease.
/// Finalization after individual isolate death has no bounded latency promise.
final class LifecycleMutexHandle implements Finalizable {
  LifecycleMutexHandle._(this._pointer) {
    _finalizer.attach(this, _pointer, detach: this);
  }
  Pointer<Void> _pointer;

  bool tryAcquire() {
    if (_pointer == nullptr) throw StateError('Lifecycle mutex already closed');
    final result = _tryLock(_pointer);
    if (result < 0) {
      throw FileSystemException('Lifecycle lock failed (error ${-result})');
    }
    return result == 1;
  }

  void close() {
    if (_pointer == nullptr) return;
    _finalizer.detach(this);
    _close(_pointer);
    _pointer = nullptr;
  }
}
