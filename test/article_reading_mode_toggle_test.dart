import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/widgets/article/article_reading_mode_toggle.dart';

void main() {
  Future<AppLocalizations> pump(
    WidgetTester tester, {
    required bool isFullText,
    required bool isLoading,
    required VoidCallback onToggle,
    Locale locale = const Locale('en'),
    double width = 400,
    double textScale = 1,
  }) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context);
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: ArticleReadingModeToggle(
                      isFullText: isFullText,
                      isLoading: isLoading,
                      onToggle: onToggle,
                      colorScheme: Theme.of(context).colorScheme,
                      l10n: l10n,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    return l10n;
  }

  testWidgets('switching modes calls onToggle once', (tester) async {
    var toggles = 0;
    final l10n = await pump(
      tester,
      isFullText: false,
      isLoading: false,
      onToggle: () => toggles++,
    );

    await tester.tap(find.text(l10n.modeShort));
    expect(toggles, 0, reason: 'the active mode is not a toggle');
    await tester.tap(find.text(l10n.modeFull));
    expect(toggles, 1);
  });

  testWidgets('while full text loads the control says so and is inert', (
    tester,
  ) async {
    var toggles = 0;
    final l10n = await pump(
      tester,
      isFullText: false,
      isLoading: true,
      onToggle: () => toggles++,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.fullTextLoading), findsOneWidget);
    await tester.tap(find.text(l10n.modeFull));
    await tester.tap(find.text(l10n.modeShort));
    expect(toggles, 0);
  });

  testWidgets('the active mode is announced as selected', (tester) async {
    final handle = tester.ensureSemantics();
    final l10n = await pump(
      tester,
      isFullText: true,
      isLoading: false,
      onToggle: () {},
    );
    expect(
      tester.getSemantics(find.text(l10n.modeFull)),
      matchesSemantics(
        label: l10n.modeFull,
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('labels are never cut off beside the read-aloud button on a '
      '320dp phone', (tester) async {
    // 320dp minus the page margins and the 48dp button with its gap.
    for (final (locale, scale) in [
      (const Locale('es'), 1.0),
      (const Locale('tr'), 1.3),
      (const Locale('en'), 1.3),
    ]) {
      for (final loading in [false, true]) {
        await pump(
          tester,
          isFullText: false,
          isLoading: loading,
          onToggle: () {},
          locale: locale,
          width: 222,
          textScale: scale,
        );
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byType(ArticleReadingModeToggle),
            matching: find.byType(RichText),
          ),
        )) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$locale x$scale loading=$loading: ${paragraph.text}',
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('each mode is a 48dp touch target', (tester) async {
    final l10n = await pump(
      tester,
      isFullText: true,
      isLoading: false,
      onToggle: () {},
    );
    expect(
      tester.getSize(find.text(l10n.modeShort)).height,
      lessThan(48),
      reason: 'sanity: the label itself is smaller than the target',
    );
    final button = find.ancestor(
      of: find.text(l10n.modeShort),
      matching: find.byWidgetPredicate(
        (w) => w is InkWell || w is ButtonStyleButton,
      ),
    );
    expect(tester.getSize(button.first).height, greaterThanOrEqualTo(48));
  });
}
