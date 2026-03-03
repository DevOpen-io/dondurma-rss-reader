import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../models/feed_item.dart';
import '../providers/subscription_provider.dart';
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

  /// Whether the extraction was attempted and failed.
  bool _fullTextFailed = false;
  bool get fullTextFailed => _fullTextFailed;

  /// Whether the heavy Html widget is ready to render. Set to `true`
  /// after the first frame so the route transition animation is not blocked.
  bool _contentReady = false;
  bool get contentReady => _contentReady;

  /// Cached result of [preprocessHtml] for the current content source.
  String? _cachedDisplayContent;
  String? get cachedDisplayContent => _cachedDisplayContent;

  /// Cached reading-time estimate for the current content source.
  int? _cachedReadingMinutes;
  int? get cachedReadingMinutes => _cachedReadingMinutes;

  /// Reading progress (0.0 to 1.0). Uses [ValueNotifier] to avoid full
  /// rebuilds on every scroll tick.
  final ValueNotifier<double> readingProgress = ValueNotifier(0.0);

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  ArticlePageProvider({required this.item});

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

  /// Checks if the item's feed has full-text enabled by default and
  /// auto-activates extraction.
  void checkAutoFullText(SubscriptionProvider subProvider) {
    final sub = subProvider.subscriptions.where((s) => s.url == item.feedUrl);
    if (sub.isNotEmpty && sub.first.fullTextEnabled) {
      activateFullText();
    }
  }

  Future<void> activateFullText() async {
    if (item.link.isEmpty) return;

    _fullTextActive = true;
    _isLoadingFullText = true;
    _fullTextFailed = false;
    _fullTextContent = null;
    notifyListeners();

    final result = await _extractionService.extractFullText(item.link);

    _isLoadingFullText = false;
    // Invalidate cached content so it's recomputed with the new source.
    _cachedDisplayContent = null;
    _cachedReadingMinutes = null;
    if (result != null && result.isNotEmpty) {
      _fullTextContent = result;
      _fullTextFailed = false;
    } else {
      _fullTextFailed = true;
      _fullTextActive = false;
      _fullTextContent = null;
    }
    notifyListeners();
  }

  void deactivateFullText() {
    _fullTextActive = false;
    _isLoadingFullText = false;
    _fullTextContent = null;
    _fullTextFailed = false;
    // Invalidate cached content so it's recomputed with the original source.
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

  /// Returns the raw HTML to display — full-text if available, otherwise
  /// the item's content or description.
  String get rawContent => _fullTextContent ?? item.content ?? item.description;

  /// Returns the preprocessed display content, computing & caching on first
  /// access or after cache invalidation.
  String get displayContent {
    _cachedDisplayContent ??= _preprocessHtml(rawContent);
    return _cachedDisplayContent!;
  }

  /// Returns the estimated reading minutes, computing & caching on first
  /// access or after cache invalidation.
  int get readingMinutes {
    _cachedReadingMinutes ??= _estimateReadingMinutes(rawContent);
    return _cachedReadingMinutes!;
  }

  /// Strips HTML tags and counts words to estimate reading time.
  int _estimateReadingMinutes(String htmlContent) {
    final doc = html_parser.parse(htmlContent);
    final text = doc.body?.text ?? '';
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    // Average reading speed: ~200 words/minute
    return (words / 200).ceil();
  }

  // ---------------------------------------------------------------------------
  // HTML pre-processing
  // ---------------------------------------------------------------------------

  String _preprocessHtml(String htmlContent) {
    final doc = html_parser.parse(htmlContent);
    final body = doc.body;
    if (body == null) return htmlContent;

    _stripInlineStyles(body);
    _removeAdContent(body);
    _removeEmptyElements(body);
    _deduplicateImages(body);
    _groupConsecutiveImages(body);

    return body.innerHtml;
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

  static final _adClassPattern = RegExp(
    r'(ad-|advert|sponsor|promo|native-ad|outbrain|taboola|'
    r'related-stories|rec-rail|story-rail|commerce|affiliate)',
    caseSensitive: false,
  );

  void _removeAdContent(html_dom.Element parent) {
    for (final el in parent.querySelectorAll('*').toList()) {
      final cls = el.attributes['class'] ?? '';
      final id = el.attributes['id'] ?? '';
      if (_adClassPattern.hasMatch(cls) || _adClassPattern.hasMatch(id)) {
        el.remove();
        continue;
      }

      final tag = el.localName ?? '';
      if ({
        'div',
        'section',
        'aside',
        'p',
        'span',
        'h2',
        'h3',
        'h4',
      }.contains(tag)) {
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

  String _normalizeImageUrl(String url) {
    var u = url.split('?').first;
    u = u.replaceFirst(RegExp(r'^https?://'), '');
    u = u.replaceAll(RegExp(r'-\d+x\d+(?=\.\w+$)'), '');
    return u.toLowerCase();
  }

  void _removeImageAndWrapper(html_dom.Element img) {
    final parent = img.parent;
    if (parent != null &&
        {'figure', 'picture', 'a'}.contains(parent.localName) &&
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
    if ({'figure', 'picture', 'a', 'div'}.contains(node.localName)) {
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
    readingProgress.dispose();
    super.dispose();
  }
}
