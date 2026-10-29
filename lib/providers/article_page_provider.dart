import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../models/feed_item.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/article_identity.dart';
import '../services/article_media_store.dart';
import '../services/article_record_store.dart';
import '../services/article_status.dart';
import '../services/full_text_extraction_service.dart';

/// Per-article-page state managed as a [ChangeNotifier].
///
/// Each article page in the [PageView] gets its own scoped instance via
/// `ChangeNotifierProvider`. Replaces the previous `setState`-based approach
/// in `_ArticlePageState`.
class ArticlePageProvider extends ChangeNotifier {
  final FeedItem item;
  final FullTextExtractionService _extractionService =
      FullTextExtractionService();

  // ---------------------------------------------------------------------------
  // State fields
  // ---------------------------------------------------------------------------

  /// Whether full-text mode is active (either via per-feed default or manual).
  bool _fullTextActive = false;
  bool get fullTextActive => _fullTextActive;

  /// Whether a full-text fetch is currently in progress.
  bool _isLoadingFullText = false;
  bool get isLoadingFullText => _isLoadingFullText;

  /// The extracted full-text HTML, if successfully fetched.
  String? _fullTextContent;
  String? get fullTextContent => _fullTextContent;

  /// Whether the extraction was attempted and failed (manual trigger).
  bool _fullTextFailed = false;
  bool get fullTextFailed => _fullTextFailed;
  bool _fullTextFailureUnreported = false;

  /// True once per manual full-text failure, so a listener reports it once
  /// although later notifications keep [fullTextFailed] set.
  bool consumeFullTextFailure() {
    final unreported = _fullTextFailureUnreported;
    _fullTextFailureUnreported = false;
    return unreported;
  }

  /// Whether an auto-triggered extraction failed (shown as subtle notice, not snackbar).
  bool _autoFullTextFailed = false;
  bool get autoFullTextFailed => _autoFullTextFailed;

  /// The page gave nothing beyond the feed's body because that body is
  /// already the whole article (blogs that publish full posts): not a
  /// failure, and the reader says so instead of offering a retry.
  bool _feedHasFullArticle = false;
  bool get feedHasFullArticle => _feedHasFullArticle;

  /// Visible text from which a feed body counts as a whole article.
  static const _fullArticleLength = 1000;

  /// Whether the last activation was automatic (from per-feed/global default).
  bool _lastAttemptAutomatic = false;

  /// Set once [dispose] runs so async continuations skip [notifyListeners],
  /// which throws on a disposed [ChangeNotifier].
  bool _disposed = false;

  /// Whether the heavy Html widget is ready to render. Set to `true`
  /// after the first frame so the route transition animation is not blocked.
  bool _contentReady = false;
  bool get contentReady => _contentReady;

  /// Cached result of [preprocessHtml] for the current content source.
  String? _cachedDisplayContent;

  /// Cached reading-time estimate for the current content source.
  int? _cachedReadingMinutes;

  /// Reading progress (0.0 to 1.0). Uses [ValueNotifier] to avoid full
  /// rebuilds on every scroll tick.
  final ValueNotifier<double> readingProgress = ValueNotifier(0.0);

  /// The durable record's saved body, when one is ready on disk (#41).
  String? _savedBody;

  /// Whether [_savedBody] is extracted full text rather than the feed's
  /// own body — preparation's offline copy for full-text reading.
  bool _savedBodyExtracted = false;

  /// Durable-state summary for the status strip — null until [loadSavedCopy]
  /// resolves (or when no record exists).
  ArticleStatus? _recordStatus;
  ArticleStatus? get recordStatus => _recordStatus;

  /// Remote image URL → local `file://` path for media entries that are
  /// `ready` in the record manifest. Exposed so the HTML renderer can
  /// whitelist `file://` srcs — only paths this map produced are trusted
  /// (#41: feed HTML is untrusted input).
  Map<String, String> _localImages = const {};
  Map<String, String> get localImages => _localImages;

  /// True when the feed item has no current readable body and the saved
  /// copy is shown instead (#41 archived-copy rule).
  bool _archivedFallback = false;
  bool get usingArchivedCopy => _archivedFallback;

  /// True once [loadSavedCopy] finished its store read — distinguishes
  /// "still loading" from "verified absent" so a missing record is not
  /// flashed as a failed save (#41 honesty).
  bool _savedCopySettled = false;
  bool get savedCopyLoaded => _savedCopySettled;

  /// Monotonic guard: a superseded read discards its results so a slow
  /// earlier load can never overwrite a newer one.
  int _savedCopyGeneration = 0;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  ArticlePageProvider({required this.item});

