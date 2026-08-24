import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';

void main() {
  test('legacy subscription gets conservative shared migration epoch', () {
    final subscription = FeedSubscription.fromJson({
      'url': 'https://feed',
      'name': 'Feed',
      'category': 'News',
    });

    expect(subscription.notificationEpoch, 'legacy-v1');
    expect(subscription.toJson()['notificationEpoch'], 'legacy-v1');
  });

  test('new and resubscribed feeds receive different persisted epochs', () {
    final first = FeedSubscription(
      url: 'https://feed',
      name: 'Feed',
      category: 'News',
    );
    final second = FeedSubscription(
      url: 'https://feed',
      name: 'Feed',
      category: 'News',
    );

    expect(first.notificationEpoch, isNot(second.notificationEpoch));
    expect(first.toJson()['notificationEpoch'], first.notificationEpoch);
  });
}
