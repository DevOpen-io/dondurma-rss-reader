import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/shared_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('finds the link in what browsers and apps share', () {
    expect(sharedUrl('https://site.test/post'), 'https://site.test/post');
    expect(
      sharedUrl('A headline\nhttps://site.test/a?b=1#c'),
      'https://site.test/a?b=1#c',
    );
    expect(
      sharedUrl('Read this (https://site.test/x).'),
      'https://site.test/x',
    );
    expect(sharedUrl('just words, no link'), isNull);
    expect(sharedUrl('ftp://site.test/file'), isNull);
  });

  test('the launch text and later shares land in pending', () async {
    const channel = MethodChannel('io.devopen.dondurma/share');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'initialText' ? 'https://a.test/' : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await SharedLinks.listen();
    expect(SharedLinks.pending.value, 'https://a.test/');

    SharedLinks.pending.value = null;
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('shared', 'later https://b.test/'),
      ),
      (_) {},
    );
    expect(SharedLinks.pending.value, 'later https://b.test/');
  });
}
