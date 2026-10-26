import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/services/app_reset_service.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/lifecycle_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app-reset-recovery-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  LifecycleCoordinator gate() =>
      LifecycleCoordinator(directory: Directory('${root.path}/lifecycle'));

  Future<MediaEntry> seed() async {
    await Hive.box('bookmarks').put('bookmarkedItemIds', ['a']);
    await Hive.box('feeds').put('subscriptions', '[]');
    await Hive.box('feeds').put('cachedItemsJson', '[]');
    await Hive.box('settings').put('notificationsEnabled', false);
    await ArticleRecordStore.forBox(
      Hive.box('feeds'),
    ).write(ArticleRecord(id: 'a', feedUrl: 'f', owners: {'bookmark'}));
    return ArticleMediaStore().put('https://i.test/a.png', [1, 2, 3]);
  }

  Future<void> expectWiped(MediaEntry media) async {
    expect(Hive.box('bookmarks').isEmpty, isTrue);
    expect(Hive.box('settings').isEmpty, isTrue);
    expect(Hive.box('feeds').get('cachedItemsJson'), isNull);
    expect(Hive.box('feeds').get('subscriptions'), isNull);
    expect(
      await ArticleRecordStore.forBox(Hive.box('feeds')).listRecords(),
      isEmpty,
    );
    expect(await ArticleMediaStore().verify(media), isFalse);
  }

  test('reset interrupted after its first stage finishes at restart', () async {
    final media = await seed();
    final interrupted = gate();
    final stages = AppResetService.appStages(
      feedStorage: AppResetService.wipeFeedStorage,
    );
    final reset = await interrupted.beginReset(
      cleanupStages: [for (final (name, _) in stages) name],
    );
    final (first, action) = stages.first;
    await interrupted.performCleanupStage(reset, first, action);
    // "Crash": nothing else runs. New work is refused meanwhile.
    await expectLater(
      interrupted.beginWork(),
      throwsA(isA<LifecycleResetPending>()),
    );

    final restarted = gate();
    await AppResetService.recover(restarted);
    await expectWiped(media);
    final state = await restarted.initialize();
    expect(state.resetPending, isFalse);
    expect(state.completedCleanupStages, AppResetService.allStages);
    await restarted.beginWork();
  });

  test('a new reset first completes a pending one, then runs', () async {
    final media = await seed();
    final current = gate();
    await current.beginReset(cleanupStages: AppResetService.allStages);
    final ok = await AppResetService.run(
      current,
      AppResetService.appStages(feedStorage: AppResetService.wipeFeedStorage),
    );
    expect(ok, isTrue);
    await expectWiped(media);
    expect((await current.initialize()).resetSequence, 2);
  });
}
