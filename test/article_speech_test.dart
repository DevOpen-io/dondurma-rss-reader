import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_speech.dart';

/// Speaks nothing; each utterance finishes when the test says so, or ends
/// early when stopped — as the platform engine does.
class _FakeEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? _current;
  var stops = 0;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    return (_current = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    stops++;
    final current = _current;
    _current = null;
    if (current != null && !current.isCompleted) current.complete();
  }

  Future<void> finishOne() async {
    final current = _current;
    _current = null;
    current?.complete();
    await Future<void>.delayed(Duration.zero);
  }
}

FeedItem _item(String id) => FeedItem(
  id: id,
  siteName: 'Site',
  title: 'Title $id',
  description: '',
  feedUrl: 'https://site.test/feed',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('speechParts', () {
    test('title first, then one part per block, markup and blanks dropped', () {
      final parts = speechParts(
        'A headline',
        '<h2>Intro</h2><p>First <b>bold</b> line.</p><p> </p>'
            '<ul><li>One</li><li>Two</li></ul><figure><img src="x">'
            '<figcaption>Caption</figcaption></figure>'
            '<script>var x = 1;</script>',
      );
      expect(parts, [
        'A headline',
        'Intro',
        'First bold line.',
        'One',
        'Two',
        'Caption',
      ]);
    });

    test('media fallbacks and tables are not read; asides are blocks', () {
      expect(
        speechParts(
          'T',
          'Lead<aside>Note</aside>More'
              '<video>Your browser does not support video.</video>'
              '<table><tr><td>cell</td></tr></table>',
        ),
        ['T', 'Lead', 'Note', 'More'],
      );
    });

    test('text outside blocks is still read', () {
      expect(speechParts('T', 'Plain text<br>second line'), [
        'T',
        'Plain text second line',
      ]);
    });

    test('a long paragraph is split at sentence ends under the limit', () {
      final sentence = '${'word ' * 60}end. ';
      final parts = speechParts('T', '<p>${sentence * 30}</p>');
      expect(parts.length, greaterThan(2));
      for (final part in parts) {
        expect(part.length, lessThanOrEqualTo(speechPartLimit));
      }
      expect(parts.skip(1).join(' '), (sentence * 30).trim());
    });
  });

  group('ArticleSpeech', () {
    late _FakeEngine engine;
    late ArticleSpeech speech;

    setUp(() {
      engine = _FakeEngine();
      speech = ArticleSpeech(engine: engine);
    });

    test('reads every part in order, then goes idle', () async {
      await speech.play(_item('a'), '<p>One.</p><p>Two.</p>');
      expect(speech.stateFor(_item('a')), SpeechState.playing);
      await engine.finishOne();
      await engine.finishOne();
      await engine.finishOne();

      expect(engine.spoken, ['Title a', 'One.', 'Two.']);
      expect(speech.stateFor(_item('a')), SpeechState.idle);
    });

    test('pause holds the part, resume reads it again and goes on', () async {
      await speech.play(_item('a'), '<p>One.</p><p>Two.</p>');
      await engine.finishOne(); // Title done, "One." starts.
      await speech.pause();
      expect(speech.stateFor(_item('a')), SpeechState.paused);
      expect(engine.spoken, ['Title a', 'One.']);

      await speech.play(_item('a'), '<p>One.</p><p>Two.</p>');
      await engine.finishOne();
      await engine.finishOne();

      expect(engine.spoken, ['Title a', 'One.', 'One.', 'Two.']);
      expect(speech.stateFor(_item('a')), SpeechState.idle);
    });

    test('another article stops the first one', () async {
      await speech.play(_item('a'), '<p>One.</p>');
      await speech.play(_item('b'), '<p>Other.</p>');

      expect(speech.stateFor(_item('a')), SpeechState.idle);
      expect(speech.stateFor(_item('b')), SpeechState.playing);
      await engine.finishOne();
      expect(engine.spoken, ['Title a', 'Title b', 'Other.']);
    });

    test('stop ends reading and nothing more is spoken', () async {
      await speech.play(_item('a'), '<p>One.</p><p>Two.</p>');
      await speech.stop();
      await engine.finishOne();

      expect(engine.spoken, ['Title a']);
      expect(speech.stateFor(_item('a')), SpeechState.idle);
      expect(engine.stops, greaterThan(0));
    });

    test('stopIfNot keeps the article being read and stops others', () async {
      await speech.play(_item('a'), '<p>One.</p>');
      await speech.stopIfNot(_item('a'));
      expect(speech.stateFor(_item('a')), SpeechState.playing);
      await speech.stopIfNot(_item('b'));
      expect(speech.stateFor(_item('a')), SpeechState.idle);
    });
  });

  test('an engine failure ends reading instead of hanging', () async {
    final speech = ArticleSpeech(engine: _FailingEngine());
    await speech.play(_item('a'), '<p>One.</p>');
    await Future<void>.delayed(Duration.zero);
    expect(speech.stateFor(_item('a')), SpeechState.idle);
  });

  testWidgets('a speak the platform never answers fails instead of hanging', (
    tester,
  ) async {
    // Android with the speech engine missing or disabled: flutter_tts parks
    // the call until an engine binds, which never happens.
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) => call.method == 'speak'
          ? Completer<Object?>().future
          : Future.value(1),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    final speech = ArticleSpeech();
    await speech.play(_item('a'), '<p>One.</p>');
    expect(speech.stateFor(_item('a')), SpeechState.playing);
    await tester.pump(const Duration(seconds: 30));
    expect(speech.stateFor(_item('a')), SpeechState.idle);
  });

  testWidgets('a late answer to an earlier speak leaves the next one alone', (
    tester,
  ) async {
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var speaks = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call.method);
      // The first speak is parked; the engine accepts the ones after it.
      if (call.method == 'speak' && speaks++ == 0) {
        return Completer<Object?>().future;
      }
      return Future.value(1);
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    final speech = ArticleSpeech();
    await speech.play(_item('a'), '<p>One.</p>');
    await speech.play(_item('b'), '<p>Other.</p>');
    final afterSwitch = calls.length;
    // The parked speak of the first article times out now.
    await tester.pump(const Duration(seconds: 30));

    expect(speech.stateFor(_item('b')), SpeechState.playing);
    expect(calls.skip(afterSwitch), isNot(contains('stop')));
  });

  test('controls are offered where an engine exists', () {
    for (final (platform, supported) in [
      (TargetPlatform.android, true),
      (TargetPlatform.iOS, true),
      (TargetPlatform.windows, true),
      (TargetPlatform.macOS, true),
      (TargetPlatform.linux, false),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(ArticleSpeech.supported, supported, reason: '$platform');
    }
    debugDefaultTargetPlatformOverride = null;
  });
}

class _FailingEngine implements SpeechEngine {
  @override
  Future<void> speak(String text) => Future.error(StateError('no engine'));

  @override
  Future<void> stop() async {}
}
