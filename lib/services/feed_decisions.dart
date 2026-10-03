import 'package:flutter/foundation.dart' show listEquals, setEquals;

/// Minimum gap between an app-resume refresh and the previous sync.
const Duration resumeRefreshThrottle = Duration(seconds: 60);

/// Pure comparison of the filter-relevant upstream inputs — extracted for
/// unit testing. Returns `true` when the filtered list must be recomputed:
/// no previous snapshot yet, or global keywords, per-feed keywords, or the
/// bookmark ID set differ.
bool feedFilterInputsChanged({
  required List<String>? prevGlobalKeywords,
  required List<String> nextGlobalKeywords,
  required Map<String, List<String>>? prevFeedKeywords,
  required Map<String, List<String>> nextFeedKeywords,
  required Set<String>? prevBookmarkIds,
  required Set<String> nextBookmarkIds,
}) {
  if (prevGlobalKeywords == null ||
      prevFeedKeywords == null ||
      prevBookmarkIds == null) {
    return true;
  }
  if (!listEquals(prevGlobalKeywords, nextGlobalKeywords)) return true;
  if (!setEquals(prevBookmarkIds, nextBookmarkIds)) return true;
  if (prevFeedKeywords.length != nextFeedKeywords.length) return true;
  for (final entry in nextFeedKeywords.entries) {
    final prev = prevFeedKeywords[entry.key];
    if (prev == null || !listEquals(prev, entry.value)) return true;
  }
  return false;
}

/// Pure decision for `maybeRefreshOnResume` — extracted for unit testing.
///
/// Returns `true` only when dependencies are wired, no sync is in flight, and
/// either no sync has happened yet or the last one is older than
/// [resumeRefreshThrottle].
bool feedShouldRefreshOnResume({
  required bool hasDependencies,
  required bool isSyncing,
  required DateTime? lastSyncTime,
  required DateTime now,
}) {
  if (!hasDependencies) return false;
  if (isSyncing) return false;
  if (lastSyncTime != null &&
      now.difference(lastSyncTime) < resumeRefreshThrottle) {
    return false;
  }
  return true;
}

/// Pure decision for the periodic sync timer — skip a tick when a sync
/// (manual, app-resume, or a previous tick) already completed within the last
/// [intervalSeconds], so off-cycle refreshes don't get doubled by the timer.
bool feedShouldRunPeriodicSync({
  required DateTime? lastSyncTime,
  required DateTime now,
  required int intervalSeconds,
}) {
  if (lastSyncTime == null) return true;
  return now.difference(lastSyncTime).inSeconds >= intervalSeconds;
}

/// Pure decision: does an item with [isRead]/[category] survive the runtime
/// filter? Read status and category set combine with AND; an empty
/// [categories] set imposes no category constraint.
bool feedPassesRuntimeFilter({
  required bool isRead,
  required String category,
  required String readFilter,
  required Set<String> categories,
}) {
  if (readFilter == 'unread' && isRead) return false;
  if (readFilter == 'read' && !isRead) return false;
  if (categories.isNotEmpty && !categories.contains(category)) return false;
  return true;
}
