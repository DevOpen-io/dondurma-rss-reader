import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/explore_feeds_page.dart';
import 'package:ice_cream_rss_reader/widgets/explore_feeds/explore_feeds_widgets.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('explore_feeds_page');
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
    } on FileSystemException {
      // Best-effort cleanup.
    }
  });

  testWidgets('leaving before the suggested lists load does not throw', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final page = MultiProvider(
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
              feed!..update(sub, settings, bm),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ExploreFeedsPage(),
      ),
    );
    await http.runWithClient(
      () => tester.pumpWidget(page),
      () => MockClient((_) => response.future),
    );
    // Leave while both requests are still in flight, then let them land.
    await tester.pumpWidget(const SizedBox());
    response.complete(http.Response('[]', 200));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the filter bar names its picker in the app language', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ExploreFilterBar(
              selectedCategory: null,
              totalCount: 3,
              onTap: () {},
              colorScheme: Theme.of(context).colorScheme,
              l10n: AppLocalizations.of(context),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Kategoriler'), findsOneWidget);
    expect(find.text('Categories'), findsNothing);
  });
}