  // ---------------------------------------------------------------------------
  // Durable saved copy (#41)
  // ---------------------------------------------------------------------------

  /// Loads this article's durable record once: the saved body, the status
  /// summary for the strip, and local paths for `ready` media entries.
  /// Injectable stores keep the method testable off-device.
  Future<void> loadSavedCopy({
    ArticleRecordStore? records,
    ArticleMediaStore? media,
  }) async {
    if (_savedCopySettled) return;
    final generation = ++_savedCopyGeneration;
    final store = records ?? ArticleRecordStore.of(Hive.box('feeds'));
    final mediaStore = media ?? ArticleMediaStore();
    ArticleRecord? record;
    try {
      // This source instance's own record — never another feed's copy of a
      // shared GUID.
      record = await store.read(ArticleRef.of(item));
    } catch (_) {
      // A store-level read error fails closed to "no offline claim".
      record = null;
    }
    if (_disposed || generation != _savedCopyGeneration) return;
    final previousBody = _savedBody;
    final previousImages = _localImages;
    _savedBody = null;
    _savedBodyExtracted = false;
    _recordStatus = null;
    _localImages = const {};
    _archivedFallback = false;
    if (record != null && !record.tombstoned) {
      // The durable body counts regardless of extraction state — the RSS
      // body survives a failed full-text attempt (#41 readability rule).
      if (record.body?.isNotEmpty ?? false) {
        _savedBody = record.body;
        _savedBodyExtracted = record.bodySource == 'extracted';
      }
      final local = <String, String>{};
      var checked = record;
      for (final entry in record.media.entries) {
        if (entry.value.state != MediaState.ready) continue;
        // Existence AND byte size — a truncated/vanished file must not be
        // rewritten in as "ready", and must not back a ready label either
        // (#41 verify-before-ready). I/O failures count as unverified.
        String? path;
        var verified = false;
        try {
          verified = await mediaStore.verify(entry.value);
          if (verified) path = await mediaStore.pathFor(entry.value.file);
        } catch (_) {
          verified = false;
        }
        if (_disposed || generation != _savedCopyGeneration) return;
        if (!verified || path == null) {
          final m = {...checked.media};
          final e = m[entry.key];
          if (e != null && e.state == MediaState.ready) {
            m[entry.key] = e.copyWith(state: MediaState.pending);
            checked = checked.copyWith(media: m);
          }
          continue;
        }
        local[entry.key] = 'file://$path';
      }
      _localImages = local;
      // The strip derives from the VERIFIED record — a manifest claiming
      // bytes the disk lacks never produces a ready label here, same rule
      // as the list surface's demote-repair.
      _recordStatus = ArticleStatus.fromRecord(checked);
      // Archived-copy rule: the feed item's own readable body wins; the
      // saved copy only takes over when the current body is absent (#41).
      final current = item.content;
      _archivedFallback =
          !item.isBookmarked &&
          (current == null || current.trim().isEmpty) &&
          _savedBody != null;
    }
    _savedCopySettled = true;
    // Re-render only when the shown body or its local files changed — a
    // refresh on every page re-activation would otherwise re-parse it.
    if (_savedBody != previousBody ||
        !mapEquals(_localImages, previousImages)) {
      _cachedDisplayContent = null;
      _cachedReadingMinutes = null;
    }
    notifyListeners();
  }

  /// Re-reads durable state after a manual preparation pass so the strip
  /// and media map reflect the new commits.
  Future<void> refreshSavedCopy({
    ArticleRecordStore? records,
    ArticleMediaStore? media,
  }) async {
    // Resetting the settled flag bumps the generation on the next load —
    // any read still in flight discards its stale result.
    _savedCopySettled = false;
    await loadSavedCopy(records: records, media: media);
  }

  // ---------------------------------------------------------------------------
  // Content ready
  // ---------------------------------------------------------------------------

