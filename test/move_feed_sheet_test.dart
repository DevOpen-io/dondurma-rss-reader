import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/widgets/folders/move_feed_sheet.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('move_sheet_test');
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

  late SubscriptionProvider subs;

  setUp(() async {
    // Isolate each test — providers reload whatever prior tests persisted.
    await Hive.box('feeds').clear();
    subs = SubscriptionProvider();
    await subs.addFeed('https://x.com/f', 'X Feed', 'Cat');
  });

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SubscriptionProvider>.value(value: subs),
      ChangeNotifierProvider(create: (_) => FeedProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets(
    'move sheet offers inline category creation when no target exists',
    (tester) async {
      // Only 'Cat' exists — previously the sheet silently refused to open.
      await tester.pumpWidget(
        wrap(
          MoveToCategorySheet(
            sub: subs.subscriptions.first,
            onMoved: (_, _) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Move to Category'), findsOneWidget);
      expect(find.text('Add Category'), findsOneWidget);
    },
  );

  testWidgets('the new-category tile opens the create dialog on top', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MoveToCategorySheet(
          sub: FeedSubscription(
            url: 'https://x.com/f',
            name: 'X Feed',
            category: 'Cat',
          ),
          onMoved: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Add Category'));
    // Sheet push animation — bounded pump, not pumpAndSettle
    // (provider-sync timers would block it).
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('New Category Name'), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
  });

  test('moveFeedToCategory lands in a brand-new category', () async {
    // Provider-level check: the inline-created category is a plain string —
    // move assigns an icon and persists.
    await subs.moveFeedToCategory('https://x.com/f', 'Fresh Cat');
    expect(subs.subscriptions.first.category, 'Fresh Cat');
    expect(subs.categories, contains('Fresh Cat'));
  });
}
