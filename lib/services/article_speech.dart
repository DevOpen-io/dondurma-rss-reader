import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;

import '../models/feed_item.dart';
import '../utils/app_toast.dart';
import '../utils/platform_caps.dart';

enum SpeechState { idle, playing, paused }

/// The device speech engine as [ArticleSpeech] uses it: [speak] completes
/// when the utterance ends or is stopped, and fails when the engine does.
abstract interface class SpeechEngine {
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

  void _settle([Object? error]) {
    final utterance = _utterance;
    _utterance = null;
    if (utterance == null || utterance.isCompleted) return;
    error == null ? utterance.complete() : utterance.completeError(error);
  }

  @override
  Future<void> speak(String text) {
    _settle();
    final utterance = _utterance = Completer<void>();
    unawaited(
      _tts.speak(text).then((result) {
        // 0 means the engine refused the utterance outright.
        if (result == 0) _settle('speak refused');
      }, onError: _settle),
    );
    return utterance.future;
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _settle();
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
  int _index = 0;
  SpeechState _state = SpeechState.idle;
  // Bumped by pause/stop: a reading loop of an older run ends quietly.
  int _run = 0;
  AppLifecycleListener? _lifecycle;

  SpeechState stateFor(FeedItem item) =>
      _article == (item.feedUrl, item.id) ? _state : SpeechState.idle;

  /// Starts reading [item] (its title, then the text of [html]) or resumes
  /// it where it was paused. When the engine fails, reading stops and
  /// [failureMessage] is shown.
  Future<void> play(
    FeedItem item,
    String html, {
    String? failureMessage,
  }) async {
    final key = (item.feedUrl, item.id);
    if (_article != key) {
      await _halt();
      _article = key;
      _parts = speechParts(item.title, html);
      _index = 0;
    } else if (_state == SpeechState.playing) {
      return;
    }
    // Reading goes on with the screen off; it ends with the app.
    _lifecycle ??= AppLifecycleListener(onDetach: () => unawaited(stop()));
    _state = SpeechState.playing;
    notifyListeners();
    unawaited(_read(++_run, failureMessage));
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
