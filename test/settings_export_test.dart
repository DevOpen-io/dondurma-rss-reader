import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/providers/bookmark_provider.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';
import 'package:ice_cream_rss_reader/providers/settings_provider.dart';
import 'package:ice_cream_rss_reader/providers/subscription_provider.dart';
import 'package:ice_cream_rss_reader/screens/settings_screen.dart';
import 'package:ice_cream_rss_reader/utils/app_toast.dart';

/// Counts native save dialogs; the user always cancels.
class _FakeFileSelector extends FileSelectorPlatform {
  int saveDialogs = 0;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    saveDialogs++;
    return null;
  }
}

Future<void> _frames(WidgetTester tester) async {
  // Settings keeps an indeterminate indicator alive: bounded pumps only.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const files = MethodChannel('io.devopen.dondurma/files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> saves;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('settings_export');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    for (final channel in const [
      MethodChannel('dev.fluttercommunity.plus/connectivity'),
      MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('feeds');
    await Hive.openBox('bookmarks');
    final subs = SubscriptionProvider();
    await subs.addFeed('https://x.test/rss', 'X', 'News');
  });

  setUp(() {
    saves = [];
    messenger.setMockMethodCallHandler(files, (call) async {
      saves.add(call);
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(files, null));

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup.
    }
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
            ChangeNotifierProvider(create: (_) => BookmarkProvider()),
            ChangeNotifierProxyProvider3<
              SubscriptionProvider,
              SettingsProvider,
              BookmarkProvider,
              FeedProvider
            >(
              create: (_) => FeedProvider(),
              update: (_, sub, settings, bm, feed) =>
                  feed!..update(sub, settings, bm),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
    });
    await _frames(tester);
  }

  for (final (row, name) in [
    ('Export backup', 'dondurma-backup-'),
    ('Export Subscriptions (OPML)', 'dondurma_subscriptions.opml'),
  ]) {
    testWidgets('$row offers saving to the device on Android', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(find.text(row));
      await _frames(tester);
      expect(find.text('Share'), findsOneWidget);
      await tester.tap(find.text('Save to device'));
      await _frames(tester);

      final args = saves.single.arguments as Map<Object?, Object?>;
      expect(args['name'] as String, startsWith(name));
      expect(appToastController.current?.type, AppToastType.success);
      // The toast's timer would outlive the tree.
      appToastController.dismiss();
    });
  }

  testWidgets('desktop export opens the native save dialog directly', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final original = FileSelectorPlatform.instance;
    final picker = _FakeFileSelector();
    FileSelectorPlatform.instance = picker;
    await pumpSettings(tester);

    await tester.tap(find.text('Export backup'));
    await _frames(tester);

    expect(find.text('Save to device'), findsNothing);
    expect(picker.saveDialogs, 1);
    expect(saves, isEmpty);
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });
}
