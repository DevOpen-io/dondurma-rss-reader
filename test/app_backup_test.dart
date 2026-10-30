import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:ice_cream_rss_reader/services/app_backup.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

FeedItem _article(String id, String feedUrl) => FeedItem(
  id: id,
  siteName: 'Site',
  title: 'Title $id',
  description: 'Summary $id',
  content: '<p>Body $id</p>',
  link: 'https://site.test/$id',
  feedUrl: feedUrl,
  category: 'Tech',
  pubDate: DateTime.utc(2026, 10, 20),
);

typedef _App = ({
  SettingsProvider settings,
  SubscriptionProvider subscriptions,
  BookmarkProvider bookmarks,
  FeedProvider feed,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    root = await Directory.systemTemp.createTemp('app-backup-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<_App> start() async {
    final feed = FeedProvider();
    await feed.refreshAll(); // Startup only: no subscriptions provider.
    return (
      settings: SettingsProvider(),
      subscriptions: SubscriptionProvider(),
      bookmarks: BookmarkProvider(),
      feed: feed,
    );
  }

  Future<void> wipe(_App app, {bool clear = true}) async {
    app.feed.dispose();
    app.bookmarks.dispose();
    await app.feed.idle;
    if (!clear) return;
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.box(name).clear();
    }
  }

  Future<RestoreSummary> restore(_App app, String json) => restoreAppBackup(
    json,
    settings: app.settings,
    subscriptions: app.subscriptions,
    bookmarks: app.bookmarks,
    feed: app.feed,
  );

  test('export, factory reset, restore brings everything back', () async {
    final first = await start();
    await first.subscriptions.addCategory('Empty');
    await first.subscriptions.importFeeds([
      FeedSubscription(
        url: 'https://a.test/feed',
        name: 'A',
        category: 'Tech',
        fullTextEnabled: true,
        excludedKeywords: const ['crypto'],
        speechLanguage: 'tr',
      ),
      FeedSubscription(url: 'https://b.test/feed', name: 'B', category: 'Tech'),
    ]);
    await first.subscriptions.setCategoryEmoji('Tech', '🧪');
    await first.settings.setFontSize('large');
    await first.settings.setMarkReadOnScroll(true);
    await first.settings.setLineSpacing(2.0);
    await first.settings.setGlobalExcludedKeywords(['sponsored']);
    first.bookmarks.toggleBookmark(_article('saved', 'https://a.test/feed'));
    first.feed.restoreReadRefs({('https://b.test/feed', 'seen')});
    await first.subscriptions.addCategory('Later');
    final folders = first.subscriptions.folderBackup;
    final epochs = {
      for (final s in first.subscriptions.subscriptions)
        s.url: s.notificationEpoch,
    };
    final settingsBefore = first.settings.backupValues();

    final json = exportAppBackup(
      settings: first.settings,
      subscriptions: first.subscriptions,
      bookmarks: first.bookmarks,
      feed: first.feed,
    );
    await wipe(first);

    final second = await start();
    final summary = await restore(second, json);

    expect(summary, (feeds: 2, bookmarks: 1));
    final subs = second.subscriptions.subscriptions;
    expect(
      [for (final s in subs) s.url],
      ['https://a.test/feed', 'https://b.test/feed'],
    );
    expect(subs.first.fullTextEnabled, isTrue);
    expect(subs.first.excludedKeywords, ['crypto']);
    expect(subs.first.speechLanguage, 'tr');
    expect(subs.last.speechLanguage, isNull);
    expect(second.subscriptions.categoriesOrdered, contains('Empty'));
    expect(
      second.subscriptions.folderBackup.icons['Tech'],
      folders.icons['Tech'],
    );
    expect(second.settings.fontSize, 'large');
    expect(second.settings.markReadOnScroll, isTrue);
    expect(second.settings.lineSpacing, 2.0);
    expect(second.settings.globalExcludedKeywords, ['sponsored']);
    expect(
      [for (final b in second.bookmarks.bookmarkedItems) (b.feedUrl, b.id)],
      [('https://a.test/feed', 'saved')],
    );
    expect(
      second.bookmarks.bookmarkedItems.single.content,
      '<p>Body saved</p>',
    );
    expect(second.feed.isRead(_article('seen', 'https://b.test/feed')), isTrue);
    expect(second.settings.backupValues(), settingsBefore);
    for (final sub in subs) {
      expect(
        sub.notificationEpoch,
        isNot(epochs[sub.url]),
        reason: 'a restored feed starts a new, silent notification history',
      );
    }
    expect(second.subscriptions.folderBackup.order, folders.order);
    await wipe(second, clear: false);

    // Everything was written to disk, not just to memory.
    final reopened = await start();
    expect(reopened.settings.fontSize, 'large');
    expect(reopened.subscriptions.subscriptions, hasLength(2));
    expect(reopened.bookmarks.bookmarkedItems, hasLength(1));
    expect(
      reopened.feed.isRead(_article('seen', 'https://b.test/feed')),
      isTrue,
    );
    await wipe(reopened);
  });

  test('settings are replaced, defaults included', () async {
    final source = await start();
    final json = exportAppBackup(
      settings: source.settings,
      subscriptions: source.subscriptions,
      bookmarks: source.bookmarks,
      feed: source.feed,
    );
    await source.settings.setFontSize('xl');
    await source.settings.setMarkReadOnScroll(true);

    await restore(source, json);

    expect(source.settings.fontSize, 'medium');
    expect(source.settings.markReadOnScroll, isFalse);
    await wipe(source);
  });

  test('background sync stays with a desktop device', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final app = await start();
    final json = jsonEncode({
      'format': AppBackup.format,
      'version': AppBackup.version,
      'settings': {'syncBackground': false, 'fontSize': 'small'},
    });

    await restore(app, json); // No background scheduler to call here.

    expect(app.settings.syncBackground, isTrue);
    expect(app.settings.fontSize, 'small');
    await wipe(app);
  });

  test('restored bookmarks get a durable record and no download', () async {
    final requests = <Uri>[];
    var extractions = 0;
    final records = ArticleRecordStore(
      FileObservedArticlePersistence(
        stateFile: File('${root.path}/archive.json'),
      ),
    );
    final prep = ArticlePreparationService(
      recordStore: records,
      mediaStore: ArticleMediaStore(root: Directory('${root.path}/media')),
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response('', 404);
      }),
      extractFullText: (_) async {
        extractions++;
        return null;
      },
      minHostGap: Duration.zero,
    );
    final app = await start();
    final bookmarks = BookmarkProvider(preparation: prep);
    final json = jsonEncode({
      'format': AppBackup.format,
      'version': AppBackup.version,
      'bookmarks': [
        for (final id in ['b1', 'b2', 'b1'])
          _article(id, 'https://a.test/feed').toJson(),
      ],
    });

    final summary = await restoreAppBackup(
      json,
      settings: app.settings,
      subscriptions: app.subscriptions,
      bookmarks: bookmarks,
      feed: app.feed,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(summary.bookmarks, 2, reason: 'a repeated entry is added once');
    final saved = await records.listRecords();
    expect({for (final r in saved) r.id}, {'b1', 'b2'});
    expect(saved.every((r) => r.owners.contains('bookmark')), isTrue);
    expect(requests, isEmpty);
    expect(extractions, 0);
    bookmarks.dispose();
    prep.dispose();
    await wipe(app);
  });

  test('restore merges: nothing already there is added twice', () async {
    final app = await start();
    await app.subscriptions.importFeeds([
      FeedSubscription(url: 'https://a.test/feed', name: 'A', category: 'X'),
    ]);
    app.bookmarks.toggleBookmark(_article('saved', 'https://a.test/feed'));
    final json = exportAppBackup(
      settings: app.settings,
      subscriptions: app.subscriptions,
      bookmarks: app.bookmarks,
      feed: app.feed,
    );

    final summary = await restore(app, json);

    expect(summary, (feeds: 0, bookmarks: 0));
    expect(app.subscriptions.subscriptions, hasLength(1));
    expect(app.bookmarks.bookmarkedItems, hasLength(1));
    await wipe(app);
  });

  test('settings with the wrong shape or unknown keys are skipped', () async {
    final app = await start();
    final json = jsonEncode({
      'format': AppBackup.format,
      'version': AppBackup.version,
      'settings': {
        'fontSize': 5,
        'typeface': 'serif',
        'hasSeenOnboarding': false,
        'somethingNew': 'x',
        'lineSpacing': 2,
        'timeFormat': '13h',
        'offlineCacheLimit': 99999,
      },
    });

    await restore(app, json);

    expect(app.settings.fontSize, 'medium');
    expect(app.settings.typeface, 'serif');
    expect(app.settings.lineSpacing, 2.0);
    expect(
      app.settings.timeFormat,
      'system',
      reason: 'not a value the app writes',
    );
    expect(app.settings.offlineCacheLimit, 50);
    expect(Hive.box('settings').get('hasSeenOnboarding'), isNull);
    expect(Hive.box('settings').get('somethingNew'), isNull);
    await wipe(app);
  });

  test('onboarding and migration markers are not exported', () async {
    final app = await start();
    await Hive.box('settings').put('hasSeenOnboarding', true);
    final decoded =
        jsonDecode(
              exportAppBackup(
                settings: app.settings,
                subscriptions: app.subscriptions,
                bookmarks: app.bookmarks,
                feed: app.feed,
              ),
            )
            as Map<String, dynamic>;
    expect(decoded['format'], AppBackup.format);
    expect(decoded['settings'], isNot(contains('hasSeenOnboarding')));
    await wipe(app);
  });

  group('a file that is not a usable backup changes nothing', () {
    for (final (name, text, reason) in [
      ('not JSON', 'hello', BackupProblem.notABackup),
      ('empty', '', BackupProblem.notABackup),
      ('another JSON', '{"version": 1}', BackupProblem.notABackup),
      ('an OPML file', '<opml version="2.0"></opml>', BackupProblem.notABackup),
      (
        'a newer backup',
        jsonEncode({'format': AppBackup.format, 'version': 99}),
        BackupProblem.tooNew,
      ),
      (
        'a broken subscription',
        jsonEncode({
          'format': AppBackup.format,
          'version': 1,
          'subscriptions': [
            {'name': 'no url'},
          ],
        }),
        BackupProblem.notABackup,
      ),
    ]) {
      test(name, () async {
        final app = await start();
        await app.settings.setFontSize('small');

        await expectLater(
          restore(app, text),
          throwsA(
            isA<BackupException>().having((e) => e.problem, 'problem', reason),
          ),
        );

        expect(app.settings.fontSize, 'small');
        expect(app.subscriptions.subscriptions, isEmpty);
        await wipe(app);
      });
    }
  });
}
