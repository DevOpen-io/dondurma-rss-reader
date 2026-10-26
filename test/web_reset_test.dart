@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/services/app_reset_service.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/lifecycle_gate.dart';

void main() {
  setUp(() async {
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await (await Hive.openBox(name)).clear();
    }
  });
  tearDown(Hive.close);

  test(
    'web factory reset runs through the memory gate and wipes storage',
    () async {
      final feeds = Hive.box('feeds');
      final records = ArticleRecordStore.forBox(feeds);
      await records.write(
        ArticleRecord(id: 'a', feedUrl: 'https://a.test/feed', owners: {'x'}),
      );
      await Hive.box('bookmarks').put('bookmarkedItemIds', ['a']);
      await Hive.box('settings').put('notificationsEnabled', false);
      final gate = MemoryLifecycleGate();
      final stale = await gate.beginWork();

      final ok = await AppResetService.run(
        gate,
        AppResetService.appStages(feedStorage: AppResetService.wipeFeedStorage),
      );

      expect(ok, isTrue);
      expect(Hive.box('bookmarks').isEmpty, isTrue);
      expect(Hive.box('settings').isEmpty, isTrue);
      expect(
        await records.read(ArticleRef('https://a.test/feed', 'a')),
        isNull,
      );
      // Work begun before the reset can no longer publish.
      await expectLater(
        gate.withPublication(stale, () async {}),
        throwsA(isA<StaleLifecycleTicket>()),
      );
      await gate.beginWork();
    },
  );
}
