import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;

import '../models/feed_item.dart';
import '../utils/app_toast.dart';
import '../utils/platform_caps.dart';
import 'speech_language.dart';

enum SpeechState { idle, playing, paused }

/// The device speech engine as [ArticleSpeech] uses it: [speak] completes
/// when the utterance ends or is stopped, and fails when the engine does.
abstract interface class SpeechEngine {
  /// The BCP-47 tags the engine speaks; empty when it cannot tell.
  Future<List<String>> availableLanguages();

  /// Speaks in [tag] from the next utterance on; null is the device's
  /// default voice. False when the engine refused it.
  Future<bool> setLanguage(String? tag);

  Future<void> speak(String text);
  Future<void> stop();
}

/// flutter_tts does not complete an awaited speak on every platform when
/// the utterance is cancelled or fails (iOS cancel, Android error), so
/// completion comes from its handlers instead, and [stop] settles it too.
class _FlutterTtsEngine implements SpeechEngine {
  _FlutterTtsEngine() {
    _tts
      ..setCompletionHandler(_settle)
      ..setCancelHandler(_settle)
      ..setErrorHandler((message) => _settle(message));
    if (PlatformCaps.isIOS) {
      // Keeps speaking with the silent switch on and the screen locked
      // (with the audio background mode in Info.plist).
      unawaited(
        _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, const [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ], IosTextToSpeechAudioMode.spokenAudio),
      );
    }
  }

  final _tts = FlutterTts();
  Completer<void>? _utterance;

  /// How long speak may take to be accepted. On Android with the engine
  /// missing or disabled flutter_tts parks the call until an engine binds,
  /// which never happens; binding a working engine takes a second or two.
  static const _acceptTimeout = Duration(seconds: 10);

  /// Set when a call timed out: the steps after it in the same attempt
  /// (languages, language, speak) give up at once instead of each waiting
  /// out its own timeout. The next attempt tries the engine afresh.
  bool _stalled = false;

  void _settle([Object? error]) {
    final utterance = _utterance;
    _utterance = null;
    if (utterance == null || utterance.isCompleted) return;
    error == null ? utterance.complete() : utterance.completeError(error);
  }

  @override
  Future<void> speak(String text) {
    _settle();
    if (_stalled) {
      _stalled = false;
      return Future.error('speech engine not answering');
    }
    final utterance = _utterance = Completer<void>();
    // A late answer to an earlier speak must not end the current one.
    bool current() => identical(_utterance, utterance);
    unawaited(
      _tts
          .speak(text)
          .timeout(
            _acceptTimeout,
            onTimeout: () {
              // A call parked behind an engine still binding runs before
              // this stop, so a late bind does not start reading.
              if (current()) unawaited(_tts.stop());
              return 0;
            },
          )
          .then(
            (result) {
              // 0 means the engine refused the utterance outright.
              if (result == 0 && current()) _settle('speak refused');
            },
            onError: (Object error) {
              if (current()) _settle(error);
            },
          ),
    );
    return utterance.future;
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _settle();
  }

  // Both are parked like speak while no engine is bound; on timeout they
  // just give up, so the speak after them fails as it would alone.
  @override
  Future<List<String>> availableLanguages() async {
    if (_stalled) return const [];
    try {
      final languages = await _tts.getLanguages.timeout(_acceptTimeout);
      return languages is List
          ? languages.whereType<String>().toList()
          : const [];
    } catch (error) {
      if (error is TimeoutException) _stalled = true;
      debugPrint('Read aloud languages failed: $error');
      return const [];
    }
  }

  @override
  Future<bool> setLanguage(String? tag) async {
    if (_stalled) return false;
    try {
      if (tag != null) {
        return await _tts.setLanguage(tag).timeout(_acceptTimeout) == 1;
      }
      // Android's default voice carries the device language; iOS and
      // Windows keep the last language, so ask for the device's again.
      if (PlatformCaps.isAndroid) {
        return await _tts.clearVoice().timeout(_acceptTimeout) == 1;
      }
      final device = PlatformDispatcher.instance.locale.toLanguageTag();
      return await _tts.setLanguage(device).timeout(_acceptTimeout) == 1;
    } catch (error) {
      if (error is TimeoutException) _stalled = true;
      debugPrint('Read aloud language $tag failed: $error');
      return false;
    }
  }
}

