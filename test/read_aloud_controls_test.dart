import 'dart:async';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_speech.dart';
import 'package:ice_cream_rss_reader/theme/app_fonts.dart';
import 'package:ice_cream_rss_reader/theme/app_theme.dart';
import 'package:ice_cream_rss_reader/widgets/article/read_aloud.dart';

import 'support/real_fonts.dart';
import 'support/snapshot.dart';

/// Never finishes an utterance, so the article stays "being read".
class _SilentEngine implements SpeechEngine {
  @override
  Future<List<String>> availableLanguages() async => const ['en-US'];

  @override
  Future<bool> setLanguage(String? tag) async => true;

  @override
  Future<void> speak(String text) => Completer<void>().future;

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRealFonts);

  final item = FeedItem(
    id: 'a',
    siteName: 'Site',
    title: 'Title',
    description: '',
    feedUrl: 'https://site.test/feed',
  );

  for (final font in [AppFont.outfit, AppFont.atkinson]) {
    for (final locale in const [Locale('en'), Locale('tr'), Locale('es')]) {
      testWidgets('the reading label is whole at 320dp with 1.3x text '
          '(${locale.languageCode}, ${font.key})', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final previous = ArticleSpeech.instance;
        final speech = ArticleSpeech(engine: _SilentEngine());
        ArticleSpeech.instance = speech;
        addTearDown(() => ArticleSpeech.instance = previous);
        unawaited(
          speech.play(
            item,
            '<p>Body</p>',
            failureMessage: 'failed',
            fallbackLanguage: locale.languageCode,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: AppThemeBuilder.light(FlexScheme.blue, font),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ReadAloudControls(item: item, html: () => ''),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (const String.fromEnvironment('SNAP').isNotEmpty) {
          await snapshot(
            tester,
            '${const String.fromEnvironment('SNAP')}/read_aloud_${locale.languageCode}_${font.key}.png',
          );
        }

        final l10n = await AppLocalizations.delegate.load(locale);
        final label = find.text(l10n.readingAloud);
        expect(label, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);

        await speech.stop();
      });
    }
  }
}
