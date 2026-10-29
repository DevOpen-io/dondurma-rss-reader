import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/widgets/home/add_feed_button.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool labelShown}) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            floatingActionButton: AddFeedButton(
              labelShown: labelShown,
              onPressed: () {},
            ),
          ),
        ),
      );

  testWidgets('says what it does, and folds to its icon while reading', (
    tester,
  ) async {
    await pump(tester, labelShown: true);
    expect(find.text('Add feed'), findsOneWidget);
    final wide = tester.getSize(find.byType(FloatingActionButton)).width;

    await pump(tester, labelShown: false);
    await tester.pumpAndSettle();
    expect(find.text('Add feed'), findsNothing);
    expect(find.byTooltip('Add new feed'), findsOneWidget);
    final folded = tester.getSize(find.byType(FloatingActionButton));
    expect(folded.width, lessThan(wide));
    expect(folded.height, greaterThanOrEqualTo(48));
  });
}
