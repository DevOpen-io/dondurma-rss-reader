import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/services/app_backup.dart';

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

  Future<void> wipe(_App app) async {
    app.feed.dispose();
    app.bookmarks.dispose();
    await app.feed.idle;
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
    final folders = first.subscriptions.folderBackup;

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
    await wipe(second);
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
        'typeface': 'literata',
        'hasSeenOnboarding': false,
        'somethingNew': 'x',
        'lineSpacing': 2,
      },
    });

    await restore(app, json);

    expect(app.settings.fontSize, 'medium');
    expect(app.settings.typeface, 'literata');
    expect(app.settings.lineSpacing, 2.0);
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
