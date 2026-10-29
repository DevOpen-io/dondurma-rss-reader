import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../utils/host_pacer.dart';
import '../utils/retry_after.dart';
import '../utils/bounded_body.dart';
import 'feed_backoff.dart';
import 'feed_service.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';

/// Extracts full article content from a webpage URL using heuristic scoring.
///
/// Designed for feeds that only publish excerpts — fetches the original page,
/// strips boilerplate elements, and returns the inner HTML of the highest-
/// scoring content block. Results are cached in-memory for the session.
///
/// Singleton: all state ([_cache], [_failedUrls]) is shared process-wide, so a
/// single instance keeps the instance/state design consistent.
class FullTextExtractionService {
  FullTextExtractionService._();
  static final FullTextExtractionService instance =
      FullTextExtractionService._();
  factory FullTextExtractionService() => instance;

  // ---------------------------------------------------------------------------
  // HTTP header constants (match FeedService for consistency)
  // ---------------------------------------------------------------------------

  /// Largest article page read; bigger responses are abandoned mid-stream.
  static const int maxPageBytes = 8 * 1024 * 1024;

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36';

  // ---------------------------------------------------------------------------
  // In-memory per-session cache  (URL → extracted HTML)
  //
  // Static so it is shared across service instances (each article page creates
  // its own service), and capped so long sessions don't accumulate megabytes
  // of extracted article HTML. Oldest entry is evicted first.
  // ---------------------------------------------------------------------------

  static final Map<String, String> _cache = {};
  static const int _cacheCapacity = 20;