  /// Called after the first frame to enable rendering of heavy content.
  void setContentReady() {
    _contentReady = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Full-text extraction
  // ---------------------------------------------------------------------------

  /// Checks per-feed and global settings to auto-activate full-text extraction.
  void checkAutoFullText(
    SubscriptionProvider subProvider,
    SettingsProvider settingsProvider,
  ) {
    if (_fullTextActive) return;
    if (subProvider.effectiveFullText(
      item.feedUrl,
      autoFullText: settingsProvider.autoFullText,
    )) {
      activateFullText(automatic: true);
    }
  }

  Future<void> activateFullText({bool automatic = false}) async {
    if (item.link.isEmpty || _disposed) return;

    _lastAttemptAutomatic = automatic;
    _fullTextActive = true;
    _fullTextFailed = false;
    _autoFullTextFailed = false;
    _feedHasFullArticle = false;
    _fullTextContent = null;
    _cachedDisplayContent = null;
    _cachedReadingMinutes = null;

    // Offline path: a prepared full-text copy renders instantly — unless it
    // is no more than the feed's excerpt; then the page is tried live.
    if (_savedBodyExtracted && _addsToFeedBody(_savedBody!)) {
      _fullTextContent = _savedBody;
      _isLoadingFullText = false;
      notifyListeners();
      return;
    }

    _isLoadingFullText = true;
    notifyListeners();

    var result = await _extractionService.extractFullText(
      item.link,
      forceRefresh: !automatic,
    );

    if (_disposed) return;

    // A "full text" that only repeats the excerpt (headline + summary, a
    // teaser page) is a failure, not a success showing the same text.
    if (result != null && result.isNotEmpty && !_addsToFeedBody(result)) {
      _extractionService.discard(item.link);
      result = null;
      _feedHasFullArticle =
          _displayText(_feedBody).trim().length >= _fullArticleLength;
    }

    _isLoadingFullText = false;
    // The reader drew the summary while the page loaded; what it shows now
    // is worked out again from the result.
    _cachedDisplayContent = null;
    _cachedReadingMinutes = null;
    if (_feedHasFullArticle) {
      _fullTextActive = false;
      _fullTextContent = null;
    } else if (result != null && result.isNotEmpty) {
      _fullTextContent = result;
      _fullTextFailed = false;
      _autoFullTextFailed = false;
    } else {
      _fullTextActive = false;
      _fullTextContent = null;
      if (_lastAttemptAutomatic) {
        _autoFullTextFailed = true;
        _fullTextFailed = false;
      } else {
        _fullTextFailed = true;
        _fullTextFailureUnreported = true;
        _autoFullTextFailed = false;
      }
    }
    notifyListeners();
  }

  /// Whether [html], as the reader would show it, gives more than the
  /// feed's own body for this item.
  bool _addsToFeedBody(String html) =>
      FullTextExtractionService.isMoreThanExcerpt(
        _displayText(html),
        _displayText(_feedBody),
      );

  String get _feedBody {
    final current = item.content;
    return current != null && current.trim().isNotEmpty
        ? current
        : item.description;
  }

  /// Visible text of [html] after the reader's own cleanup.
  String _displayText(String html) {
    final body = html_parser.parse(html).body;
    if (body == null) return '';
    _preprocessHtml(body);
    return body.text;
  }

  void deactivateFullText() {
    _lastAttemptAutomatic = false;
    _fullTextActive = false;
    _isLoadingFullText = false;
    _fullTextContent = null;
    _fullTextFailed = false;
    _autoFullTextFailed = false;
    _feedHasFullArticle = false;
    _cachedDisplayContent = null;
    _cachedReadingMinutes = null;
    notifyListeners();
  }

  void toggleFullText() {
    if (_fullTextActive) {
      deactivateFullText();
    } else {
      activateFullText();
    }
  }

  // ---------------------------------------------------------------------------
  // Scroll tracking for reading progress
  // ---------------------------------------------------------------------------

  /// Updates reading progress based on scroll position. Returns false
  /// so the notification continues to bubble.
  bool updateReadingProgress(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      if (metrics.maxScrollExtent > 0) {
        readingProgress.value = (metrics.pixels / metrics.maxScrollExtent)
            .clamp(0.0, 1.0);
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Content preprocessing & reading time (cached)
  // ---------------------------------------------------------------------------

  /// Returns the raw HTML to display. Priority (#41): a live extraction
  /// from this session; the saved copy when the item is a bookmark or has
  /// no current readable body of its own; the feed item's body last.
  String get rawContent {
    if (_fullTextContent != null) return _fullTextContent!;
    if (item.isBookmarked) {
      return _savedBody ?? item.content ?? item.description;
    }
    final current = item.content;
    if (current != null && current.trim().isNotEmpty) return current;
    if (_savedBody != null) return _savedBody!;
    return item.description;
  }

  String get displayContent {
    if (_cachedDisplayContent == null) _prepareContent();
    return _cachedDisplayContent!;
  }

  /// Estimated reading minutes of [rawContent], from the same parse.
  int get readingMinutes {
    if (_cachedReadingMinutes == null) _prepareContent();
    return _cachedReadingMinutes!;
  }

  static final _whitespace = RegExp(r'\s+');

  /// Parses [rawContent] once: reading time from its text as published,
  /// then the cleaned display HTML.
  void _prepareContent() {
    final raw = rawContent;
    final body = html_parser.parse(raw).body;
    final words = (body?.text ?? '')
        .split(_whitespace)
        .where((w) => w.isNotEmpty)
        .length;
    // Average reading speed: ~200 words/minute
    _cachedReadingMinutes = (words / 200).ceil();
    _cachedDisplayContent = body == null ? raw : _preprocessHtml(body);
  }

  // ---------------------------------------------------------------------------
  // HTML pre-processing
  // ---------------------------------------------------------------------------

  String _preprocessHtml(html_dom.Element body) {
    _removeRepeatedHeadline(body);
    _stripInlineStyles(body);
    _removeAdContent(body);
    _removeEmptyElements(body);
    _deduplicateImages(body);
    _groupConsecutiveImages(body);
    _rewriteLocalImages(body);

    return body.innerHtml;
  }

  /// Drops the page's own copy of the headline: the reader already shows
  /// the title above the text. A source suffix ("… - CNN") on either side
  /// still matches.
  void _removeRepeatedHeadline(html_dom.Element body) {
    String norm(String text) => text
        .toLowerCase()
        .replaceAll(RegExp(r'[‘’`´]'), "'")
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
    final title = norm(item.title);
    if (title.length < 8) return;
    final heading = body.querySelector('h1, h2');
    if (heading == null) return;
    final text = norm(heading.text);
    if (text.isEmpty) return;
    final (short, long) = text.length < title.length
        ? (text, title)
        : (title, text);
    if (long.contains(short) && short.length >= long.length * 0.6) {
      heading.remove();
    }
  }

  /// Points ready media entries at their durable local files so offline
  /// reading shows stored bytes instead of a dead remote URL (#41).
  /// Attribute-scoped — link hrefs, captions, and other markup sharing the
  /// URL string are never touched.
  void _rewriteLocalImages(html_dom.Element body) {
    if (_localImages.isEmpty) return;
    for (final img in body.querySelectorAll('img')) {
      final src = img.attributes['src'];
      final local = src == null ? null : _localImages[src];
      if (local != null) img.attributes['src'] = local;
    }
    for (final carousel in body.querySelectorAll('img-carousel')) {
      final raw = carousel.attributes['data-urls'];
      if (raw == null) continue;
      carousel.attributes['data-urls'] = raw
          .split('|')
          .map((u) => _localImages[u] ?? u)
          .join('|');
    }
  }

  // ----------- Inline style stripping -----------

  /// Removes inline `style`, `color`, `bgcolor`, `face`, and `size` attributes
  /// from every element so that the app's theme and user font settings are
  /// always respected, regardless of what the RSS source embeds.
  void _stripInlineStyles(html_dom.Element parent) {
    for (final el in parent.querySelectorAll('*')) {
      el.attributes.remove('style');
      el.attributes.remove('color');
      el.attributes.remove('bgcolor');
      el.attributes.remove('face');
      el.attributes.remove('size');
    }
  }

  // ----------- Ad / Promo removal -----------

  static final _adTextPattern = RegExp(
    r'(advertiser\s*content|native\s*ad|sponsored\s*content|'
    r'advertisement|promoted\s*content|follow\s*topics\s*and\s*authors|'
    r'read\s*our\s*recent\s*profile)',
    caseSensitive: false,
  );

  // `ad-` only at the start of a class word — inside one it is `head-`,
  // `lead-` or ntv.com.tr's `inread-` story wrapper.
  static final _adClassPattern = RegExp(
    r'((?<![a-z0-9])ad-|advert|sponsor|promo|native-ad|outbrain|taboola|'
    r'related-stories|rec-rail|story-rail|commerce|affiliate)',
    caseSensitive: false,
  );

  static const _adTextTags = {
    'div',
    'section',
    'aside',
    'p',
    'span',
    'h2',
    'h3',
    'h4',
  };

  void _removeAdContent(html_dom.Element parent) {
    // A wrapper holding most of the story is never an ad, whatever its
    // class lists (Future plc's `flw-article-sponsored-disclaimer`).
    final storyText = FullTextExtractionService.paragraphTextLength(parent);
    for (final el in parent.querySelectorAll('*').toList()) {
      final cls = el.attributes['class'] ?? '';
      final id = el.attributes['id'] ?? '';
      if ((_adClassPattern.hasMatch(cls) || _adClassPattern.hasMatch(id)) &&
          FullTextExtractionService.paragraphTextLength(el) * 2 <= storyText) {
        el.remove();
        continue;
      }

      if (_adTextTags.contains(el.localName)) {
        final text = el.text.trim();
        if (text.length < 200 && _adTextPattern.hasMatch(text)) {
          el.remove();
        }
      }
    }
  }

  // ----------- Empty element removal -----------

  void _removeEmptyElements(html_dom.Element parent) {
    const emptyTags = {'div', 'p', 'section', 'span', 'figure', 'figcaption'};
    for (final child in parent.children.toList()) {
      _removeEmptyElements(child);

      if (emptyTags.contains(child.localName) &&
          child.text.trim().isEmpty &&
          child.children.isEmpty &&
          child.getElementsByTagName('img').isEmpty) {
        child.remove();
        continue;
      }

      if (child.localName == 'li' &&
          child.text.trim().isEmpty &&
          child.getElementsByTagName('img').isEmpty) {
        child.remove();
        continue;
      }
    }

    for (final child in parent.children.toList()) {
      if ((child.localName == 'ul' || child.localName == 'ol') &&
          child.children.isEmpty) {
        child.remove();
      }
    }
  }

  // ----------- Image deduplication -----------

  void _deduplicateImages(html_dom.Element parent) {
    final heroUrl = item.imageUrl ?? '';
    final seen = <String>{};
    if (heroUrl.isNotEmpty) {
      seen.add(_normalizeImageUrl(heroUrl));
    }

    for (final img in parent.getElementsByTagName('img').toList()) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty) {
        img.remove();
        continue;
      }
      final norm = _normalizeImageUrl(src);
      if (seen.contains(norm)) {
        _removeImageAndWrapper(img);
      } else {
        seen.add(norm);
      }
    }
  }

  static final _scheme = RegExp(r'^https?://');
  static final _sizeSuffix = RegExp(r'-\d+x\d+(?=\.\w+$)');

  String _normalizeImageUrl(String url) {
    var u = url.split('?').first;
    u = u.replaceFirst(_scheme, '');
    u = u.replaceAll(_sizeSuffix, '');
    return u.toLowerCase();
  }

  void _removeImageAndWrapper(html_dom.Element img) {
    final parent = img.parent;
    if (parent != null &&
        const {'figure', 'picture', 'a'}.contains(parent.localName) &&
        parent.getElementsByTagName('img').length <= 1) {
      parent.remove();
    } else {
      img.remove();
    }
  }

  // ----------- Consecutive-image carousel grouping -----------

  void _groupConsecutiveImages(html_dom.Element parent) {
    for (final child in parent.children.toList()) {
      _groupConsecutiveImages(child);
    }

    final children = parent.nodes.toList();
    final runs = <List<html_dom.Node>>[];
    List<html_dom.Node> currentRun = [];

    for (final node in children) {
      if (_isImageNode(node)) {
        currentRun.add(node);
      } else {
        if (node is html_dom.Text && node.text.trim().isEmpty) {
          if (currentRun.isNotEmpty) currentRun.add(node);
          continue;
        }
        if (currentRun.length >= 2) runs.add(List.from(currentRun));
        currentRun = [];
      }
    }
    if (currentRun.length >= 2) runs.add(currentRun);

    for (final run in runs) {
      final urls = <String>[];
      for (final node in run) {
        final url = _extractImageUrl(node);
        if (url != null && url.isNotEmpty) urls.add(url);
      }
      if (urls.length < 2) continue;

      final carousel = html_dom.Element.tag('img-carousel')
        ..attributes['data-urls'] = urls.join('|');

      run.first.replaceWith(carousel);
      for (int i = 1; i < run.length; i++) {
        run[i].remove();
      }
    }
  }

  bool _isImageNode(html_dom.Node node) {
    if (node is! html_dom.Element) return false;
    if (node.localName == 'img') return true;
    if (const {'figure', 'picture', 'a', 'div'}.contains(node.localName)) {
      final imgs = node.getElementsByTagName('img');
      if (imgs.isNotEmpty) {
        final nonImgText = node.text.trim();
        return nonImgText.length < 30;
      }
    }
    return false;
  }

  String? _extractImageUrl(html_dom.Node node) {
    if (node is! html_dom.Element) return null;
    if (node.localName == 'img') return node.attributes['src'];
    final imgs = node.getElementsByTagName('img');
    if (imgs.isNotEmpty) return imgs.first.attributes['src'];
    return null;
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    readingProgress.dispose();
    super.dispose();
  }
}
