import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/categories_screen.dart';
import 'package:ice_cream_rss_reader/screens/desktop/desktop_sidebar.dart';
import 'package:ice_cream_rss_reader/utils/app_toast.dart';
import 'package:ice_cream_rss_reader/widgets/adaptive_dialog.dart';
import 'package:ice_cream_rss_reader/widgets/add_feed_dialog.dart';
import 'package:ice_cream_rss_reader/widgets/app_drawer.dart';
import 'package:ice_cream_rss_reader/widgets/folders/category_action_sheet.dart';
import 'package:ice_cream_rss_reader/widgets/folders/feed_action_sheet.dart';
import 'package:ice_cream_rss_reader/widgets/folders/move_feed_sheet.dart';

/// Counts refreshes instead of fetching — the flows under test only need to
/// prove refreshAll() follows the provider mutation.
class _SpyFeedProvider extends FeedProvider {
  int refreshes = 0;

  @override
  Future<void> refreshAll({
    bool queueIfRunning = false,
    bool userInitiated = false,
  }) async {
    refreshes++;
  }
}

/// Feed/folder action flows reachable from the drawer, the categories screen
/// and the desktop sidebar: same sheets, same confirmations, same provider
/// calls, on both the mobile sheet and the desktop dialog presentation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late SubscriptionProvider subs;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('folder_actions');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
    PackageInfo.setMockInitialValues(
      appName: 'Dondurma',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    // FeedProvider subscribes to connectivity_plus in its ctor.
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    // Not awaited: Hive's in-memory view updates synchronously, while a
    // write left pending by the previous test's fake-async zone would block
    // an awaited one forever.
    final box = Hive.box('feeds');
    box.deleteAll(box.keys.toList());
    box.put(
      'subscriptions',
      jsonEncode([
        for (final (url, name, category) in const [
          ('https://a.example/feed', 'Feed A1', 'Tech'),
          ('https://a2.example/feed', 'Feed A2', 'Tech'),
          ('https://b.example/feed', 'Feed B1', 'Science'),
        ])
          FeedSubscription(url: url, name: name, category: category).toJson(),
      ]),
    );
    subs = SubscriptionProvider();
  });

  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  /// Real app shape: providers above a GoRouter-backed MaterialApp.
  Widget app(Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SubscriptionProvider>.value(value: subs),
      ChangeNotifierProvider<FeedProvider>(create: (_) => _SpyFeedProvider()),
      ChangeNotifierProvider(create: (_) => BookmarkProvider()),
      // The sidebar lists saved searches from the settings.
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => home)],
      ),
    ),
  );

  _SpyFeedProvider feedOf(WidgetTester tester) =>
      tester.element(find.byType(Scaffold).first).read<FeedProvider>()
          as _SpyFeedProvider;

  /// Bounded pumps — FeedProvider timers keep pumpAndSettle busy.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets real Hive I/O finish and flushes the continuations queued in the
  /// fake-async zone until the refresh that follows the write has run.
  Future<void> settleWrites(WidgetTester tester, int refreshes) async {
    for (var i = 0; i < 100 && feedOf(tester).refreshes < refreshes; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    // Hive chains every write on the previous write's future. Re-anchor the
    // chain in the real zone: a future from this test's fake-async zone
    // would never notify the next test's writes once that zone is gone.
    await tester.runAsync(() => Hive.box('feeds').put('testAnchor', 0));
    await settle(tester);
  }

  void phoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  void desktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// The old hand-drawn grabber: a 36–40 × 4 rounded bar.
  final handDrawnHandle = find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.constraints?.maxHeight == 4 &&
        w.constraints?.minHeight == 4 &&
        (w.constraints?.maxWidth == 36 || w.constraints?.maxWidth == 40),
  );

  Finder nodeIcon(String category, IconData icon) => find.descendant(
    of: find.widgetWithText(ExpansionTile, category),
    matching: find.byIcon(icon),
  );

  // ── Categories screen ────────────────────────────────────────────────

  Future<void> pumpCategories(WidgetTester tester) async {
    await tester.pumpWidget(app(const Scaffold(body: CategoriesScreen())));
    await settle(tester);
  }

  group('categories screen', () {
    testWidgets('tapping a feed opens the feed action sheet', (tester) async {
      phoneSurface(tester);
      await pumpCategories(tester);

      await tester.tap(find.text('Feed A1'));
      await settle(tester);

      expect(find.byType(FeedActionSheet), findsOneWidget);
      expect(find.text('Move to Category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('feed delete confirms, removes the feed, then refreshes', (
      tester,
    ) async {
      phoneSurface(tester);
      await pumpCategories(tester);
      final before = feedOf(tester).refreshes;

      await tester.tap(find.text('Feed A1'));
      await settle(tester);
      await tester.tap(find.text('Delete Feed'));
      await settle(tester);

      expect(find.byType(FeedActionSheet), findsNothing);
      expect(find.byType(ActionSheet), findsOneWidget);
      expect(subs.subscriptions.map((s) => s.name), contains('Feed A1'));

      await tester.tap(
        find.descendant(
          of: find.byType(ActionSheet),
          matching: find.text('Delete'),
        ),
      );
      await settleWrites(tester, before + 1);

      expect(find.byType(ActionSheet), findsNothing);
      expect(subs.subscriptions.map((s) => s.name), isNot(contains('Feed A1')));
      expect(feedOf(tester).refreshes, before + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('feed delete cancel keeps the feed', (tester) async {
      phoneSurface(tester);
      await pumpCategories(tester);

      await tester.tap(find.text('Feed A1'));
      await settle(tester);
      await tester.tap(find.text('Delete Feed'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(find.byType(ActionSheet), findsNothing);
      expect(subs.subscriptions.length, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('folder delete confirms with Delete All and drops its feeds', (
      tester,
    ) async {
      phoneSurface(tester);
      await pumpCategories(tester);
      final before = feedOf(tester).refreshes;

      // Science sorts first — the second overflow menu belongs to Tech.
      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await settle(tester);
      await tester.tap(find.text('Delete Category'));
      await settle(tester);

      expect(find.byType(ActionSheet), findsOneWidget);
      await tester.tap(find.text('Delete All'));
      await settleWrites(tester, before + 1);

      expect(find.byType(ActionSheet), findsNothing);
      expect(
        subs.subscriptions.map((s) => s.category),
        everyElement('Science'),
      );
      expect(feedOf(tester).refreshes, before + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile sheets use the built-in drag handle only', (
      tester,
    ) async {
      phoneSurface(tester);
      await pumpCategories(tester);

      await tester.tap(find.text('Feed A1'));
      await settle(tester);

      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue,
      );
      expect(handDrawnHandle, findsNothing);
    });

    testWidgets('desktop shows the feed actions in a dialog without a handle', (
      tester,
    ) async {
      desktopSurface(tester);
      await pumpCategories(tester);

      await tester.tap(find.text('Feed A1'));
      await settle(tester);

      expect(
        find.ancestor(
          of: find.byType(FeedActionSheet),
          matching: find.byType(Dialog),
        ),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(handDrawnHandle, findsNothing);
    }, variant: desktop);
  });

  // ── Mobile drawer ────────────────────────────────────────────────────

  Future<void> pumpDrawer(WidgetTester tester) async {
    phoneSurface(tester);
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      app(
        Scaffold(key: key, drawer: const AppDrawer(), body: const SizedBox()),
      ),
    );
    await settle(tester);
    key.currentState!.openDrawer();
    await settle(tester);
    // The app name is wider than the drawer under the square-glyph test
    // font, as under a large system font on a device: it must still fit.
    expect(tester.takeException(), isNull);
  }

  group('drawer', () {
    testWidgets('long-pressing a feed opens the feed action sheet', (
      tester,
    ) async {
      await pumpDrawer(tester);
      await tester.tap(nodeIcon('Tech', Icons.expand_more));
      await settle(tester);

      await tester.longPress(find.text('Feed A1'));
      await settle(tester);

      expect(find.byType(FeedActionSheet), findsOneWidget);
      expect(handDrawnHandle, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('moving a feed shows the success toast and refreshes', (
      tester,
    ) async {
      await pumpDrawer(tester);
      await tester.tap(nodeIcon('Tech', Icons.expand_more));
      await settle(tester);
      final before = feedOf(tester).refreshes;

      await tester.longPress(find.text('Feed A1'));
      await settle(tester);
      await tester.tap(find.text('Move to Category'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(MoveToCategorySheet),
          matching: find.text('Science'),
        ),
      );
      await settleWrites(tester, before + 1);

      expect(
        subs.subscriptions.firstWhere((s) => s.name == 'Feed A1').category,
        'Science',
      );
      expect(
        appToastController.current?.message,
        '"Feed A1" moved to "Science" category',
      );
      expect(appToastController.current?.type, AppToastType.success);
      // The toast's auto-dismiss timer must not outlive the test.
      appToastController.dismiss();
      expect(feedOf(tester).refreshes, before + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('category options delete confirms with Delete All', (
      tester,
    ) async {
      await pumpDrawer(tester);
      final before = feedOf(tester).refreshes;

      await tester.tap(nodeIcon('Tech', Icons.more_vert));
      await settle(tester);
      expect(find.byType(CategoryActionSheet), findsOneWidget);
      expect(handDrawnHandle, findsNothing);

      await tester.tap(find.text('Delete Category'));
      await settle(tester);
      await tester.tap(find.text('Delete All'));
      await settleWrites(tester, before + 1);

      expect(
        subs.subscriptions.map((s) => s.category),
        everyElement('Science'),
      );
      expect(feedOf(tester).refreshes, before + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('category options target is at least 48dp', (tester) async {
      await pumpDrawer(tester);

      final target = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Category options',
      );
      expect(target, findsWidgets);
      final size = tester.getSize(target.first);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      // The larger target must not grow the 56dp category header.
      final header = find.ancestor(
        of: find.text('Tech'),
        matching: find.byType(ListTile),
      );
      expect(tester.getSize(header).height, 56);
    });
  });

  // ── Desktop sidebar ──────────────────────────────────────────────────

  Future<void> pumpSidebar(WidgetTester tester) async {
    desktopSurface(tester);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SizedBox(
            width: 320,
            child: DesktopSidebar(
              section: DesktopSection.articles,
              onSectionChanged: (_) {},
              onAddFeed: () {},
              onAddCategory: () {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  group('desktop sidebar', () {
    testWidgets('long-pressing a feed opens the feed actions dialog', (
      tester,
    ) async {
      await pumpSidebar(tester);
      await tester.tap(nodeIcon('Tech', Icons.expand_more));
      await settle(tester);

      await tester.longPress(find.text('Feed A1'));
      await settle(tester);

      expect(
        find.ancestor(
          of: find.byType(FeedActionSheet),
          matching: find.byType(Dialog),
        ),
        findsOneWidget,
      );
      expect(handDrawnHandle, findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: desktop);

    testWidgets('feed delete from the sidebar removes the feed and refreshes', (
      tester,
    ) async {
      await pumpSidebar(tester);
      await tester.tap(nodeIcon('Tech', Icons.expand_more));
      await settle(tester);
      final before = feedOf(tester).refreshes;

      await tester.longPress(find.text('Feed A1'));
      await settle(tester);
      await tester.tap(find.text('Delete Feed'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(ActionSheet),
          matching: find.text('Delete'),
        ),
      );
      await settleWrites(tester, before + 1);

      expect(subs.subscriptions.map((s) => s.name), isNot(contains('Feed A1')));
      expect(feedOf(tester).refreshes, before + 1);
      expect(tester.takeException(), isNull);
    }, variant: desktop);

    testWidgets('category options delete confirms with Delete All', (
      tester,
    ) async {
      await pumpSidebar(tester);
      final before = feedOf(tester).refreshes;

      await tester.tap(nodeIcon('Tech', Icons.more_horiz));
      await settle(tester);
      expect(find.byType(CategoryActionSheet), findsOneWidget);

      await tester.tap(find.text('Delete Category'));
      await settle(tester);
      await tester.tap(find.text('Delete All'));
      await settleWrites(tester, before + 1);

      expect(
        subs.subscriptions.map((s) => s.category),
        everyElement('Science'),
      );
      expect(feedOf(tester).refreshes, before + 1);
      expect(tester.takeException(), isNull);
    }, variant: desktop);

    testWidgets('selected feed marks its parent with the ancestor accent', (
      tester,
    ) async {
      await pumpSidebar(tester);
      // Ancestor lookup resolves the feed's live category.
      feedOf(tester)
        ..subscriptionProvider = subs
        ..selectFeed('https://a.example/feed');
      await settle(tester);

      final bars = tester
          .widgetList<Positioned>(
            find.descendant(
              of: find.byType(DesktopSidebar),
              matching: find.byType(Positioned),
            ),
          )
          .where((p) => p.left == 0 && p.top == 10 && p.bottom == 10);
      expect(bars.length, 1);
      // Collapsed ancestor auto-expanded to reveal the selected feed.
      expect(find.text('Feed A1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: desktop);
  });

  // ── Add-feed category picker ─────────────────────────────────────────

  Future<void> pumpAddFeed(WidgetTester tester) async {
    phoneSurface(tester);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  showAdaptiveSheet<void>(ctx, const AddFeedDialog()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  group('add feed category picker', () {
    testWidgets('picking an existing category fills the field', (tester) async {
      await pumpAddFeed(tester);

      await tester.tap(find.text('Technology, News, etc.'));
      await settle(tester);
      await tester.tap(find.text('Science').last);
      await settle(tester);

      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller
            ?.text,
        'Science',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new category fills the field without creating it', (
      tester,
    ) async {
      await pumpAddFeed(tester);

      await tester.tap(find.text('Technology, News, etc.'));
      await settle(tester);
      await tester.tap(find.text('Add Category'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tech, Sports, Finance…'),
        'Fresh',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller
            ?.text,
        'Fresh',
      );
      // Nothing is persisted until the feed itself is saved.
      expect(subs.categories, isNot(contains('Fresh')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the current choice is marked when reopening the picker', (
      tester,
    ) async {
      await pumpAddFeed(tester);

      await tester.tap(find.text('Technology, News, etc.'));
      await settle(tester);
      await tester.tap(find.text('Science').last);
      await settle(tester);
      await tester.tap(find.text('Science'));
      await settle(tester);

      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Science'),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(handDrawnHandle, findsNothing);
    });
  });
}
