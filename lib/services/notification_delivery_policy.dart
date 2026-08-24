import '../models/feed_item.dart';
import 'notification_service.dart';

class NotificationDeliveryPolicy {
  static List<FeedItem> eligibleItems({
    required Iterable<FeedItem> claimedItems,
    required bool notificationsEnabled,
    required String digestMode,
    required bool quietHoursEnabled,
    required int quietHoursStart,
    required int quietHoursEnd,
    required Set<String> mutedFeedUrls,
    DateTime? now,
  }) {
    if (!notificationsEnabled || digestMode != 'instant') return const [];
    final current = now ?? DateTime.now();
    if (quietHoursEnabled &&
        NotificationService.isInQuietHours(
          current.hour,
          quietHoursStart,
          quietHoursEnd,
        )) {
      return const [];
    }

    final cutoff = current.subtract(const Duration(hours: 48));
    final unique = <String, FeedItem>{};
    for (final item in claimedItems) {
      if (mutedFeedUrls.contains(item.feedUrl) ||
          item.pubDate == null ||
          !item.pubDate!.isAfter(cutoff)) {
        continue;
      }
      unique.putIfAbsent('${item.feedUrl}\u0000${item.id}', () => item);
    }
    return unique.values.toList();
  }
}
