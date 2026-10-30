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

  /// The engine's languages, the ones it refuses, and every call in order.
  List<String> offered = const ['en-US', 'en-GB', 'tr-TR', 'de-DE'];
  Set<String> refused = const {};
  final calls = <String>[];

  @override
  Future<List<String>> availableLanguages() async => offered;

  @override
  Future<bool> setLanguage(String? tag) async {
    calls.add('language $tag');
    return !refused.contains(tag);
  }

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    calls.add('speak $text');
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

    const turkish =
        '<p>Merkez Bankası faiz kararını açıkladı ve bu karar için yeni bir '
        'açıklama yapılacak.</p>';

    test('reads in the language detected from the article', () async {
      await speech.play(_item('a'), turkish, fallbackLanguage: 'en');
      expect(engine.calls.take(2), ['language tr-TR', 'speak Title a']);
      expect(speech.automaticLanguage, 'tr');
      expect(speech.language, 'tr');
    });

    test('text too short to tell reads in the app language', () async {
      await speech.play(_item('a'), '<p>Ok.</p>', fallbackLanguage: 'en');
      expect(engine.calls.first, 'language en-US');
      expect(speech.automaticLanguage, 'en');
    });

    test('the feed\'s chosen language wins over detection', () async {
      await speech.play(_item('a'), turkish, language: 'de');
      expect(engine.calls.first, 'language de-DE');
      expect(speech.chosenLanguage, 'de');
      expect(speech.automaticLanguage, 'tr');
    });

    test('a language the engine lacks reads with the default voice', () async {
      engine.offered = const ['en-US'];
      await speech.play(_item('a'), turkish);
      expect(engine.calls.take(2), ['language null', 'speak Title a']);
    });

    test('a refused language falls back to the default voice', () async {
      engine.refused = {'tr-TR'};
      await speech.play(_item('a'), turkish);
      expect(engine.calls.take(3), [
        'language tr-TR',
        'language null',
        'speak Title a',
      ]);
    });

    test('choosing a language reads the current part again in it', () async {
      await speech.play(_item('a'), turkish);
      await engine.finishOne(); // Title done, the paragraph starts.
      engine.calls.clear();
      await speech.chooseLanguage('en');
      await Future<void>.delayed(Duration.zero);

      expect(engine.stops, 1);
      expect(engine.calls, ['language en-US', 'speak ${engine.spoken[1]}']);
      expect(speech.language, 'en');
      expect(speech.stateFor(_item('a')), SpeechState.playing);

      await speech.chooseLanguage(null);
      expect(speech.language, 'tr');
    });

    test('choosing while paused applies on resume', () async {
      await speech.play(_item('a'), turkish);
      await speech.pause();
      engine.calls.clear();
      await speech.chooseLanguage('de');
      expect(engine.calls, isEmpty);
      expect(speech.stateFor(_item('a')), SpeechState.paused);

      await speech.play(_item('a'), turkish);
      expect(engine.calls.first, 'language de-DE');
    });

    test('the engine\'s languages, asked once', () async {
      var asked = 0;
      final counting = _CountingEngine(() => asked++);
      final speech = ArticleSpeech(engine: counting);
      expect(await speech.languages(), ['tr-TR']);
      expect(await speech.languages(), ['tr-TR']);
      expect(asked, 1);
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

  testWidgets('with no engine at all the failure comes after one wait, '
      'not one per step', (tester) async {
    // Languages, language and speak are all parked by flutter_tts.
    const channel = MethodChannel('flutter_tts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) => call.method == 'stop'
          ? Future.value(1)
          : Completer<Object?>().future,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    final speech = ArticleSpeech();
    unawaited(
      speech.play(_item('a'), '<p>One.</p>', fallbackLanguage: 'tr'),
    );
    await tester.pump();
    expect(speech.stateFor(_item('a')), SpeechState.playing);
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
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
  Future<List<String>> availableLanguages() async => const [];

  @override
  Future<bool> setLanguage(String? tag) async => false;

  @override
  Future<void> speak(String text) => Future.error(StateError('no engine'));

  @override
  Future<void> stop() async {}
}

class _CountingEngine extends _FailingEngine {
  _CountingEngine(this.onAsk);

  final void Function() onAsk;

  @override
  Future<List<String>> availableLanguages() async {
    onAsk();
    return const ['tr-TR'];
  }
}
