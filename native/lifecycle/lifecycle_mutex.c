// Phase-1 Linux backend. Not linked into the application yet.
// Build: cc -shared -fPIC -Wall -Wextra -Werror -o liblifecycle_mutex.so lifecycle_mutex.c
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/file.h>
#include <unistd.h>

struct lifecycle_mutex { int fd; };

int lifecycle_mutex_abi(void) { return 1; }
void *lifecycle_allocate(size_t size) { return malloc(size); }
void lifecycle_free(void *pointer) { free(pointer); }

// Separate opens have separate open-file descriptions: flock excludes other
// isolates/engines in this process as well as other processes. Never unlink
// this persistent lock file; replacing its inode would split the mutex.
void *lifecycle_mutex_open(const char *path) {
  int fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0) return NULL;
  struct lifecycle_mutex *mutex = malloc(sizeof(*mutex));
  if (mutex == NULL) { close(fd); return NULL; }
  mutex->fd = fd;
  return mutex;
}

// Nonblocking acquisition: Dart can yield instead of blocking its event loop.
// 1 acquired, 0 busy/interrupted, negative errno on an actual failure.
int lifecycle_mutex_try_lock(void *pointer) {
  struct lifecycle_mutex *mutex = pointer;
  if (flock(mutex->fd, LOCK_EX | LOCK_NB) == 0) return 1;
  int error = errno;
  if (error == EWOULDBLOCK || error == EAGAIN || error == EINTR) return 0;
  return -error;
}

// NativeFinalizer-compatible signature. close releases the kernel lock; no
// clock, owner-age estimate or removal of another owner's lock is involved.
void lifecycle_mutex_close(void *pointer) {
  struct lifecycle_mutex *mutex = pointer;
  if (mutex == NULL) return;
  close(mutex->fd);
  free(mutex);
}

// Make a journal rename durable in its containing directory on Linux.
int lifecycle_sync_directory(const char *path) {
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (fd < 0) return -errno;
  int result;
  do { result = fsync(fd); } while (result < 0 && errno == EINTR);
  int error = result < 0 ? -errno : 0;
  close(fd);
  return error;
}
