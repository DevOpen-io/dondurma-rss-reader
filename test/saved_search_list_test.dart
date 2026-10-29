import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/widgets/saved_searches.dart';

void main() {
  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('saved-search-list');
    Hive.init(root.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('savedSearches', [
      {'name': 'Flutter news', 'query': 'flutter'},
    ]);
  });
  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a tap runs the search; a long press can delete it', (
    tester,
  ) async {
    final opened = <String>[];
    final settings = SettingsProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                SavedSearchList(
                  header: (_, title) => Text(title),
                  onOpen: opened.add,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Saved searches'), findsOneWidget);

    await tester.tap(find.text('Flutter news'));
    expect(opened, ['flutter']);

    await tester.longPress(find.text('Flutter news'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(settings.savedSearches, isEmpty);
    expect(find.text('Saved searches'), findsNothing);
  });
}
