import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
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
import 'package:ice_cream_rss_reader/screens/home_screen.dart';
import 'package:ice_cream_rss_reader/theme/app_fonts.dart';
import 'package:ice_cream_rss_reader/theme/app_theme.dart';

import 'support/real_fonts.dart';

/// Bottom-bar labels stay on one line, unbroken, in every language at
/// common phone widths and with large system text. On device Turkish at
/// 1.3x read "Kategorile/r" and "Yer/İşaretleri" (2026-11-16).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    await loadRealFonts();
    tempDir = Directory.systemTemp.createTempSync('nav_labels');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
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

  Widget app(Locale locale, AppFont font) => MultiProvider(
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
    child: MaterialApp(
      locale: locale,
      theme: AppThemeBuilder.light(FlexScheme.blue, font),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    ),
  );

  /// Lines [paragraph] breaks its text into at its laid-out width.
  int lines(RenderParagraph paragraph) {
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width + 0.5);
    final count = painter.computeLineMetrics().length;
    painter.dispose();
    return count;
  }

  for (final font in [AppFont.outfit, AppFont.atkinson]) {
    for (final locale in const [Locale('en'), Locale('tr'), Locale('es')]) {
      for (final width in const [360.0, 411.0]) {
        for (final scale in const [1.0, 1.3]) {
          testWidgets('${locale.languageCode} ${font.key} ${width.toInt()}dp '
              '${scale}x: every bar label on one line', (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpWidget(app(locale, font));
            await tester.pumpAndSettle();

            final l10n = await AppLocalizations.delegate.load(locale);
            for (final label in [
              l10n.feedsTab,
              l10n.foldersTab,
              l10n.bookmarksTab,
              l10n.settingsTab,
              l10n.addFeedButton,
            ]) {
              final text = find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text(label),
              );
              expect(text, findsOneWidget, reason: label);
              final paragraph = tester.renderObject<RenderParagraph>(text);
              expect(lines(paragraph), 1, reason: '"$label" wraps');
              expect(paragraph.didExceedMaxLines, isFalse, reason: label);
            }
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
