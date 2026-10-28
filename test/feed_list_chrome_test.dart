import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/refresh_progress.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/widgets/home/filter_bottom_sheet.dart';
import 'package:ice_cream_rss_reader/widgets/home/offline_banner.dart';
import 'package:ice_cream_rss_reader/widgets/home/refresh_progress_count.dart';

/// List chrome shared by the mobile feed tab and the desktop list pane.
/// The desktop variants keep their denser sizes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('feed_list_chrome_test');
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

  Widget app(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ChangeNotifierProvider(create: (_) => FeedProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  for (final (desktop, padding, iconSize, fontSize) in const [
    (false, EdgeInsets.symmetric(horizontal: 16, vertical: 8), 16.0, 13.0),
    (true, EdgeInsets.symmetric(horizontal: 14, vertical: 7), 15.0, 12.5),
  ]) {
    testWidgets('offline banner (desktop: $desktop) keeps its sizes', (
      tester,
    ) async {
      await tester.pumpWidget(app(OfflineBanner(desktop: desktop)));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));

      final text = tester.widget<Text>(find.text(l10n.offlineBanner));
      expect(text.style?.fontSize, fontSize);
      expect(tester.widget<Icon>(find.byIcon(Icons.wifi_off)).size, iconSize);
      final pad = tester.widget<Padding>(
        find
            .ancestor(of: find.byType(Row), matching: find.byType(Padding))
            .first,
      );
      expect(pad.padding, padding);
    });
  }

  for (final (desktop, spinner, gap) in const [
    (false, 13.0, 8.0),
    (true, 14.0, 7.0),
  ]) {
    testWidgets('refresh count (desktop: $desktop) shows completed / total', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          RefreshProgressCount(
            progress: const RefreshProgress(
              phase: RefreshPhase.refreshing,
              total: 10,
              completed: 3,
            ),
            desktop: desktop,
          ),
        ),
      );

      expect(find.text('3 / 10'), findsOneWidget);
      final boxes = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(RefreshProgressCount),
              matching: find.byType(SizedBox),
            ),
          )
          .toList();
      expect(boxes.first.width, spinner);
      expect(boxes.first.height, spinner);
      expect(boxes[1].width, gap);
    });
  }

  testWidgets('filter button badges an active filter and opens the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(app(const FilterSheetButton(active: false)));
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    expect(find.byIcon(Icons.filter_list), findsOneWidget);

    await tester.pumpWidget(app(const FilterSheetButton(active: true)));
    final cs = Theme.of(tester.element(find.byType(Badge))).colorScheme;
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.filter_list)).color,
      cs.primary,
    );

    await tester.tap(find.byType(FilterSheetButton));
    await tester.pumpAndSettle();
    expect(find.byType(FilterBottomSheet), findsOneWidget);
  });

  testWidgets('desktop filter button uses the smaller rounded glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const FilterSheetButton(active: false, desktop: true)),
    );
    final cs = Theme.of(tester.element(find.byType(Badge))).colorScheme;
    final icon = tester.widget<Icon>(find.byIcon(Icons.filter_list_rounded));
    expect(icon.size, 20);
    expect(icon.color, cs.onSurfaceVariant);
  });
}
