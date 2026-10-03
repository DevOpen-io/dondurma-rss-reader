import '../models/feed_item.dart';

/// Tuple holding the three date-based groups computed in a single pass.
class FeedDateGroups {
  final List<FeedItem> today;
  final List<FeedItem> yesterday;
  final List<FeedItem> older;

  const FeedDateGroups(this.today, this.yesterday, this.older);
}

/// Groups [items] into Today / Yesterday / Older buckets relative to [now].
/// Items with no publication date land in `older`.
FeedDateGroups groupFeedItemsByDate(Iterable<FeedItem> items, DateTime now) {
  final yesterday = now.subtract(const Duration(days: 1));
  final today = <FeedItem>[];
  final yester = <FeedItem>[];
  final older = <FeedItem>[];

  for (final item in items) {
    final d = item.pubDate;
    if (d != null &&
        d.year == now.year &&
        d.month == now.month &&
        d.day == now.day) {
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
