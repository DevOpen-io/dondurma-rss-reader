import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/widgets/keyword_input_sheet.dart';

void main() {
  testWidgets('a pattern stays whole, an invalid one is refused', (
    tester,
  ) async {
    List<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: KeywordInputSheet(
            title: 'Rules',
            initialKeywords: const [],
            onSave: (k) => saved = k,
            onReset: () {},
          ),
        ),
      ),
    );
    final field = find.byType(TextField);

    await tester.enterText(field, '/(broken/');
    await tester.pump(); // The add button enables on text.
    await tester.tap(find.text('Add Keyword'));
    await tester.pump();
    expect(find.text('This pattern is not valid.'), findsOneWidget);
    expect(find.text('/(broken/'), findsOneWidget, reason: 'kept to fix');

    await tester.enterText(field, 'title: /a{1,3}b/');
    await tester.pump();
    await tester.tap(find.text('Add Keyword'));
    await tester.pump();
    await tester.enterText(field, 'crypto, nft');
    await tester.pump();
    await tester.tap(find.text('Add Keyword'));
    await tester.pump();
    expect(find.text('This pattern is not valid.'), findsNothing);

    // Save with an invalid rule still in the field keeps the sheet open.
    await tester.enterText(field, '/(again/');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('This pattern is not valid.'), findsOneWidget);

    await tester.enterText(field, '');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(saved, ['title: /a{1,3}b/', 'crypto', 'nft']);
  });
}
