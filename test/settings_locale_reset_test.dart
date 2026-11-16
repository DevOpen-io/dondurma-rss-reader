import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('settings_locale_reset');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  setUp(() => Hive.box('settings').clear());

  tearDown(binding.platformDispatcher.clearLocalesTestValue);

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup.
    }
  });

  void deviceLocales(List<Locale> locales) =>
      binding.platformDispatcher.localesTestValue = locales;

  test('without a chosen language the app follows the device', () {
    deviceLocales(const [Locale('tr', 'TR')]);
    expect(SettingsProvider().locale, const Locale('tr'));
  });

  test('a device language the app lacks falls back to the first supported '
      'one, then English', () {
    deviceLocales(const [Locale('de'), Locale('es')]);
    expect(SettingsProvider().locale, const Locale('es'));
    deviceLocales(const [Locale('de')]);
    expect(SettingsProvider().locale, const Locale('en'));
  });

  test('factory reset returns the language to the device default', () async {
    deviceLocales(const [Locale('en', 'US')]);
    final settings = SettingsProvider();
    await settings.setLocale(const Locale('tr'));
    expect(settings.locale, const Locale('tr'));

    await settings.factoryReset();

    expect(settings.locale, const Locale('en'));
    expect(Hive.box('settings').get('locale'), isNull);
  });
}
