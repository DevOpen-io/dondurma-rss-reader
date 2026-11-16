import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
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
import 'package:ice_cream_rss_reader/screens/settings_screen.dart';
import 'package:ice_cream_rss_reader/theme/app_fonts.dart';
import 'package:ice_cream_rss_reader/theme/app_theme.dart';

import 'support/real_fonts.dart';

/// Every settings row lays out without errors in every language on common
/// phone widths, with real fonts and large text. Turkish at 360dp threw
/// "Trailing widget consumes the entire tile width" (2026-11-16).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    await loadRealFonts();
    tempDir = Directory.systemTemp.createTempSync('settings_layout');
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

  for (final locale in const [Locale('en'), Locale('tr'), Locale('es')]) {
    for (final width in const [360.0, 412.0]) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('${locale.languageCode} ${width.toInt()}dp ${scale}x: '
            'settings lay out cleanly', (tester) async {
          // Tall enough that the lazy list builds every row at once.
          tester.view.physicalSize = Size(width, 9000);
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) =>
              errors.add(details.exceptionAsString().split('\n').first);
          addTearDown(() => FlutterError.onError = previous);

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
                  locale: locale,
                  theme: AppThemeBuilder.light(FlexScheme.blue, AppFont.outfit),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: const Scaffold(body: SettingsScreen()),
                ),
              ),
            );
          });
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          FlutterError.onError = previous;
          expect(errors, isEmpty);
        });
      }
    }
  }
}
