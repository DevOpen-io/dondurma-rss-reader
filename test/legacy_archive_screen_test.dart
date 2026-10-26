import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/screens/legacy_archive_screen.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';

Widget _app(Future<List<ArticleRecord>> Function() load) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: LegacyArchiveScreen(load: load),
);

void main() {
  testWidgets('lists quarantined copies and opens one with an honest label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        () async => [
          ArticleRecord(
            id: 'shared',
            feedUrl: 'https://a.test/feed',
            title: 'Mixed copy',
            siteName: 'Site A',
            body: '<p>Saved body text</p>',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Legacy archive'), findsOneWidget);
    expect(find.text('Mixed copy'), findsOneWidget);
    expect(find.text('Site A'), findsOneWidget);
    await tester.tap(find.text('Mixed copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Source unverified'), findsOneWidget);
    expect(find.textContaining('Saved body text'), findsOneWidget);
  });

  testWidgets('shows an empty state without legacy copies', (tester) async {
    await tester.pumpWidget(_app(() async => const []));
    await tester.pumpAndSettle();
    expect(find.text('No legacy copies.'), findsOneWidget);
  });
}