/// Reads one article aloud with the device's own speech engine — offline,
/// no account (#66). One reader for the app: starting another article
/// stops the last one. Pausing keeps the current part; resuming reads that
/// part again and goes on.
class ArticleSpeech extends ChangeNotifier {
  ArticleSpeech({SpeechEngine? engine}) : _engineOverride = engine;

  /// The app's reader; tests swap in one with a fake engine.
  static ArticleSpeech instance = ArticleSpeech();

  /// Platforms with an engine flutter_tts drives; elsewhere (Linux) the
  /// controls are hidden.
  static bool get supported =>
      PlatformCaps.isAndroid ||
      PlatformCaps.isIOS ||
      PlatformCaps.isMacOS ||
      PlatformCaps.isWindows;

  final SpeechEngine? _engineOverride;
  SpeechEngine? _engineInstance;
  SpeechEngine get _engine =>
      _engineInstance ??= _engineOverride ?? _FlutterTtsEngine();

  (String, String)? _article;
  List<String> _parts = const [];
  String? _detected;
  String? _fallback;
  String? _chosen;
  String? _failureMessage;
  List<String>? _offered;
  int _index = 0;
  SpeechState _state = SpeechState.idle;
  // Bumped by pause/stop: a reading loop of an older run ends quietly.
  int _run = 0;
  AppLifecycleListener? _lifecycle;

  SpeechState stateFor(FeedItem item) =>
      _article == (item.feedUrl, item.id) ? _state : SpeechState.idle;

  /// The language of the article being read when none is chosen: detected
  /// from its text, else the app's.
  String? get automaticLanguage => _detected ?? _fallback;

  /// The language chosen for the article being read; null detects it.
  String? get chosenLanguage => _chosen;

  /// The language the article being read is spoken in.
  String? get language => _chosen ?? automaticLanguage;

  /// The engine's language tags, asked once it has answered with some.
  Future<List<String>> languages() async {
    final offered = _offered ?? await _engine.availableLanguages();
    if (offered.isNotEmpty) _offered = offered;
    return offered;
  }

  /// Starts reading [item] (its title, then the text of [html]) or resumes
  /// it where it was paused. It is spoken in [language] when set, else in
  /// the language detected from its text, else in [fallbackLanguage] (the
  /// app's). When the engine fails, reading stops and [failureMessage] is
  /// shown.
  Future<void> play(
    FeedItem item,
    String html, {
    String? failureMessage,
    String? language,
    String? fallbackLanguage,
  }) async {
    final key = (item.feedUrl, item.id);
    if (_article != key) {
      await _halt();
      _article = key;
      _parts = speechParts(item.title, html);
      _index = 0;
      final text = _parts.join(' ');
      _detected = detectLanguage(
        text.length > 2000 ? text.substring(0, 2000) : text,
      );
      _fallback = fallbackLanguage;
      _chosen = language;
    } else if (_state == SpeechState.playing) {
      return;
    }
    _failureMessage = failureMessage;
    // Reading goes on with the screen off; it ends with the app.
    _lifecycle ??= AppLifecycleListener(onDetach: () => unawaited(stop()));
    _state = SpeechState.playing;
    notifyListeners();
    await _start(++_run);
  }

  /// Reads the article being read in [code] from now on (null detects
  /// it): the current part starts again in it.
  Future<void> chooseLanguage(String? code) async {
    final article = _article;
    if (article == null || code == _chosen) return;
    _chosen = code;
    notifyListeners();
    if (_state != SpeechState.playing) return;
    _run++;
    await _engine.stop();
    if (_article != article || _state != SpeechState.playing) return;
    await _start(++_run);
  }

  /// Sets the engine's language, then reads from the current part on; it
  /// returns once the first part is handed to the engine.
  Future<void> _start(int run) async {
    final code = language;
    final tag = code == null ? null : resolveSpeechTag(code, await languages());
    if (run != _run) return;
    // A language the engine lacks or refuses reads in the default voice
    // rather than not at all.
    if (tag == null || !await _engine.setLanguage(tag)) {
      if (run != _run) return;
      await _engine.setLanguage(null);
    }
    if (run != _run) return;
    unawaited(_read(run, _failureMessage));
  }

