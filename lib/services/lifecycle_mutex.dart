import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// Linux-only phase-1 binding, deliberately requiring an explicit library.
/// No fallback to expiring leases or process-scoped Dart file locks exists.
final class LifecycleMutexBindings {
  LifecycleMutexBindings(String libraryPath) {
    if (!Platform.isLinux) {
      throw UnsupportedError(
        'Lifecycle mutex backend is verified on Linux only',
      );
    }
    final library = DynamicLibrary.open(libraryPath);
    final abi = library.lookupFunction<Int32 Function(), int Function()>(
      'lifecycle_mutex_abi',
    );
    if (abi() != 1) throw StateError('Unsupported lifecycle mutex ABI');
    _allocate = library
        .lookupFunction<
          Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)
        >('lifecycle_allocate');
    _free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('lifecycle_free');
    _open = library
        .lookupFunction<
          Pointer<Void> Function(Pointer<Uint8>),
          Pointer<Void> Function(Pointer<Uint8>)
        >('lifecycle_mutex_open');
    _tryLock = library
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('lifecycle_mutex_try_lock');
    final closeAddress = library
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'lifecycle_mutex_close',
        );
    _close = closeAddress.asFunction<void Function(Pointer<Void>)>();
    _finalizer = NativeFinalizer(closeAddress);
    _syncDirectory = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>),
          int Function(Pointer<Uint8>)
        >('lifecycle_sync_directory');
  }

  late final Pointer<Void> Function(int) _allocate;
  late final void Function(Pointer<Void>) _free;
  late final Pointer<Void> Function(Pointer<Uint8>) _open;
  late final int Function(Pointer<Void>) _tryLock;
  late final void Function(Pointer<Void>) _close;
  late final int Function(Pointer<Uint8>) _syncDirectory;
  late final NativeFinalizer _finalizer;

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
    return LifecycleMutexHandle._(this, pointer);
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
  LifecycleMutexHandle._(this._bindings, this._pointer) {
    _bindings._finalizer.attach(this, _pointer, detach: this);
  }
  final LifecycleMutexBindings _bindings;
  Pointer<Void> _pointer;

  bool tryAcquire() {
    if (_pointer == nullptr) throw StateError('Lifecycle mutex already closed');
    final result = _bindings._tryLock(_pointer);
    if (result < 0) {
      throw FileSystemException('Lifecycle flock failed (errno ${-result})');
    }
    return result == 1;
  }

  void close() {
    if (_pointer == nullptr) return;
    _bindings._finalizer.detach(this);
    _bindings._close(_pointer);
    _pointer = nullptr;
  }
}
