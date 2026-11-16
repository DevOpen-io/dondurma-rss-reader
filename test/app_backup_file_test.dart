import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:ice_cream_rss_reader/services/app_backup.dart';
import 'package:ice_cream_rss_reader/services/opml_service.dart';

/// Stands in for the native open/save dialogs.
class _FakeFileSelector extends FileSelectorPlatform {
  XFile? picked;
  String? savePath;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => picked;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => savePath == null ? null : FileSaveLocation(savePath!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform original;
  late _FakeFileSelector picker;
  late Directory root;

  setUp(() async {
    original = FileSelectorPlatform.instance;
    picker = _FakeFileSelector();
    FileSelectorPlatform.instance = picker;
    root = await Directory.systemTemp.createTemp('backup-file-');
  });
  tearDown(() async {
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  group('pickBackupFile', () {
    // The Android picker hands over the file's bytes; `XFile.readAsString`
    // decodes those as Latin-1 whatever encoding it is given.
    test('reads a picked file as UTF-8', () async {
      const json = '{"category":"Dünya Haberleri","tag":"çay ☕"}';
      picker.picked = XFile.fromData(utf8.encode(json), name: 'b.json');

      expect(await pickBackupFile(), json);
    });

    test('is null when the user cancels', () async {
      expect(await pickBackupFile(), isNull);
    });
  });

  test('OPML import reads a picked file as UTF-8', () async {
    picker.picked = XFile.fromData(
      utf8.encode(
        '<opml version="2.0"><body><outline text="Gündem">'
        '<outline text="Haber Türk" xmlUrl="https://h.test/rss" />'
        '</outline></body></opml>',
      ),
      name: 'subs.opml',
    );

    final subs = await OpmlService().importOpml();

    expect(subs.single.name, 'Haber Türk');
    expect(subs.single.category, 'Gündem');
  });

  group('saveBackupFile on desktop', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);

    test('writes the chosen file, adding .json', () async {
      picker.savePath = '${root.path}/mine';

      expect(await saveBackupFile('{"ü":1}'), isTrue);
      expect(File('${root.path}/mine.json').readAsStringSync(), '{"ü":1}');
    });

    test('is null when the user cancels', () async {
      expect(await saveBackupFile('{}'), isNull);
    });

    test('is false when the file cannot be written', () async {
      picker.savePath = '${root.path}/missing/dir/b.json';

      expect(await saveBackupFile('{}'), isFalse);
    });
  });

  // iPad presents the share sheet as a popover; without an anchor inside
  // the screen the plugin fails and the export reports an error.
  test('the share sheet gets the anchor it is given', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const share = MethodChannel('dev.fluttercommunity.plus/share');
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    Map<Object?, Object?>? sent;
    messenger.setMockMethodCallHandler(share, (call) async {
      sent = call.arguments as Map<Object?, Object?>;
      return 'done';
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(share, null);
    });

    final saved = await saveBackupFile(
      '{}',
      shareOrigin: const Rect.fromLTWH(0, 100, 400, 60),
    );

    expect(saved, isTrue);
    expect(sent, containsPair('originY', 100.0));
    expect(sent, containsPair('originWidth', 400.0));
    expect(sent, containsPair('originHeight', 60.0));
  });

  // Android: the system "save as" dialog (Storage Access Framework) through
  // the app's own channel; the share sheet stays the other option.
  group('save to device on Android', () {
    const files = MethodChannel('io.devopen.dondurma/files');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    Object? Function() reply = () => true;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = [];
      reply = () => true;
      messenger.setMockMethodCallHandler(files, (call) async {
        calls.add(call);
        return reply();
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(files, null));

    test('a backup goes to the file the user picks', () async {
      expect(await saveBackupFile('{"ü":1}', toDevice: true), isTrue);

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, 'saveFile');
      expect(
        args['name'],
        matches(RegExp(r'^dondurma-backup-\d{4}-\d{2}-\d{2}\.json$')),
      );
      expect(args['mimeType'], 'application/json');
      expect(utf8.decode(args['bytes'] as Uint8List), '{"ü":1}');
    });

    test('a cancelled save is null, a failed one false', () async {
      reply = () => null;
      expect(await saveBackupFile('{}', toDevice: true), isNull);
      reply = () => throw PlatformException(code: 'unavailable');
      expect(await saveBackupFile('{}', toDevice: true), isFalse);
    });

    test('OPML export saves the subscriptions file', () async {
      final subs = [
        FeedSubscription(
          url: 'https://h.test/rss',
          name: 'Haber Türk',
          category: 'Gündem',
        ),
      ];
      expect(await OpmlService().exportOpml(subs, toDevice: true), isTrue);

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['name'], 'dondurma_subscriptions.opml');
      expect(args['mimeType'], 'text/x-opml');
      expect(utf8.decode(args['bytes'] as Uint8List), contains('Haber Türk'));

      reply = () => null;
      expect(await OpmlService().exportOpml(subs, toDevice: true), isNull);
    });
  });
}
