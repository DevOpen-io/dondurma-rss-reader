import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';

const _feed = 'https://a.test/feed';

FeedItem _item(String id, String title) => FeedItem(
  id: id,
  siteName: 'A',
  title: title,
  description: '',
  feedUrl: _feed,
  link: 'https://a.test/$id',
  pubDate: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      // Refresh ends by updating the home-screen widgets.
      MethodChannel('home_widget'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    root = await Directory.systemTemp.createTemp('read-rules-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
    await Hive.box('feeds').put(
      'subscriptions',
      jsonEncode([
        FeedSubscription(url: _feed, name: 'A', category: 'News').toJson(),
      ]),
    );
    await Hive.box('feeds').put(
      'cachedItemsJson',
      jsonEncode([
        _item('ad', '[AD] Buy this').toJson(),
        _item('flutter', 'Flutter 4 released').toJson(),
        _item('weather', 'Weather today').toJson(),
      ]),
    );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('mark-read rules mark matching articles; changing them applies at '
      'once; "only show" narrows the feed', () async {
    final settings = SettingsProvider();
    await settings.setGlobalReadKeywords([r'/^\[ad\]/']);
    final subs = SubscriptionProvider();
    final bookmarks = BookmarkProvider();
    final feed = FeedProvider(
      // Every refresh fails offline-free: cached articles stay.
      feedService: FeedService(
        client: MockClient((_) async => http.Response('', 404)),
      ),
    );
    feed.update(subs, settings, bookmarks);
    await feed.refreshAll();
    bool read(String id) => feed.isRead(_item(id, ''));

    expect(read('ad'), isTrue);
    expect(read('flutter'), isFalse);
    expect(read('weather'), isFalse);

    await settings.setGlobalReadKeywords([r'/^\[ad\]/', 'weather']);
    feed.update(subs, settings, bookmarks);
    expect(read('weather'), isTrue, reason: 'applied without a refresh');

    // Set back to unread by hand: no rule reads it again, not on the next
    // pass and not after a restart.
    await feed.toggleReadStatus(_item('ad', '').copyWith(isRead: true));
    expect(read('ad'), isFalse);
    await feed.refreshAll();
    expect(read('ad'), isFalse);

    await subs.editSubscription(_feed, _feed, 'A', onlyKeywords: ['flutter']);
    feed.update(subs, settings, bookmarks);
    expect([for (final i in feed.filteredItems) i.id], ['flutter']);

    feed.dispose();
  });
}
