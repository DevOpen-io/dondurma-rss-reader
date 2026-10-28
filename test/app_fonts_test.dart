import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/theme/app_fonts.dart';
import 'package:ice_cream_rss_reader/theme/app_theme.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unknown or missing app font keys fall back to Outfit', () {
    expect(AppFont.fromKey(null), AppFont.outfit);
    expect(AppFont.fromKey('comic-sans'), AppFont.outfit);
    expect(AppFont.fromKey('lexend'), AppFont.lexend);
  });

  test('stored article typefaces keep their meaning', () {
    // Values saved before fonts were bundled.
    expect(articleFontFamily('serif', AppFont.outfit), 'Literata');
    expect(
      articleFontFamily('sans-serif', AppFont.outfit),
      'AtkinsonHyperlegibleNext',
    );
    expect(articleFontFamily('mono', AppFont.outfit), 'monospace');
    // 'system' follows the app font.
    expect(articleFontFamily('system', AppFont.lexend), 'Lexend');
    expect(articleFontFamily('system', AppFont.system), isNull);
    expect(articleFontFamily('unknown', AppFont.outfit), 'Outfit');
  });

  test('every bundled family is declared in the font manifest', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final declared = {
      for (final entry in manifest.cast<Map<String, dynamic>>())
        entry['family'] as String: [
          for (final font in (entry['fonts'] as List).cast<Map>())
            font['asset'] as String,
        ],
    };
    for (final font in AppFont.values) {
      if (font.family == null) continue;
      final assets = declared[font.family];
      expect(assets, isNotNull, reason: '${font.family} missing');
      for (final asset in assets!) {
        expect((await rootBundle.load(asset)).lengthInBytes, greaterThan(0));
      }
    }
  });

  test('themes use the chosen bundled family', () {
    for (final font in AppFont.values) {
      final theme = AppThemeBuilder.light(FlexScheme.blue, font);
      expect(theme.textTheme.bodyMedium!.fontFamily, font.family ?? isNot(''));
      if (font.family != null) {
        expect(theme.textTheme.titleLarge!.fontFamily, font.family);
        expect(theme.appBarTheme.titleTextStyle!.fontFamily, font.family);
      }
    }
  });

  group('SettingsProvider app font', () {
    late Directory dir;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('app_fonts_test');
      Hive.init(dir.path);
      await Hive.openBox('settings');
    });

    tearDownAll(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('defaults to Outfit and persists the choice', () async {
      await Hive.box('settings').clear();
      final settings = SettingsProvider();
      expect(settings.appFont, AppFont.outfit);
      await settings.setAppFont(AppFont.atkinson);
      expect(Hive.box('settings').get('appFont'), 'atkinson');
      expect(SettingsProvider().appFont, AppFont.atkinson);
    });
  });

  test('font licenses reach the license page', () async {
    registerFontLicenses();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    for (final font in AppFont.values) {
      if (font.family != null) expect(packages, contains(font.family));
    }
  });

  testWidgets('bundled fonts render without network access', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.light(FlexScheme.blue, AppFont.literata),
        home: const Text('Okunabilir metin ğüşıöç'),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
