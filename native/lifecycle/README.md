# Lifecycle mutex — phase 1

This is a narrowly scoped **Linux/local-filesystem** backend for
`lib/services/lifecycle_coordinator.dart`. It is **not packaged into Flutter
runners and not connected to application data writers**. Other platforms fail
closed in the Dart binding. No Dart package dependency is added.

## Build and tests

```sh
cc -shared -fPIC -Wall -Wextra -Werror \
  -o /tmp/liblifecycle_mutex.so native/lifecycle/lifecycle_mutex.c
flutter test test/lifecycle_coordinator_test.dart
```

The tests build their own temporary library, require `cc` and `dart` on PATH,
and launch both actual Dart isolates and fresh Dart processes. Do not check in
compiled binaries. Android/iOS/macOS/Windows packaging and platform backends
are future work; Linux test results are not evidence for those platforms.

## Why a native shim?

Linux `flock(2)` associates locks with **open-file descriptions**. Separate
`open()` calls conflict even within one process. This differs from the
process-level POSIX locks documented for Dart `RandomAccessFile.lock()`.
Every acquisition opens its own descriptor. `LOCK_NB` lets Dart yield while
waiting; timeout aborts the waiter, never steals the owner. `O_CLOEXEC`
prevents accidental descriptor inheritance across exec. The mutex inode is
permanent: **never unlink or replace `publication.lock`**.

Normal release closes the descriptor in an awaited `finally`. Process death
closes it in the kernel. A C `void(void*)` destructor is also attached through
`NativeFinalizer`; it closes the handle if a Dart owner becomes unreachable.
Individual-isolate finalizer latency is not bounded by the SDK (the guarantee
is by isolate-group shutdown). A stalled handle therefore causes a timeout,
not concurrent entry. Phase 2 must preserve this fail-closed behavior; do not
add age-based orphan recovery. Separate-engine behavior follows the native
open-description model, but an actual multi-engine Flutter test is still
required.

Assumptions: trusted application-private storage; all participating writers
cooperate; a local Linux filesystem with `flock`, atomic same-directory rename
and directory `fsync` semantics. Network filesystems, external lock-inode
replacement, arbitrary journal rollback, malicious same-user processes, and
hardware power-loss fault injection have not been validated.

## Journal boundary

`lifecycle.json` stores schema version, storage incarnation, reset epoch and
sequence, reset ID, pending state, required stages and acknowledged stages.
`initialized` detects loss of a previously acknowledged journal. Bootstrap
creates these files only; it never deletes legacy article/Hive/media data.
Staged journal files are flushed, atomically renamed, and the containing
directory is synced. New directory entries are synced in their parents too.
Uncommitted `.tmp-*` files from process death are ignored, not adopted as state;
bounded orphan housekeeping can be added later under the same mutex.

Cleanup acknowledgement is **at least once**, not exactly once. If an action
finishes and the process exits before its journal acknowledgement, recovery
replays it. Supply idempotent callbacks. Corrupt, foreign, inconsistent or lost
acknowledged journals fail closed; no fallback to an empty/default journal.

All coordinator APIs acquire the same mutex. Nested coordinator calls in a
publication/cleanup callback are rejected, even through another instance or
root, to prevent self-deadlock/ABBA. Await every side effect before returning
from a callback. Never start HTTP, extraction or a fire-and-forget write there.

## Phase-2 caller contract

Capture `beginWork()` **before** reading operation inputs or starting HTTP.
Carry the same immutable ticket through queues and callbacks. Acquiring a new
ticket after an old response arrives does not authorize that response.
`withPublication(ticket, action)` checks authorization while holding the mutex
and holds it until the action completes. Tickets are fencing tokens, not secret
security credentials.

`beginReset(cleanupStages: ...)` invalidates old tickets and durably closes the
gate. `performCleanupStage` executes/acknowledges stages in the recorded order;
`completeReset` refuses incomplete cleanup and rotates the epoch, so tickets
observed while pending (the reset handle's included) are stale afterwards.
`recoverPendingReset` requires a handler for every recorded stage (extra
handlers are ignored, so keep legacy names after a rename) and skips already
acknowledged stages. These are
reusable state-machine interfaces, **not factory-reset integration or automatic
startup recovery**. The five existing reset-publication acceptance tests must
remain red until production integrations are separately implemented.
