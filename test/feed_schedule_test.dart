import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/services/feed_refresh.dart';
import 'package:ice_cream_rss_reader/services/feed_schedule.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';
import 'package:ice_cream_rss_reader/services/observed_article_store.dart';

const _rss =
    '<?xml version="1.0"?><rss version="2.0"><channel><title>T</title>'
    '<item><guid>1</guid><title>A</title><link>https://a.test/1</link></item>'
    '</channel></rss>';

FeedSubscription _sub(String url, {int? minutes}) => FeedSubscription(
  url: url,
  name: url,
  category: 'News',
  refreshIntervalMinutes: minutes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('feed-schedule-');
    Hive.init(root.path);
    await Hive.openBox('feeds');
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('a feed is due without an interval, once fetched only after it', () {
    final schedule = FeedSchedule();
    final now = DateTime(2026, 10, 29, 12);
    final hourly = _sub('https://a.test/feed', minutes: 60);
    expect(schedule.isDue(hourly, now), isTrue, reason: 'never fetched');
    expect(schedule.isDue(_sub('https://b.test/feed'), now), isTrue);

    schedule.recordFetch(hourly.url, now);
    expect(
      schedule.isDue(hourly, now.add(const Duration(minutes: 30))),
      isFalse,
    );
    expect(
      schedule.isDue(hourly, now.add(const Duration(minutes: 59))),
      isTrue,
      reason: 'a tick just short of the hour still counts',
    );
  });

  test(
    'each isolate writes its own slot and reads the latest of both',
    () async {
      final box = Hive.box('feeds');
      final early = DateTime(2026, 10, 29, 8);
      final late = DateTime(2026, 10, 29, 10);
      final foreground = FeedSchedule()
        ..recordFetch('https://a.test/feed', early);
      await foreground.saveSlot(box, FeedSchedule.foregroundSlot, [
        'https://a.test/feed',
      ]);
      final background = FeedSchedule()
        ..recordFetch('https://a.test/feed', late);
      await background.saveSlot(box, FeedSchedule.backgroundSlot, [
        'https://a.test/feed',
      ]);

      final reader = FeedSchedule()..loadSlots(box);
      final daily = _sub('https://a.test/feed', minutes: 24 * 60);
      expect(reader.isDue(daily, late.add(const Duration(hours: 23))), isFalse);
      expect(
        reader.isDue(daily, early.add(const Duration(hours: 25))),
        isFalse,
        reason: 'the later background fetch wins',
      );

      // A removed feed is dropped from the slot.
      await reader.saveSlot(box, FeedSchedule.foregroundSlot, const []);
      expect(box.get(FeedSchedule.foregroundSlot), '{}');
    },
  );

  test(
    'automatic passes skip a feed that is not due; a user pass fetches it',
    () async {
      final requests = <String>[];
      final refresher = FeedRefresher(
        feedService: FeedService(
          client: MockClient((request) async {
            requests.add(request.url.toString());
            return http.Response(
              _rss,
              200,
              headers: {'content-type': 'application/rss+xml'},
            );
          }),
        ),
        observedArticleStore: ObservedArticleStore(
          FileObservedArticlePersistence(
            stateFile: File('${root.path}/observed.json'),
          ),
        ),
        hostGap: Duration.zero,
      );
      final hourly = _sub('https://a.test/feed', minutes: 60);
      final plain = _sub('https://b.test/feed');
      Future<void> pass({required bool automatic}) => refresher.refresh(
        subscriptions: [hourly, plain],
        existingItems: const [],
        validators: const {},
        bookmarkedItems: const [],
        redirects: const {},
        honorIntervals: automatic,
      );

      await pass(automatic: true);
      expect(requests, ['https://a.test/feed', 'https://b.test/feed']);

      requests.clear();
      await pass(automatic: true);
      expect(requests, ['https://b.test/feed'], reason: 'hourly feed not due');

      requests.clear();
      await pass(automatic: false);
      expect(requests, ['https://a.test/feed', 'https://b.test/feed']);
    },
  );

  test('the interval survives JSON; bad values follow the app cycle', () {
    final sub = _sub('https://a.test/feed', minutes: 360);
    expect(FeedSubscription.fromJson(sub.toJson()).refreshIntervalMinutes, 360);
    expect(
      _sub('https://a.test/feed').toJson(),
      isNot(contains('refreshIntervalMinutes')),
    );
    final json = sub.toJson()..['refreshIntervalMinutes'] = -5;
    expect(FeedSubscription.fromJson(json).refreshIntervalMinutes, isNull);
    expect(sub.copyWithFullTextMode(true).refreshIntervalMinutes, 360);
    expect(sub.copyWith(name: 'x').refreshIntervalMinutes, 360);
  });
}
