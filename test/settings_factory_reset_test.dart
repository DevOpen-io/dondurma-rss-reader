import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/widgets/adaptive_dialog.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/settings_screen.dart';
import 'package:provider/provider.dart';

/// The confirm button's context belongs to the dialog, which is gone by the
/// time the reset awaits finish; the redirect to onboarding must still run.
// Settings keeps an indeterminate indicator alive, so pumpAndSettle never
// returns; pump a bounded number of frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('settings_factory_reset');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('home_widget'),
          (_) async => true,
        );
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

  testWidgets('factory reset lands on onboarding', (tester) async {
    // WebView cookies are only cleared on mobile/macOS; keep the host free
    // of platform plugins that the test binding cannot provide.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: SettingsScreen()),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const Scaffold(body: Text('onboarding-route')),
        ),
      ],
    );
    addTearDown(router.dispose);

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
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
    });
    await settle(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SettingsScreen)),
    );
    await tester.tap(find.text(l10n.factoryReset).first);
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(ActionSheet),
        matching: find.text(l10n.factoryReset),
      ),
    );
    // The reset stages touch real files; let them finish outside fake time.
    final onboarding = find.text('onboarding-route');
    for (var i = 0; i < 100 && onboarding.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
    debugDefaultTargetPlatformOverride = null;

    expect(onboarding, findsOneWidget);
  });
}