  static void _cachePut(String url, String html) {
    if (_cache.length >= _cacheCapacity && !_cache.containsKey(url)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = html;
  }

  /// Host pacer shared with the feed refresher/preparation pipeline —
  /// wired by the owning provider. Falls back to a private pacer so the
  /// service still works standalone (tests, direct use).
  HostPacer pacer = HostPacer(minGap: const Duration(seconds: 1));

  /// Shared rate-limit policy — a host cooldown learned by feed refresh
  /// (e.g. a Reddit 429) must also hold article fetches back. Assigned
  /// by the owning provider / background runner; null means extraction
  /// only honors its own failure tracking.
  FeedBackoff? backoff;

  // Failure cache — remembers URLs where extraction failed so we don't
  // waste bandwidth retrying on every article open. Transient failures
  // (timeouts, 5xx, 429) expire quickly so a temporary outage doesn't
  // block the article for the whole session; permanent ones (403/404/410,
  // or a page with no extractable content) last the session.
  //
  // `mandatedUntil` tracks the server-issued `Retry-After` window
  // separately from the overall cooldown — an explicit user retry may
  // bypass the local heuristic part but never an active server wait.
  // Keeping the two windows distinct means a local estimate longer than
  // the mandate can't erase the mandate, and vice versa.
  static final Map<String, ({DateTime until, DateTime? mandatedUntil})>
  _failedUntil = {};
  static const int _failedCapacity = 20;

  /// Far-future deadline marking a permanent (session-lifetime) failure.
  static final DateTime _permanentDeadline = DateTime.utc(3000);

  /// How long a transient failure keeps a URL out of automatic extraction.
  /// Mutable so tests can shrink the cooldown instead of waiting minutes.
  @visibleForTesting
  static Duration transientFailureTtl = const Duration(minutes: 5);

  /// Clears the shared session caches — tests need isolation between cases
  /// because the singleton state is process-wide.
  @visibleForTesting
  static void debugClearSession() {
    _cache.clear();
    _failedUntil.clear();
    _deferredUrls.clear();
  }

  // URLs whose last [extractFullText] call returned null WITHOUT firing
  // a request — a cooldown gate skipped it. A caller distinguishes
  // "deferred" (not an attempt — don't count a failure) from a fetch
  // that actually ran and failed (e.g. the page's own 429).
  static final Set<String> _deferredUrls = {};

  /// Whether the last [extractFullText] call for [url] was skipped by a
  /// cooldown without hitting the network.
  bool wasDeferred(String url) => _deferredUrls.contains(url);

  static void _markDeferred(String url) {
    if (_deferredUrls.length >= _failedCapacity &&
        !_deferredUrls.contains(url)) {
      _deferredUrls.remove(_deferredUrls.first);
    }
    _deferredUrls.add(url);
  }

  /// Test seam — injected extract callbacks in tests simulate the
  /// cooldown-skip path through this marker.
  @visibleForTesting
  static void debugMarkDeferred(String url) => _markDeferred(url);

  static void _recordFailure(
    String url,
    DateTime until, {
    bool serverMandated = false,
  }) {
    // Merge, never shorten: an out-of-order sibling response (a 500
    // landing after a 429's Retry-After) must not unlock a retry early.
    // The mandate window merges independently — a shorter local estimate
    // can't cut it, a longer one can't erase it, and a new valid mandate
    // still extends it.
    final existing = _failedUntil[url];
    var effective = until;
    DateTime? mandated = serverMandated ? until : null;
    if (existing != null) {
      if (existing.until.isAfter(effective)) effective = existing.until;
      final em = existing.mandatedUntil;
      if (em != null && (mandated == null || em.isAfter(mandated))) {
        mandated = em;
      }
    }
    // A mandated wait also blocks automatic retries for its whole window.
    if (mandated != null && mandated.isAfter(effective)) {
      effective = mandated;
    }
    if (_failedUntil.length >= _failedCapacity &&
        !_failedUntil.containsKey(url)) {
      _failedUntil.remove(_failedUntil.keys.first);
    }
    _failedUntil[url] = (until: effective, mandatedUntil: mandated);
  }

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

  /// Whether [url] is currently inside a failure cooldown, so a failing
  /// article is not re-fetched on every attempt; transient entries expire
  /// after [_transientFailureTtl].
  bool hasFailedAttempt(String url) {
    final entry = _failedUntil[url];
    return entry != null && entry.until.isAfter(DateTime.now());
  }

  /// Whether a request to [url] must not fire right now — this URL's own
  /// failure cooldown or the shared host-level rate-limit policy. A
  /// forced retry bypasses local estimates, never a server mandate.
  bool _blocked(String url, bool forceRefresh) {
    if (forceRefresh ? _inServerCooldown(url) : hasFailedAttempt(url)) {
      return true;
    }
    return _hostBlocked(url, forceRefresh);
  }

  /// The shared host-level rate-limit part of [_blocked].
  bool _hostBlocked(String url, bool forceRefresh) {
    final b = backoff;
    if (b == null) return false;
    final now = DateTime.now();
    return forceRefresh
        ? b.isMandatedBackedOff(url, now)
        : b.isBackedOff(url, now);
  }

  /// Whether [url] is inside a server-issued `Retry-After` wait — even a
  /// forced retry must not violate it.
  bool _inServerCooldown(String url) {
    final until = _failedUntil[url]?.mandatedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// Fetches [url], extracts the main article body, and returns its inner HTML.
  ///
  /// Returns `null` if the page cannot be fetched or no suitable content block
  /// is found.
  ///
  /// [forceRefresh] bypasses the failure cache for explicit user-initiated
  /// retries (tapping "Full Article"), so a URL that failed on an automatic
  /// attempt is still retried on demand. Successful results are always cached.
  Future<String?> extractFullText(
    String url, {
    bool forceRefresh = false,
  }) async {
    // Return cached result if available
    if (_cache.containsKey(url)) return _cache[url];
    if (_blocked(url, forceRefresh)) {
      _markDeferred(url);
      return null;
    }

    try {
      await pacer.pace(url);
      // The pace wait may have spanned a sibling request's 429 — the
      // cooldown learned while queued applies before this request too.
      if (_blocked(url, forceRefresh)) {
        _markDeferred(url);
        return null;
      }
      _deferredUrls.remove(url);
      final client = http.Client();
      // The URL whose host answered — the publisher page for a resolved
      // Google News link, so host-wide rate limits land on that host.
      var fetchedUrl = url;
      (http.StreamedResponse, Uint8List?) fetched;
      try {
        fetched = await _fetchPage(client, url);
        // Google News article links answer with a JS redirect stub; the
        // publisher URL has to be asked from Google before extracting.
        final stub = fetched.$2;
        if (fetched.$1.statusCode == 200 &&
            stub != null &&
            _googleNewsArticlePath.hasMatch(Uri.parse(url).path)) {
          final target = await _resolveGoogleNews(client, url, stub);
          if (target == null) {
            _recordFailure(url, DateTime.now().add(transientFailureTtl));
            return null;
          }
          await pacer.pace(target);
          if (_hostBlocked(target, forceRefresh)) {
            _markDeferred(url);
            return null;
          }
          fetchedUrl = target;
          fetched = await _fetchPage(client, target);
        }
      } finally {
        client.close();
      }
      final (response, bodyBytes) = fetched;

      if (response.statusCode != 200) {
        final now = DateTime.now();
        // Access-denied and gone statuses are permanent for the session —
        // the page won't change its mind in minutes. Everything else
        // (429, 5xx, odd statuses) is transient: a Retry-After wins, else
        // a short TTL lets the next attempt try again instead of the URL
        // staying dead for the session.
        const permanent = {401, 403, 404, 410};
        final retryAfter = parseRetryAfter(
          response.headers['retry-after'],
          now,
        );
        _recordFailure(
          url,
          permanent.contains(response.statusCode)
              ? _permanentDeadline
              : (retryAfter ?? now.add(transientFailureTtl)),
          serverMandated:
              !permanent.contains(response.statusCode) && retryAfter != null,
        );
        // Rate-limit signals are host-wide — report them to the shared
        // backoff so sibling feeds, extractions and media downloads on
        // the same origin stop too, not just this URL's own cooldown.
        if (response.statusCode == 429 ||
            response.statusCode == 503 ||
            retryAfter != null) {
          backoff?.recordFailure(
            fetchedUrl,
            FeedFetchException(
              FeedFetchErrorKind.httpStatus,
              'Full-text fetch failed (Status: ${response.statusCode})',
              retryAfter: retryAfter,
              statusCode: response.statusCode,
            ),
            now,
          );
        }
        return null;
      }

      if (bodyBytes == null) {
        // Over the size limit — a retry would fetch the same page.
        _recordFailure(url, _permanentDeadline);
        return null;
      }

      // Full-page HTML parse + heuristic scoring is CPU-heavy (pages can be
      // megabytes) — run it in a background isolate to keep the UI smooth.
      final result = await compute(extractArticleHtml, bodyBytes);

      if (result != null && result.isNotEmpty) {
        _cachePut(url, result);
        return result;
      }
      _recordFailure(url, _permanentDeadline);
      return null;
    } catch (e) {
      debugPrint('FullTextExtractionService error for $url: $e');
      // Transport failures (timeout, DNS, socket) are transient by nature.
      _recordFailure(url, DateTime.now().add(transientFailureTtl));
      return null;
    }
  }

  /// Drops [url]'s extraction result when the caller found it no better
  /// than the feed's own excerpt: it is not served from the cache again and
  /// automatic attempts stop for the session. An explicit retry
  /// ([extractFullText] with `forceRefresh`) still fetches the page anew.
  void discard(String url) {
    _cache.remove(url);
    _recordFailure(url, _permanentDeadline);
  }

  static final _whitespace = RegExp(r'\s+');

  /// Visible text of [html], whitespace collapsed.
  static String plainText(String html) =>
      (parse(html).body?.text ?? '').replaceAll(_whitespace, ' ').trim();

  /// Whether [fullText] gives the reader meaningfully more than
  /// [excerptText] (both plain text). A page that only yields its headline,
  /// the feed's own summary and a dateline is not a full article.
  static bool isMoreThanExcerpt(String fullText, String excerptText) {
    final full = fullText.replaceAll(_whitespace, ' ').trim().length;
    final excerpt = excerptText.replaceAll(_whitespace, ' ').trim().length;
    if (excerpt == 0) return full > 0;
    return full >= excerpt * 1.2 + 200;
  }

  /// GETs [url] with browser headers. The body streams with a cap, so a
  /// runaway page is dropped instead of buffered whole; it is only read
  /// for a 200.
  Future<(http.StreamedResponse, Uint8List?)> _fetchPage(
    http.Client client,
    String url,
  ) => sendBounded(
    client,
    http.Request('GET', Uri.parse(url))
      ..headers.addAll({
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      }),
    maxBytes: maxPageBytes,
    accept: (response) => response.statusCode == 200,
    timeout: const Duration(seconds: 15),
  );

  /// `news.google.com/rss/articles/<id>` (and `/articles/<id>`).
  static final _googleNewsArticlePath = RegExp(r'^/(rss/)?articles/');

  static String? _dataAttr(String page, String name) =>
      RegExp('$name="([^"]+)"').firstMatch(page)?.group(1);

  /// Asks Google's own decoding endpoint for the publisher URL behind a
  /// Google News article [url], using the id/timestamp/signature its
  /// redirect [stub] page carries. Null when any step fails.
  Future<String?> _resolveGoogleNews(
    http.Client client,
    String url,
    Uint8List stub,
  ) async {
    final page = utf8.decode(stub, allowMalformed: true);
    final id = _dataAttr(page, 'data-n-a-id');
    final ts = int.tryParse(_dataAttr(page, 'data-n-a-ts') ?? '');
    final sg = _dataAttr(page, 'data-n-a-sg');
    if (id == null || ts == null || sg == null) return null;
    final payload = jsonEncode([
      'garturlreq',
      // Fixed client context the endpoint expects, as Google's own page
      // sends it.
      [
        [
          'X', 'X', ['X', 'X'], null, null, 1, 1, 'US:en', null, 1, //
          null, null, null, null, null, 0, 1,
        ],
        'X', 'X', 1, [1, 1, 1], 1, 1, null, 0, 0, null, 0, //
      ],
      id,
      ts,
      sg,
    ]);
    final response = await client
        .post(
          Uri.parse(url).resolve('/_/DotsSplashUi/data/batchexecute'),
          headers: {
            'User-Agent': _userAgent,
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
          },
          body: {
            'f.req': jsonEncode([
              [
                ['Fbv4je', payload, null, 'generic'],
              ],
            ]),
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    // `)]}'` guard line, then one JSON envelope per line.
    for (final line in const LineSplitter().convert(response.body)) {
      if (!line.startsWith('[')) continue;
      try {
        for (final entry in jsonDecode(line) as List) {
          if (entry is! List || entry.length < 3 || entry[0] != 'wrb.fr') {
            continue;
          }
          final inner = jsonDecode(entry[2] as String) as List;
          final target = Uri.tryParse(inner[1] as String);
          if (inner[0] == 'garturlres' &&
              target != null &&
              (target.isScheme('http') || target.isScheme('https')) &&
              !_googleNewsArticlePath.hasMatch(target.path)) {
            return target.toString();
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Decodes [bodyBytes] and runs the full extraction pipeline, returning the
  /// inner HTML of the best content block or `null` when none qualifies.
  ///
  /// Static and side-effect free so it can run in a background isolate via
  /// [compute].
  static String? extractArticleHtml(Uint8List bodyBytes) {
    final bodyString = utf8.decode(bodyBytes, allowMalformed: true);
    final document = parse(bodyString);

    // 1. Remove obviously non-content elements
    _removeBoilerplate(document);

    // 2. Heuristic scoring across all block elements
    final body = document.body;
    if (body == null) return null;

    final candidates = <Element>[];
    for (final tag in ['div', 'section']) {
      candidates.addAll(body.getElementsByTagName(tag));
    }

    Element? bestCandidate;
    double bestScore = 0;

    for (final el in candidates) {
      final score = _scoreElement(el);
      if (score > bestScore) {
        bestScore = score;
        bestCandidate = el;
      }
    }
    final block = bestScore < 20 ? null : bestCandidate;

    // 3. Prefer <article>, then <main> — many modern sites wrap content in
    // them — unless that element is only the headline block and the story
    // paragraphs sit beside it (gzt.com): a single-article block with far
    // more paragraph text wins then.
    for (final tag in ['article', 'main']) {
      final best = _pickBestCandidate(document.getElementsByTagName(tag));
      if (best == null) continue;
      if (block != null &&
          block.getElementsByTagName('article').length <= 1 &&
          paragraphTextLength(block) > 2 * paragraphTextLength(best)) {
        break;
      }
      final html = _extractInnerHtml(best);
      if (html.isNotEmpty) return html;
    }

    if (block == null) return null;
    final result = _extractInnerHtml(block);
    return result.isNotEmpty ? result : null;
  }

  /// Text length of [el]'s substantial paragraphs — the story itself, as
  /// opposed to headlines, bylines and link lists.
  static int paragraphTextLength(Element el) {
    var length = 0;
    for (final p in el.getElementsByTagName('p')) {
      final text = p.text.trim();
      if (text.length > 25) length += text.length;
    }
    return length;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts the inner HTML of [element], then fixes any entity-encoded HTML
  /// tags that the DOM serialiser may have produced (e.g. when the original
  /// page stored content as text inside a `<div>`).
  static String _extractInnerHtml(Element element) {
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
  static void _removeBoilerplate(Document document) {
    for (final tag in _removeTags) {
      for (final el in document.getElementsByTagName(tag).toList()) {
        el.remove();
      }
    }

    // Remove elements whose class or id strongly suggest non-content.
    // Root and wrapper classes often describe the layout instead
    // (`no-sidebar`, bbc.co.uk's `ContainerWithSidebarWrapper`, Valnet's
    // `<article class="widget">`), so <html>/<body> and any element holding
    // most of the page's paragraph text are kept.
    final storyText = document.body == null
        ? 0
        : paragraphTextLength(document.body!);
    for (final el in document.querySelectorAll('*').toList()) {
      if (el.localName == 'html' || el.localName == 'body') continue;
      final classAttr = el.attributes['class'] ?? '';
      final idAttr = el.attributes['id'] ?? '';
      if ((_nonContentClassPattern.hasMatch(classAttr) ||
              _nonContentClassPattern.hasMatch(idAttr)) &&
          paragraphTextLength(el) * 2 <= storyText) {
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
  static Element? _pickBestCandidate(List<Element> candidates) {
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
  static double _scoreElement(Element el) {
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
