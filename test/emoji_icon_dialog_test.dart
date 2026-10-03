import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/widgets/category_icon.dart';
import 'package:ice_cream_rss_reader/widgets/folders/folder_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late SubscriptionProvider provider;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('emoji-dialog-');
    Hive.init(tempDirectory.path);
    await Hive.openBox('feeds');
  });

  setUp(() {
    // No awaited box ops here: a Hive write issued inside a testWidgets body
    // (e.g. the dialog's Save) stays pending under FakeAsync and deadlocks any
    // later awaited box op. Tests use distinct categories to stay isolated.
    provider = SubscriptionProvider();
  });

  Widget wrap(Widget child) => ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  /// Mutates the in-memory icon synchronously — the returned future must not
  /// be awaited inside a testWidgets body (FakeAsync vs. real I/O deadlock).
  void seedEmoji(String category, String emoji) {
    unawaited(provider.setCategoryEmoji(category, emoji));
  }

  testWidgets('dialog saves typed emoji as the category icon', (tester) async {
    await tester.pumpWidget(wrap(const EmojiIconDialog(category: 'SaveCat')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '🎌');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(provider.getCategoryEmoji('SaveCat'), '🎌');
  });

  testWidgets('dialog is prefilled with the stored emoji', (tester) async {
    seedEmoji('PrefilledCat', '🚀');
    await tester.pumpWidget(
      wrap(const EmojiIconDialog(category: 'PrefilledCat')),
    );
    await tester.pumpAndSettle();

    expect(find.text('🚀'), findsWidgets);
  });

  testWidgets('empty save restores the default icon', (tester) async {
    seedEmoji('ResetCat', '🚀');
    await tester.pumpWidget(wrap(const EmojiIconDialog(category: 'ResetCat')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(provider.getCategoryEmoji('ResetCat'), isNull);
  });

  testWidgets('CategoryIcon renders Text for emoji, Icon for legacy', (
    tester,
  ) async {
    seedEmoji('EmojiCat', '🦊');
    await tester.pumpWidget(
      wrap(
        const Column(
          children: [
            CategoryIcon(category: 'EmojiCat', size: 18),
            CategoryIcon(category: 'LegacyCat', size: 18),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🦊'), findsOneWidget);
    // LegacyCat falls back to the default folder icon.
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  });
}
