import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/feed_subscription.dart';

/// When each feed was last fetched, for per-feed refresh intervals (#68).
///
/// Persisted like [FeedBackoff]: the foreground isolate writes
/// [foregroundSlot], the background isolate [backgroundSlot], and every
/// reader merges both (the latest fetch wins) — neither isolate can
/// overwrite the other's record.
class FeedSchedule {
  static const foregroundSlot = 'feedFetchedAt';
  static const backgroundSlot = 'feedFetchedAt.bg';

  /// A timer tick or a background run landing just short of the interval
  /// still counts, instead of waiting for the next one.
  static const _slack = Duration(minutes: 2);

  final Map<String, DateTime> _fetched = {};

  /// Whether an automatic refresh should fetch [sub] at [now]: always for
  /// a feed without its own interval or never fetched.
  bool isDue(FeedSubscription sub, DateTime now) {
    final minutes = sub.refreshIntervalMinutes;
    if (minutes == null) return true;
    final last = _fetched[sub.url];
    // A stamp from the future (the clock was moved back) proves nothing.
    return last == null ||
        last.isAfter(now) ||
        !now.isBefore(last.add(Duration(minutes: minutes) - _slack));
  }

  /// Forgets every fetch — a factory reset.
  void reset() => _fetched.clear();

  void recordFetch(String url, DateTime at) {
    final last = _fetched[url];
    if (last == null || at.isAfter(last)) _fetched[url] = at;
  }

  /// Merges both persisted slots of [box]; a malformed slot is skipped.
  void loadSlots(Box box) {
    for (final key in const [foregroundSlot, backgroundSlot]) {
      try {
        final raw = box.get(key);
        if (raw is! String || raw.isEmpty) continue;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final MapEntry(:key, :value) in decoded.entries) {
          recordFetch(key, DateTime.fromMillisecondsSinceEpoch(value as int));
        }
      } catch (_) {
        // One malformed slot must not forfeit the other.
      }
    }
  }

  /// Merges the other isolate's slot first, then writes this isolate's
  /// [slot] with the feeds in [subscribed] only.
  Future<void> saveSlot(Box box, String slot, Iterable<String> subscribed) {
    loadSlots(box);
    final keep = subscribed.toSet();
    _fetched.removeWhere((url, _) => !keep.contains(url));
    return box.put(
      slot,
      jsonEncode({
        for (final MapEntry(:key, :value) in _fetched.entries)
          key: value.millisecondsSinceEpoch,
      }),
    );
  }
}
