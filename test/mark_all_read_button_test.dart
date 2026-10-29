import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/widgets/home/mark_all_read_button.dart';

FeedItem _item(String id, Duration age) => FeedItem(
  id: id,
  siteName: 'a',
  title: 'Title $id',
  description: '',
  feedUrl: 'https://a.test/feed',
  link: 'https://a.test/$id',
  pubDate: DateTime.now().subtract(age),
);

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
    root = await Directory.systemTemp.createTemp('mark-all-read-button-');
    Hive.init(root.path);
    for (final name in ['feeds', 'settings', 'bookmarks']) {
      await Hive.openBox(name);
    }
    await Hive.box('feeds').put(
      'cachedItemsJson',
      jsonEncode([
        _item('fresh', const Duration(hours: 1)).toJson(),
        _item('old', const Duration(days: 2)).toJson(),
      ]),
    );
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<FeedProvider> pumpButton(WidgetTester tester) async {
    late FeedProvider feed;
    await tester.runAsync(() async {
      feed = FeedProvider();
      await feed.refreshAll(); // Loads the cache; no subscriptions to fetch.
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: feed,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(actions: const [MarkAllReadButton()]),
          ),
        ),
      ),
    );
    return feed;
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<PopupMenuItem<Object?>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      )
      .enabled;

  testWidgets('older-than choice confirms its count and marks only those', (
    tester,
  ) async {
    final feed = await pumpButton(tester);

    await tester.tap(find.byTooltip('Mark All as Read'));
    await tester.pumpAndSettle();
    expect(enabled(tester, 'All articles'), isTrue);
    expect(enabled(tester, 'Older than a day'), isTrue);
    expect(enabled(tester, 'Older than a week'), isFalse);

    await tester.tap(find.text('Older than a day'));
    await tester.pumpAndSettle();
    expect(find.text('Mark 1 article as read?'), findsOneWidget);
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();

    expect([for (final i in feed.unreadInView()) i.id], ['fresh']);
    await tester.runAsync(() async => feed.dispose());
  });

  testWidgets('cancel leaves every article unread', (tester) async {
    final feed = await pumpButton(tester);

    await tester.tap(find.byTooltip('Mark All as Read'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All articles'));
    await tester.pumpAndSettle();
    expect(find.text('Mark 2 articles as read?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(feed.unreadInView(), hasLength(2));
    await tester.runAsync(() async => feed.dispose());
  });
}
