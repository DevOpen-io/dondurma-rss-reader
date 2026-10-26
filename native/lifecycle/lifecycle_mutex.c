// Lifecycle publication mutex. Built for every native target by
// hook/build.dart (Dart build hooks); bound with @Native in
// lib/services/lifecycle_mutex.dart.
//
// POSIX (Linux, Android, macOS, iOS): flock(2) on a per-acquisition open file
// description. Windows: LockFileEx on a per-acquisition handle. Both conflict
// across processes AND between separate opens inside one process, so isolates
// and engines exclude each other; process death releases the lock.
#ifdef _WIN32
#define LIFECYCLE_EXPORT __declspec(dllexport)
#include <stdlib.h>
#include <windows.h>
#else
#define _GNU_SOURCE
#define LIFECYCLE_EXPORT __attribute__((visibility("default")))
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/file.h>
#include <unistd.h>
#endif

struct lifecycle_mutex {
#ifdef _WIN32
  HANDLE handle;
#else
  int fd;
#endif
};

LIFECYCLE_EXPORT int lifecycle_mutex_abi(void) { return 1; }
LIFECYCLE_EXPORT void *lifecycle_allocate(size_t size) { return malloc(size); }
LIFECYCLE_EXPORT void lifecycle_free(void *pointer) { free(pointer); }

#ifdef _WIN32
static wchar_t *lifecycle_wide(const char *path) {
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1,
                                   NULL, 0);
  if (length <= 0) return NULL;
  wchar_t *wide = malloc(sizeof(wchar_t) * (size_t)length);
  if (wide == NULL) return NULL;
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide,
                          length) != length) {
    free(wide);
    return NULL;
  }
  return wide;
}
#endif

// Never unlink this persistent lock file; replacing its inode would split
// the mutex.
LIFECYCLE_EXPORT void *lifecycle_mutex_open(const char *path) {
  struct lifecycle_mutex *mutex = malloc(sizeof(*mutex));
  if (mutex == NULL) return NULL;
#ifdef _WIN32
  wchar_t *wide = lifecycle_wide(path);
  if (wide == NULL) {
    free(mutex);
    return NULL;
  }
  // FILE_FLAG_OPEN_REPARSE_POINT: a planted link is opened itself, never
  // followed to a foreign file (the O_NOFOLLOW counterpart).
  mutex->handle = CreateFileW(
      wide, GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  free(wide);
  if (mutex->handle == INVALID_HANDLE_VALUE) {
    free(mutex);
    return NULL;
  }
#else
  mutex->fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (mutex->fd < 0) {
    free(mutex);
    return NULL;
  }
#endif
  return mutex;
}

// Nonblocking acquisition: Dart can yield instead of blocking its event loop.
// 1 acquired, 0 busy/interrupted, negative error code on an actual failure.
LIFECYCLE_EXPORT int lifecycle_mutex_try_lock(void *pointer) {
  struct lifecycle_mutex *mutex = pointer;
#ifdef _WIN32
  OVERLAPPED overlapped = {0};
  if (LockFileEx(mutex->handle,
                 LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0,
                 &overlapped)) {
    return 1;
  }
  DWORD error = GetLastError();
  if (error == ERROR_LOCK_VIOLATION || error == ERROR_IO_PENDING) return 0;
  return -(int)error;
#else
  if (flock(mutex->fd, LOCK_EX | LOCK_NB) == 0) return 1;
  int error = errno;
  if (error == EWOULDBLOCK || error == EAGAIN || error == EINTR) return 0;
  return -error;
#endif
}

// NativeFinalizer-compatible signature. Closing releases the kernel lock; no
// clock, owner-age estimate or removal of another owner's lock is involved.
LIFECYCLE_EXPORT void lifecycle_mutex_close(void *pointer) {
  struct lifecycle_mutex *mutex = pointer;
  if (mutex == NULL) return;
#ifdef _WIN32
  // Windows may release locks of a closed handle lazily; unlock first.
  OVERLAPPED overlapped = {0};
  UnlockFileEx(mutex->handle, 0, 1, 0, &overlapped);
  CloseHandle(mutex->handle);
#else
  close(mutex->fd);
#endif
  free(mutex);
}

// Make a journal rename durable in its containing directory. Windows has no
// directory fsync; NTFS journals the rename metadata itself.
LIFECYCLE_EXPORT int lifecycle_sync_directory(const char *path) {
#ifdef _WIN32
  (void)path;
  return 0;
#else
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (fd < 0) return -errno;
  int result;
  do {
    result = fsync(fd);
  } while (result < 0 && errno == EINTR);
  int error = result < 0 ? -errno : 0;
  close(fd);
  return error;
#endif
}
