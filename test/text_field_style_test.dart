import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/theme/app_fonts.dart';
import 'package:ice_cream_rss_reader/theme/app_theme.dart';
import 'package:ice_cream_rss_reader/widgets/bookmark_tags.dart';
import 'package:ice_cream_rss_reader/widgets/folders/folder_dialogs.dart';
import 'package:ice_cream_rss_reader/widgets/home/add_category_dialog.dart';
import 'package:ice_cream_rss_reader/widgets/saved_searches.dart';

/// Usability test 2026-10-30: the rename field looked cramped and the app's
/// text fields came in three styles. Every dialog field is now the filled,
/// rounded field of the add sheets, with room around its text.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('text_field_style');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
    await Hive.box('settings').put('savedSearches', [
      {'name': 'Flutter news', 'query': 'flutter'},
    ]);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ChangeNotifierProvider(create: (_) => BookmarkProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppThemeBuilder.light(FlexScheme.blue, AppFont.outfit),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  void expectAppField(WidgetTester tester, String where) {
    final fields = find.byType(TextField);
    expect(fields, findsWidgets, reason: where);
    final cs = Theme.of(tester.element(fields.first)).colorScheme;
    for (final element in fields.evaluate()) {
      final decoration = (element.widget as TextField).decoration!;
      expect(decoration.filled, isTrue, reason: where);
      expect(decoration.fillColor, cs.surfaceContainerHigh, reason: where);
      final border = decoration.enabledBorder as OutlineInputBorder;
      expect(border.borderSide, BorderSide.none, reason: where);
      expect(border.borderRadius, BorderRadius.circular(12), reason: where);
      final padding = decoration.contentPadding! as EdgeInsets;
      expect(padding.left, greaterThanOrEqualTo(12), reason: where);
      expect(padding.top, greaterThanOrEqualTo(12), reason: where);
    }
  }

  testWidgets('rename category', (tester) async {
    await tester.pumpWidget(
      wrap(const EditCategoryDialog(currentCategory: 'Tech')),
    );
    expectAppField(tester, 'rename category');
  });

  testWidgets('category emoji', (tester) async {
    await tester.pumpWidget(wrap(const EmojiIconDialog(category: 'Tech')));
    expectAppField(tester, 'category emoji');
  });

  testWidgets('add category', (tester) async {
    await tester.pumpWidget(wrap(const AddCategoryDialog()));
    expectAppField(tester, 'add category');
  });

  testWidgets('bookmark tags', (tester) async {
    await tester.pumpWidget(
      wrap(
        BookmarkTagsSheet(
          item: FeedItem(
            id: 'a',
            siteName: 'Site',
            title: 'Title',
            description: '',
            feedUrl: 'https://site.test/feed',
          ),
        ),
      ),
    );
    expectAppField(tester, 'bookmark tags');
  });

  testWidgets('saved search name', (tester) async {
    await tester.pumpWidget(
      wrap(
        ListView(
          children: [
            SavedSearchList(header: (_, title) => Text(title), onOpen: (_) {}),
          ],
        ),
      ),
    );
    await tester.longPress(find.text('Flutter news'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expectAppField(tester, 'saved search name');
  });
}
