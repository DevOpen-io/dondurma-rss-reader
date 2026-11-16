import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/saved_search.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/utils/app_toast.dart';
import 'package:ice_cream_rss_reader/widgets/saved_searches.dart';

void main() {
  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('saved-search-list');
    Hive.init(root.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
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
    final opened = <SavedSearch>[];
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
    expect([for (final s in opened) s.query], ['flutter']);

    await tester.longPress(find.text('Flutter news'));
    await tester.pumpAndSettle();
    // The sheet is titled with the search it acts on.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Flutter news'),
      ),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(settings.savedSearches, isEmpty);
    expect(find.text('Saved searches'), findsNothing);
  });

  testWidgets('saving a search confirms it with a toast', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(create: (_) => FeedProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => saveCurrentSearch(context),
                child: const Text('save'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Morning');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(settings.savedSearches.map((s) => s.name), contains('Morning'));
    expect(appToastController.current?.message, 'Search saved');
    expect(appToastController.current?.type, AppToastType.success);
    appToastController.dismiss();
  });
}
