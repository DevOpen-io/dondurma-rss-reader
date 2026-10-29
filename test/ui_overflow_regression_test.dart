import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/widgets/add_feed_dialog.dart';
import 'package:ice_cream_rss_reader/widgets/feed_list_item.dart';
import 'package:ice_cream_rss_reader/widgets/folders/feed_action_sheet.dart';
import 'package:ice_cream_rss_reader/widgets/home/home_bottom_nav.dart';

// #57/#58 regression: sheets that used fixed Rows overflowed under large
// text scale + long translations. Flutter reports a RenderFlex overflow as
// a test failure, so a clean pump is the assertion.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('ui_overflow_test');
    Hive.init(tempDir.path);
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');

    // FeedProvider subscribes to connectivity_plus in its ctor. Without a
    // mock, the missing plugin surfaces as an uncaught async error and
    // flakes whichever test happens to be running when it lands.
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      // EventChannel listen/cancel — a silent stream is enough.
      (call) async => null,
    );
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  late SubscriptionProvider subs;

  // setUp runs in the real async zone — Hive writes are safe here.
  // testWidgets bodies are fake-async; awaiting box puts inside them hangs.
  setUp(() async {
    // Isolate each test — providers reload whatever prior tests persisted.
    await Hive.box('feeds').clear();
    subs = SubscriptionProvider();
    await subs.addFeed('https://x.com/f', 'X Feed', 'Dünya Haberleri');
  });

  Widget wrap({required Widget child, required SubscriptionProvider subs}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SubscriptionProvider>.value(value: subs),
          ChangeNotifierProvider(create: (_) => BookmarkProvider()),
          ChangeNotifierProvider(create: (_) => FeedProvider()),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            // Narrow device + large system font — the audited failure mode.
            data: const MediaQueryData(
              size: Size(340, 700),
              textScaler: TextScaler.linear(1.4),
            ),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );

  testWidgets('feed action sheet fits at 340px width, 1.4x scale, TR', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        subs: subs,
        child: FeedActionSheet(
          subUrl: 'https://x.com/f',
          onMove: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );
    // Bounded pumps — pumpAndSettle would wait on provider-sync timers.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // All three chips must be fully laid out — previously the row
    // overflowed and 'Kapalı' was clipped.
    expect(find.text('Varsayılan'), findsOneWidget);
    expect(find.text('Açık'), findsOneWidget);
    expect(find.text('Kapalı'), findsOneWidget);
  });

  testWidgets('add feed dialog header fits at 340px width, 1.4x scale, TR', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(subs: subs, child: const AddFeedDialog()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('RSS Kaynağı Ekle'), findsOneWidget);
  });

  FeedItem longMetaItem() => FeedItem(
    id: 'n1',
    siteName: '"site:apnews.com" - Google News Very Long Site Name',
    title: 'Başlık',
    description: 'Açıklama',
    link: 'https://x.com/a',
    pubDate: DateTime.now().subtract(const Duration(hours: 1)),
    category: 'Dünya Haberleri',
    feedUrl: 'https://x.com/f',
  );

  testWidgets(
    'feed list item keeps site+category segments at 480px, 1.4x, TR',
    (tester) async {
      tester.view.physicalSize = const Size(480, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          subs: subs,
          child: FeedListItem(item: longMetaItem()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The category segment must be its own Text — in the old single
      // Text.rich the whole tail (category included) could be clipped by
      // one ellipsis, producing 'Top Stori… · …'.
      // 14-char cap: 'Dünya Haberle…'
      final categoryText = tester.widget<Text>(
        find.textContaining('Dünya Haberle'),
      );
      expect(categoryText.textSpan, isNull);
      expect(categoryText.data, startsWith(' · '));
    },
  );

  testWidgets(
    'feed list item hides category entirely below the meta threshold',
    (tester) async {
      tester.view.physicalSize = const Size(288, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          subs: subs,
          child: FeedListItem(item: longMetaItem()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // ~157px meta width: the site name keeps its own ellipsis, the
      // category segment is omitted rather than rendered as a lone '…'.
      expect(find.textContaining('Dünya Haberle'), findsNothing);
      // 20-char cap: '"site:apnews.com" - Go…'
      expect(find.textContaining('apnews'), findsOneWidget);
    },
  );

  testWidgets('nav bar label stays readable at 1.4x scale', (tester) async {
    tester.view.physicalSize = const Size(340, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        subs: subs,
        child: Row(
          children: [
            Expanded(
              child: NavBarItem(
                icon: Icons.folder,
                label: 'Kategoriler',
                selected: true,
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 10.5px label at 1.4x overflows a quarter-width slot unless the
    // text scale is clamped — effective size stays at or under ~1.2x.
    final text = tester.widget<Text>(find.text('Kategoriler'));
    final scaler = MediaQuery.textScalerOf(
      tester.element(find.text('Kategoriler')),
    );
    expect(scaler.scale(10.5), lessThanOrEqualTo(10.5 * 1.25));
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
