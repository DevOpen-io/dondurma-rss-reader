import 'dart:async';
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

  group('app bar title', () {
    for (final width in const [360.0, 411.0]) {
      testWidgets('Turkish "My Feeds" is whole at ${width.toInt()}dp', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(app(const Locale('tr'), AppFont.outfit));
        await tester.pumpAndSettle();
        final title = find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Kaynaklarım'),
        );
        expect(title, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    // A feed opened from the categories tab was titled with its folder.
    testWidgets('a selected feed titles the screen with its own name', (
      tester,
    ) async {
      await tester.pumpWidget(app(const Locale('en'), AppFont.outfit));
      await tester.pumpAndSettle();
      final home = tester.element(find.byType(HomeScreen));
      // Not awaited: the list updates at once, the Hive write would hang
      // in the fake-async zone.
      unawaited(
        home.read<SubscriptionProvider>().addFeed(
          'https://px.example/feed',
          '500px',
          'Lifestyle',
        ),
      );
      final feed = home.read<FeedProvider>();
      feed.selectFeed('https://px.example/feed');
      await tester.pump();
      Finder title(String t) =>
          find.descendant(of: find.byType(AppBar), matching: find.text(t));
      expect(title('500px'), findsOneWidget);
      expect(title('Lifestyle'), findsNothing);

      feed.selectFeed(null);
      feed.selectCategory('Lifestyle');
      await tester.pump();
      expect(title('Lifestyle'), findsOneWidget);
    });

    testWidgets('a slightly long folder name shrinks a little to fit; a '
        'very long one ends in an ellipsis', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const Locale('en'), AppFont.outfit));
      await tester.pumpAndSettle();
      final feed = tester.element(find.byType(HomeScreen)).read<FeedProvider>();
      Text titleOf(String name) => tester.widget<Text>(
        find.descendant(of: find.byType(AppBar), matching: find.text(name)),
      );

      feed.selectCategory('Technology');
      await tester.pumpAndSettle();
      final normal = titleOf('Technology').style!.fontSize!;

      feed.selectCategory('Science Stories');
      await tester.pumpAndSettle();
      final shrunk = titleOf('Science Stories').style!.fontSize!;
      expect(shrunk, lessThan(normal));
      expect(shrunk, greaterThanOrEqualTo(normal * 0.8 - 0.01));
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: find.byType(AppBar),
                matching: find.text('Science Stories'),
              ),
            )
            .didExceedMaxLines,
        isFalse,
      );

      const long = 'Science, Innovation and Space Exploration';
      feed.selectCategory(long);
      await tester.pumpAndSettle();
      expect(titleOf(long).style!.fontSize, moreOrLessEquals(normal * 0.8));
      expect(titleOf(long).overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  });
}