  Future<void> _read(int run, String? failureMessage) async {
    try {
      while (run == _run && _index < _parts.length) {
        await _engine.speak(_parts[_index]);
        if (run != _run) return;
        _index++;
      }
    } catch (error) {
      debugPrint('Read aloud failed: $error');
      if (run == _run && failureMessage != null) {
        showAppToast(failureMessage, type: AppToastType.error);
      }
    }
    if (run != _run) return;
    _article = null;
    _state = SpeechState.idle;
    notifyListeners();
  }

  Future<void> pause() async {
    if (_state != SpeechState.playing) return;
    _run++;
    _state = SpeechState.paused;
    notifyListeners();
    await _engine.stop();
  }

  Future<void> stop() async {
    if (_article == null) return;
    await _halt();
    notifyListeners();
  }

  /// Stops reading unless [item] is the article being read — for a page
  /// that is left or replaced by another one.
  Future<void> stopIfNot(FeedItem item) async {
    if (_article != null && _article != (item.feedUrl, item.id)) {
      await stop();
    }
  }

  Future<void> _halt() async {
    final speaking = _state == SpeechState.playing;
    _run++;
    _article = null;
    _parts = const [];
    _state = SpeechState.idle;
    if (speaking) await _engine.stop();
  }
}

/// Longest part handed to the engine; Android's input limit is ~4000.
const speechPartLimit = 3500;

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'ul', 'ol', //
  'blockquote', 'pre', 'figure', 'figcaption', 'section', 'article',
  'header', 'footer', 'main', 'aside', 'nav', 'details', 'summary',
  'address', 'dl', 'dt', 'dd', 'hr',
};
// Never shown as text by the reader: code, media fallbacks and tables
// (no table rendering in the article view).
const _skipTags = {
  'script', 'style', 'noscript', 'template', 'svg', 'video', 'audio', //
  'iframe', 'object', 'embed', 'table',
};

/// What is read aloud: the title, then the text of each block of [html]
/// as its own part, long blocks split at sentence ends.
@visibleForTesting
List<String> speechParts(String title, String html) {
  final parts = <String>[];
  final buffer = StringBuffer();
  void flush() {
    final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    buffer.clear();
    if (text.isNotEmpty) parts.addAll(_fit(text));
  }

  void walk(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }
    final tag = node is dom.Element ? node.localName : null;
    if (_skipTags.contains(tag)) return;
    if (tag == 'br') {
      buffer.write(' ');
      return;
    }
    final block = _blockTags.contains(tag);
    if (block) flush();
    for (final child in node.nodes) {
      walk(child);
    }
    if (block) flush();
  }

  final doc = parse(html);
  walk(doc.body ?? doc);
  flush();
  final heading = title.trim();
  return [if (heading.isNotEmpty) ..._fit(heading), ...parts];
}

/// Splits [text] into parts under [speechPartLimit], at sentence ends
/// where it can, else at a space.
List<String> _fit(String text) {
  if (text.length <= speechPartLimit) return [text];
  final parts = <String>[];
  var current = '';
  for (var sentence in text.split(RegExp(r'(?<=[.!?…؟])\s+|(?<=[。！？])\s*'))) {
    while (sentence.length > speechPartLimit) {
      final cut = sentence.lastIndexOf(' ', speechPartLimit);
      var at = cut > 0 ? cut : speechPartLimit;
      // Never between the halves of a surrogate pair.
      if (cut <= 0 && _isHighSurrogate(sentence.codeUnitAt(at - 1))) at--;
      if (current.isNotEmpty) {
        parts.add(current);
        current = '';
      }
      parts.add(sentence.substring(0, at).trim());
      sentence = sentence.substring(at).trim();
    }
    if (current.isEmpty) {
      current = sentence;
    } else if (current.length + 1 + sentence.length <= speechPartLimit) {
      current = '$current $sentence';
    } else {
      parts.add(current);
      current = sentence;
    }
  }
  if (current.isNotEmpty) parts.add(current);
  return parts;
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
