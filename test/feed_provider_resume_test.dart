import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';

void main() {
  group('FeedProvider.shouldRefreshOnResume', () {
    final now = DateTime(2026, 6, 24, 12, 0, 0);

    test('no refresh when dependencies are not wired yet', () {
      expect(
        FeedProvider.shouldRefreshOnResume(
          hasDependencies: false,
          isSyncing: false,
          lastSyncTime: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('no refresh while a sync is already in flight', () {
      expect(
        FeedProvider.shouldRefreshOnResume(
          hasDependencies: true,
          isSyncing: true,
          lastSyncTime: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('refreshes when no sync has ever happened', () {
      expect(
        FeedProvider.shouldRefreshOnResume(
          hasDependencies: true,
          isSyncing: false,
          lastSyncTime: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('no refresh when last sync is within the throttle window', () {
      expect(
        FeedProvider.shouldRefreshOnResume(
          hasDependencies: true,
          isSyncing: false,
          lastSyncTime: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isFalse,
      );
    });

    test('refreshes when last sync is older than the throttle window', () {
      expect(
        FeedProvider.shouldRefreshOnResume(
          hasDependencies: true,
          isSyncing: false,
          lastSyncTime: now.subtract(const Duration(seconds: 90)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
