import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';

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

  test('read-aloud language: absent is automatic, kept by every copy', () {
    final sub = FeedSubscription(
      url: 'https://feed',
      name: 'Feed',
      category: 'News',
      speechLanguage: 'tr',
    );
    expect(FeedSubscription.fromJson(sub.toJson()).speechLanguage, 'tr');
    expect(sub.copyWith(name: 'x').speechLanguage, 'tr');
    expect(sub.copyWithFullTextMode(true).speechLanguage, 'tr');
    expect(sub.copyWithRefreshInterval(60).speechLanguage, 'tr');
    expect(sub.copyWithSpeechLanguage(null).speechLanguage, isNull);
    final legacy = FeedSubscription.fromJson({
      'url': 'https://feed',
      'name': 'Feed',
      'category': 'News',
    });
    expect(legacy.speechLanguage, isNull);
    expect(legacy.toJson(), isNot(contains('speechLanguage')));
    final corrupt = sub.toJson()..['speechLanguage'] = 42;
    expect(FeedSubscription.fromJson(corrupt).speechLanguage, isNull);
  });

  test('setSpeechLanguage stores the feed\'s reading language', () async {
    final dir = Directory.systemTemp.createTempSync('subscription_speech');
    Hive.init(dir.path);
    await Hive.openBox('feeds');
    addTearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });
    final subs = SubscriptionProvider();
    await subs.importFeeds([
      FeedSubscription(url: 'https://feed', name: 'Feed', category: 'News'),
    ]);
    await subs.setSpeechLanguage('https://feed', 'tr');
    expect(SubscriptionProvider().speechLanguageFor('https://feed'), 'tr');
    await subs.setSpeechLanguage('https://feed', null);
    expect(subs.speechLanguageFor('https://feed'), isNull);
    expect(subs.speechLanguageFor('https://unknown'), isNull);
  });

  test('effective full text: feed tri-state, null follows global', () async {
    final dir = Directory.systemTemp.createTempSync('subscription_ft');
    Hive.init(dir.path);
    await Hive.openBox('feeds');
    addTearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });
    await Hive.box('feeds').put(
      'subscriptions',
      jsonEncode([
        for (final (url, value) in [
          ('on', true),
          ('off', false),
          ('auto', null),
        ])
          FeedSubscription(
            url: url,
            name: url,
            category: 'News',
            fullTextEnabled: value,
          ).toJson(),
      ]),
    );
    final subs = SubscriptionProvider();
    for (final auto in [true, false]) {
      expect(subs.effectiveFullText('on', autoFullText: auto), isTrue);
      expect(subs.effectiveFullText('off', autoFullText: auto), isFalse);
      expect(subs.effectiveFullText('auto', autoFullText: auto), auto);
      expect(subs.effectiveFullText('unknown', autoFullText: auto), auto);
    }
  });

  test(
    'import skips canonical duplicates of existing and batch feeds',
    () async {
      final dir = Directory.systemTemp.createTempSync('subscription_import');
      Hive.init(dir.path);
      await Hive.openBox('feeds');
      addTearDown(() async {
        await Hive.close();
        dir.deleteSync(recursive: true);
      });
      await Hive.box('feeds').put(
        'subscriptions',
        jsonEncode([
          FeedSubscription(
            url: 'https://x.com/feed',
            name: 'X',
            category: 'News',
          ).toJson(),
        ]),
      );
      final subs = SubscriptionProvider();
      FeedSubscription feed(String url) =>
          FeedSubscription(url: url, name: url, category: 'News');

      final added = await subs.importFeeds([
        feed('HTTPS://X.com/feed/'),
        feed('https://y.com/rss'),
        feed('https://y.com/rss/'),
      ]);
      expect(added, 1);
      expect(subs.subscriptions.map((s) => s.url), [
        'https://x.com/feed',
        'https://y.com/rss',
      ]);

      await subs.addFeedsBatch([
        (url: 'https://y.com/rss', name: 'Y', category: 'News'),
        (url: 'https://z.com/rss', name: 'Z', category: 'News'),
        (url: 'https://z.com/rss/', name: 'Z', category: 'News'),
      ]);
      expect(subs.subscriptions.map((s) => s.url).last, 'https://z.com/rss');
      expect(subs.subscriptions, hasLength(3));
    },
  );
}
