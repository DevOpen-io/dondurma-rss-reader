import 'dart:convert';

import 'package:flutter/material.dart' hide Element;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';

/// Extracts full article content from a webpage URL using heuristic scoring.
///
/// Designed for feeds that only publish excerpts — fetches the original page,
/// strips boilerplate elements, and returns the inner HTML of the highest-
/// scoring content block. Results are cached in-memory for the session.
class FullTextExtractionService {
  // ---------------------------------------------------------------------------
  // HTTP header constants (match FeedService for consistency)
  // ---------------------------------------------------------------------------

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36';

  // ---------------------------------------------------------------------------
  // In-memory per-session cache  (URL → extracted HTML)
  // ---------------------------------------------------------------------------

  final Map<String, String> _cache = {};

  // ---------------------------------------------------------------------------
  // Tags and class-name patterns considered non-content
  // ---------------------------------------------------------------------------

  static const _removeTags = <String>[
    'script',
    'style',
    'noscript',
    'nav',
    'header',
    'footer',
    'aside',
    'form',
    'ins', // ads
    'iframe',
    'svg',
    'button',
    'input',
    'select',
    'textarea',
    'label',
  ];

  static final _nonContentClassPattern = RegExp(
    r'(comment|sidebar|widget|menu|nav\b|footer|header|advert|ad-slot|'
    r'social|share|related|promo|popup|modal|cookie|banner|newsletter|'
    r'breadcrumb|pagination|toolbar|signup|login|search-form|skip-link|'
    r'masthead|site-header|site-footer|wp-caption-text)',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Fetches [url], extracts the main article body, and returns its inner HTML.
  ///
  /// Returns `null` if the page cannot be fetched or no suitable content block
  /// is found.
  Future<String?> extractFullText(String url) async {
    // Return cached result if available
    if (_cache.containsKey(url)) return _cache[url];

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );

      if (response.statusCode != 200) return null;

      // Decode body with UTF-8 (handle malformed sequences gracefully)
      String bodyString;
      try {
        bodyString = utf8.decode(response.bodyBytes, allowMalformed: true);
      } catch (_) {
        bodyString = response.body;
      }

      final document = parse(bodyString);

      // 1. Remove obviously non-content elements
      _removeBoilerplate(document);

      // 2. Try <article> first — many modern sites wrap content in <article>
      final articles = document.getElementsByTagName('article');
      if (articles.isNotEmpty) {
        final best = _pickBestCandidate(articles);
        if (best != null) {
          final html = _extractInnerHtml(best);
          if (html.isNotEmpty) {
            _cache[url] = html;
            return html;
          }
        }
      }

      // 3. Try <main>
      final mains = document.getElementsByTagName('main');
      if (mains.isNotEmpty) {
        final best = _pickBestCandidate(mains);
        if (best != null) {
          final html = _extractInnerHtml(best);
          if (html.isNotEmpty) {
            _cache[url] = html;
            return html;
          }
        }
      }

      // 4. Fall back to heuristic scoring across all block elements
      final body = document.body;
      if (body == null) return null;

      final candidates = <Element>[];
      for (final tag in ['div', 'section']) {
        candidates.addAll(body.getElementsByTagName(tag));
      }

      if (candidates.isEmpty) return null;

      Element? bestCandidate;
      double bestScore = 0;

      for (final el in candidates) {
        final score = _scoreElement(el);
        if (score > bestScore) {
          bestScore = score;
          bestCandidate = el;
        }
      }

      if (bestCandidate == null || bestScore < 20) return null;

      final result = _extractInnerHtml(bestCandidate);
      if (result.isNotEmpty) {
        _cache[url] = result;
      }
      return result.isNotEmpty ? result : null;
    } catch (e) {
      debugPrint('FullTextExtractionService error for $url: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts the inner HTML of [element], then fixes any entity-encoded HTML
  /// tags that the DOM serialiser may have produced (e.g. when the original
  /// page stored content as text inside a `<div>`).
  String _extractInnerHtml(Element element) {
    var html = element.innerHtml.trim();

    // Detect and fix entity-encoded HTML: if the content has many `&lt;`
    // occurrences relative to actual `<` tags, it's likely double-escaped.
    final encodedTagCount = '&lt;'.allMatches(html).length;
    if (encodedTagCount > 3) {
      // Decode HTML entities so <p> becomes <p>
      html = html
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&#x27;', "'")
          .replaceAll('&#x2F;', '/');
    }

    return html;
  }

  /// Removes non-content tags and elements whose class/id match ad/nav patterns.
  void _removeBoilerplate(Document document) {
    for (final tag in _removeTags) {
      for (final el in document.getElementsByTagName(tag).toList()) {
        el.remove();
      }
    }

    // Remove elements whose class or id strongly suggest non-content
    for (final el in document.querySelectorAll('*').toList()) {
      final classAttr = el.attributes['class'] ?? '';
      final idAttr = el.attributes['id'] ?? '';
      if (_nonContentClassPattern.hasMatch(classAttr) ||
          _nonContentClassPattern.hasMatch(idAttr)) {
        el.remove();
      }
    }

    // Remove hidden elements
    for (final el
        in document.querySelectorAll('[aria-hidden="true"]').toList()) {
      el.remove();
    }
    for (final el
        in document
            .querySelectorAll(
              '[style*="display:none"], [style*="display: none"]',
            )
            .toList()) {
      el.remove();
    }
  }

  /// Picks the candidate with the highest text density from a list.
  Element? _pickBestCandidate(List<Element> candidates) {
    Element? best;
    double bestScore = 0;
    for (final el in candidates) {
      final score = _scoreElement(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }
    return best;
  }

  /// Scores a DOM element by paragraph density and text length.
  ///
  /// Higher scores indicate a better content candidate:
  ///  - Paragraphs (`<p>`) contribute heavily
  ///  - Total text length adds to the base score
  ///  - Short or deeply nested containers are penalised
  double _scoreElement(Element el) {
    final text = el.text;
    final paragraphs = el.getElementsByTagName('p');

    // Skip very short blocks (< 100 chars of visible text)
    if (text.trim().length < 100) return 0;

    // Base: text length
    double score = text.length / 100.0;

    // Bonus for each paragraph with substantial text
    for (final p in paragraphs) {
      final pText = p.text.trim();
      if (pText.length > 25) {
        score += 10;
      }
    }

    // Bonus for common content-indicating class/id names
    final classAttr = (el.attributes['class'] ?? '').toLowerCase();
    final idAttr = (el.attributes['id'] ?? '').toLowerCase();
    if (classAttr.contains('content') ||
        classAttr.contains('article') ||
        classAttr.contains('post') ||
        classAttr.contains('entry') ||
        classAttr.contains('story') ||
        classAttr.contains('body') ||
        idAttr.contains('content') ||
        idAttr.contains('article') ||
        idAttr.contains('post') ||
        idAttr.contains('entry')) {
      score *= 1.5;
    }

    // Penalise elements with too many links (likely nav or link-heavy blocks)
    final anchors = el.getElementsByTagName('a');
    if (anchors.length > 5 && text.isNotEmpty) {
      final linkTextLen = anchors
          .map((a) => a.text.length)
          .fold(0, (a, b) => a + b);
      final linkDensity = linkTextLen / text.length;
      if (linkDensity > 0.5) {
        score *= 0.3;
      }
    }

    return score;
  }
}
