import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/home_screen.dart';
import 'package:ice_cream_rss_reader/widgets/home/pull_to_refresh.dart';

/// Counts user refreshes instead of fetching.
class _SpyFeedProvider extends FeedProvider {
  int userRefreshes = 0;

  @override
  Future<void> refreshAll({
    bool queueIfRunning = false,
    bool userInitiated = false,
  }) async {
    if (userInitiated) userRefreshes++;
  }
}

/// The feed list's pull-to-refresh: a small pull does nothing; a circle
/// fills as the list is pulled and a release once it is full refreshes.
void main() {
  late int refreshes;

  Widget app() => MaterialApp(
    home: Scaffold(
      body: PullToRefresh(
        onRefresh: () async => refreshes++,
        child: ListView.builder(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemCount: 30,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
        ),
      ),
    ),
  );

  setUp(() => refreshes = 0);

  double? fill(WidgetTester tester) {
    final circle = find.byKey(PullToRefresh.progressKey);
    if (circle.evaluate().isEmpty) return null;
    return tester.widget<CircularProgressIndicator>(circle).value;
  }

  testWidgets('nothing shows at rest', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a small pull does not refresh', (tester) async {
    await tester.pumpWidget(app());
    for (final distance in [1.0, 10.0, 40.0, 80.0]) {
      await tester.drag(find.text('row 0'), Offset(0, distance));
      await tester.pumpAndSettle();
    }
    expect(refreshes, 0);
  });

  testWidgets('the circle fills with the pull and refreshes once full', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 0')),
    );
    final fills = <double>[];
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      fills.add(fill(tester) ?? 0);
    }
    // Rises steadily and ends full.
    for (var i = 1; i < fills.length; i++) {
      expect(fills[i], greaterThanOrEqualTo(fills[i - 1]));
    }
    expect(fills.first, lessThan(0.5));
    expect(fills.last, 1.0);
    expect(refreshes, 0, reason: 'refreshes on release, not mid-pull');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('pulling back before letting go cancels', (tester) async {
    await tester.pumpWidget(app());
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 0')),
    );
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
    }
    expect(fill(tester), 1.0);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(refreshes, 0);
  });

  testWidgets('a fling that bounces off the top does not refresh', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.drag(find.text('row 2'), const Offset(0, -400));
    await tester.pumpAndSettle();
    // The finger stops short of the top; only momentum overscrolls.
    await tester.fling(find.byType(ListView), const Offset(0, 300), 4000);
    await tester.pumpAndSettle();
    expect(refreshes, 0);
  });

  group('home feed list', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('pull_to_refresh');
      Hive.init(tempDir.path);
      await Hive.openBox('settings');
      await Hive.openBox('feeds');
      await Hive.openBox('bookmarks');
      final messenger =
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
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

    testWidgets('a short pull does nothing; a full one refreshes once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final feed = _SpyFeedProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
            ChangeNotifierProvider(create: (_) => BookmarkProvider()),
            ChangeNotifierProvider<FeedProvider>.value(value: feed),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = feed.userRefreshes;
      final list = find.byType(Scrollable).first;

      await tester.drag(list, const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(feed.userRefreshes, start, reason: 'short pull');

      final gesture = await tester.startGesture(tester.getCenter(list));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump();
      }
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byKey(PullToRefresh.progressKey),
            )
            .value,
        1.0,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(feed.userRefreshes, start + 1);
      expect(tester.takeException(), isNull);
    });
  });
}
