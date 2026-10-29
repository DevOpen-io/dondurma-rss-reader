import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/bookmarks_screen.dart';
import 'package:ice_cream_rss_reader/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('empty_state_test');
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('bookmarks without saved articles explain how to save one', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BookmarkProvider()),
          ChangeNotifierProvider(create: (_) => FeedProvider()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: BookmarksScreen()),
        ),
      ),
    );
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.text(l10n.noBookmarks), findsOneWidget);
    expect(find.text(l10n.bookmarksSwipeHint), findsOneWidget);
  });

  testWidgets('a search matching nothing shows no "all caught up" row', (
    tester,
  ) async {
    const feedUrl = 'https://example.com/feed';
    // Awaiting a Hive write in the fake-async zone never returns; the box's
    // in-memory view updates synchronously, which is all the provider reads.
    final box = Hive.box('feeds');
    unawaited(
      box.put(
        'subscriptions',
        jsonEncode([
          FeedSubscription(
            url: feedUrl,
            name: 'Example',
            category: 'News',
          ).toJson(),
        ]),
      ),
    );
    unawaited(
      box.put(
        'cachedItemsJson',
        jsonEncode([
          FeedItem(
            id: 'a1',
            siteName: 'Example',
            title: 'Article One',
            description: '',
            feedUrl: feedUrl,
          ).toJson(),
        ]),
      ),
    );
    addTearDown(
      () => unawaited(box.deleteAll(['cachedItemsJson', 'subscriptions'])),
    );
    // The cache decodes via compute(), which only completes when the
    // provider is created outside the fake-async zone.
    await tester.runAsync(
      () => tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
            ChangeNotifierProvider(create: (_) => BookmarkProvider()),
            ChangeNotifierProxyProvider3<
              SubscriptionProvider,
              SettingsProvider,
              BookmarkProvider,
              FeedProvider
            >(
              create: (_) => FeedProvider(),
              update: (_, sub, settings, bm, feed) =>
                  (feed ?? FeedProvider())..update(sub, settings, bm),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeScreen(),
          ),
        ),
      ),
    );
    final home = tester.element(find.byType(HomeScreen));
    final l10n = AppLocalizations.of(home);
    final feed = home.read<FeedProvider>();
    for (var i = 0; i < 100 && feed.items.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('Article One'), findsOneWidget);

    feed.setSearchQuery('no-such-article');
    await tester.pump();

    expect(find.text(l10n.noFeedsMatchFilter), findsOneWidget);
    expect(find.text(l10n.allCaughtUp), findsNothing);
  });
}
