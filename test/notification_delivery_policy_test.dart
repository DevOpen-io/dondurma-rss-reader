import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/notification_delivery_policy.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';
import 'package:ice_cream_rss_reader/services/observed_article_store.dart';
import 'dart:io';

FeedItem _item(String feed, String id, DateTime date) => FeedItem(
  id: id,
  siteName: feed,
  title: id,
  description: '',
  timeAgo: '',
  siteIcon: Icons.rss_feed,
  iconColor: Colors.blue,
  iconBackgroundColor: Colors.blueGrey,
  feedUrl: feed,
  pubDate: date,
);

void main() {
  test('suppressed claims stay observed and never backfill', () async {
    final directory = await Directory.systemTemp.createTemp('dondurma-policy-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ObservedArticleStore(
      FileObservedArticlePersistence(
        stateFile: File('${directory.path}/observed.json'),
      ),
    );
    final now = DateTime(2026, 8, 24, 12);
    const feed = 'https://feed';
    await store.claimFeedBatch(feedUrl: feed, items: const []);

    final cases =
        <({bool global, String digest, bool quiet, Set<String> muted})>[
          (global: false, digest: 'instant', quiet: false, muted: {}),
          (global: true, digest: 'daily', quiet: false, muted: {}),
          (global: true, digest: 'instant', quiet: true, muted: {}),
          (global: true, digest: 'instant', quiet: false, muted: {feed}),
        ];

    for (var index = 0; index < cases.length; index++) {
      final settings = cases[index];
      final article = _item(feed, 'suppressed-$index', now);
      final claim = await store.claimFeedBatch(feedUrl: feed, items: [article]);
      final eligible = NotificationDeliveryPolicy.eligibleItems(
        claimedItems: claim.claimedItems,
        notificationsEnabled: settings.global,
        digestMode: settings.digest,
        quietHoursEnabled: settings.quiet,
        quietHoursStart: 10,
        quietHoursEnd: 14,
        mutedFeedUrls: settings.muted,
        now: now,
      );
      expect(eligible, isEmpty);

      final afterRestore = await store.claimFeedBatch(
        feedUrl: feed,
        items: [article],
      );
      expect(afterRestore.claimedItems, isEmpty);
    }

    final later = _item(feed, 'later', now.add(const Duration(minutes: 1)));
    final laterClaim = await store.claimFeedBatch(
      feedUrl: feed,
      items: [later],
    );
    final eligibleLater = NotificationDeliveryPolicy.eligibleItems(
      claimedItems: laterClaim.claimedItems,
      notificationsEnabled: true,
      digestMode: 'instant',
      quietHoursEnabled: false,
      quietHoursStart: 0,
      quietHoursEnd: 0,
      mutedFeedUrls: const {},
      now: now,
    );
    expect(eligibleLater.map((item) => item.id), ['later']);
  });
}
