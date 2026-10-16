import '../models/feed_item.dart';

/// Tuple holding the three date-based groups computed in a single pass.
class FeedDateGroups {
  final List<FeedItem> today;
  final List<FeedItem> yesterday;
  final List<FeedItem> older;

  const FeedDateGroups(this.today, this.yesterday, this.older);
}

/// Tolerance for small clock skew between publisher and device.
///
/// A `pubDate` up to this far ahead of [now] is treated as genuinely
/// current; beyond it the timestamp is implausibly future-dated
/// (mislabeled timezone, broken CMS clock, scheduled post) and is clamped
/// to [now] for ordering/grouping purposes.
const kFuturePubDateAllowance = Duration(minutes: 30);

/// Effective instant for chronological ordering and calendar grouping.
///
/// Implausibly future-dated timestamps are clamped to [now] so a broken or
/// mislabeled feed cannot pin itself above every newer article. The
/// original [FeedItem.pubDate] is never mutated — display still shows the
/// source value, identity and cache stay stable.
DateTime effectivePublicationDate(
  DateTime pubDate,
  DateTime now, {
  Duration allowance = kFuturePubDateAllowance,
}) {
  return pubDate.isAfter(now.add(allowance)) ? now : pubDate;
}

/// Sorts [items] newest-first by effective publication date, in place.
///
/// Null dates sink to the bottom; equal effective dates (and equal nulls)
/// tie-break on [FeedItem.id] so ordering is stable across refreshes.
/// The allowance deadline is hoisted out of the comparator — sorting 10k
/// items performs ~140k comparisons, so per-comparison `now.add()` churn
/// is worth avoiding.
void sortByEffectivePubDateDesc(
  List<FeedItem> items,
  DateTime now, {
  Duration allowance = kFuturePubDateAllowance,
}) {
  final deadline = now.add(allowance);
  items.sort((a, b) {
    final ap = a.pubDate;
    final bp = b.pubDate;
    if (ap == null && bp == null) return a.id.compareTo(b.id);
    if (ap == null) return 1;
    if (bp == null) return -1;
    final ad = ap.isAfter(deadline) ? now : ap;
    final bd = bp.isAfter(deadline) ? now : bp;
    final c = bd.compareTo(ad);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
}

/// Groups [items] into Today / Yesterday / Older buckets relative to [now].
/// Items with no publication date land in `older`.
///
/// `pubDate` instants are normalized UTC; calendar-day boundaries are local
/// — each date is converted with `toLocal()` before comparing year/month/day
/// so articles near midnight land in the correct bucket.
FeedDateGroups groupFeedItemsByDate(Iterable<FeedItem> items, DateTime now) {
  final localNow = now.toLocal();
  final yesterday = localNow.subtract(const Duration(days: 1));
  final today = <FeedItem>[];
  final yester = <FeedItem>[];
  final older = <FeedItem>[];

  for (final item in items) {
    final raw = item.pubDate;
    final d = raw == null
        ? null
        : effectivePublicationDate(raw, now).toLocal();
    if (d != null &&
        d.year == localNow.year &&
        d.month == localNow.month &&
        d.day == localNow.day) {
      today.add(item);
    } else if (d != null &&
        d.year == yesterday.year &&
        d.month == yesterday.month &&
        d.day == yesterday.day) {
      yester.add(item);
    } else {
      older.add(item);
    }
  }

  return FeedDateGroups(today, yester, older);
}
