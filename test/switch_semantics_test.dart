import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/settings_screen.dart';
import 'package:ice_cream_rss_reader/widgets/folders/feed_action_sheet.dart';

/// Every switch-like semantics node under the root: screen readers name a
/// switch by its label, so an empty one reads as "switch, on".
List<SemanticsNode> _switchNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isToggled != Tristate.none) nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Settings keeps an indeterminate indicator alive: bounded pumps only.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('switch_semantics');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
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

  testWidgets('every settings switch is named after its row', (tester) async {
    final handle = tester.ensureSemantics();
    // Tall enough that the lazy list builds every row at once.
    tester.view.physicalSize = const Size(800, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(
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
                  feed!..update(sub, settings, bm),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
    });
    await _pumpFrames(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettingsScreen)),
    );
    final switches = _switchNodes(tester);
    expect(
      switches.length,
      find.byType(Switch, skipOffstage: false).evaluate().length,
    );
    expect(switches, isNotEmpty);
    for (final node in switches) {
      expect(node.label.trim(), isNotEmpty, reason: '$node');
    }
    final labels = switches.map((n) => n.label).toList();
    for (final name in [
      l10n.adBlocker,
      l10n.webviewDarkMode,
      l10n.fullTextExtraction,
      l10n.markReadOnScroll,
      l10n.enableNotifications,
      l10n.quietHoursEnabled,
      l10n.syncBackground,
    ]) {
      expect(labels, contains(name));
    }
    handle.dispose();
  });

  group('feed action sheet', () {
    late SubscriptionProvider subs;
    // Real async zone: awaiting Hive writes in a widget test body hangs.
    setUp(() async {
      await Hive.box('feeds').clear();
      subs = SubscriptionProvider();
      await subs.addFeed('https://x.com/f', 'X Feed', 'News');
    });

    testWidgets('the feed notifications switch is named', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SubscriptionProvider>.value(value: subs),
            ChangeNotifierProvider(create: (_) => BookmarkProvider()),
            ChangeNotifierProvider(create: (_) => FeedProvider()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: FeedActionSheet(
                  subUrl: 'https://x.com/f',
                  onMove: () {},
                  onEdit: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final switches = _switchNodes(tester);
      expect(switches, hasLength(1));
      expect(switches.single.label, 'Feed Notifications');
      handle.dispose();
    });
  });
}
