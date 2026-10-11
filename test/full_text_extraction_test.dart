import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/feed_backoff.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/full_text_extraction_service.dart';

/// Transient-vs-permanent failure classification in
/// [FullTextExtractionService]: a dead page must not be retried forever,
/// but a temporary outage must not kill the article for the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  final counts = <String, int>{};
  final handlers = <String, void Function(HttpRequest)>{};

  String url(String path) =>
      'http://${server.address.host}:${server.port}$path';

  setUpAll(() async {
    // flutter_test installs a 400-only HttpOverrides client — extraction
    // needs a real loopback server.
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      counts.update(request.uri.path, (v) => v + 1, ifAbsent: () => 1);
      final handler = handlers[request.uri.path];
      if (handler != null) {
        handler(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  setUp(() {
    counts.clear();
    handlers.clear();
    FullTextExtractionService.debugClearSession();
    FullTextExtractionService.transientFailureTtl = const Duration(minutes: 5);
    FullTextExtractionService.instance.backoff = null;
  });

  test('404 marks the URL permanently failed — no second request', () async {
    final target = url('/gone');
    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    expect(FullTextExtractionService.instance.hasFailedAttempt(target), isTrue);

    // Second automatic attempt never reaches the network.
    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    expect(counts['/gone'], 1);
  });

  test('500 failure is transient — cooldown expiry allows a retry', () async {
    handlers['/flaky'] = (request) {
      request.response.statusCode = HttpStatus.internalServerError;
    };
    FullTextExtractionService.transientFailureTtl = const Duration(
      milliseconds: 150,
    );
    final target = url('/flaky');

    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    expect(FullTextExtractionService.instance.hasFailedAttempt(target), isTrue);

    // After the transient cooldown expires the URL is attempted again.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(
      FullTextExtractionService.instance.hasFailedAttempt(target),
      isFalse,
    );
    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    expect(counts['/flaky'], 2);
  });

  test('Retry-After header sets the transient cooldown', () async {
    handlers['/limited'] = (request) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      request.response.headers.set('retry-after', '30');
    };
    FullTextExtractionService.transientFailureTtl = const Duration(
      milliseconds: 150,
    );
    final target = url('/limited');

    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    // The server-issued 30s wait outlives the tiny transient TTL — the URL
    // must still be cooling down well past 150ms.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(FullTextExtractionService.instance.hasFailedAttempt(target), isTrue);
  });

  test('forceRefresh bypasses the heuristic cooldown', () async {
    handlers['/flaky'] = (request) {
      request.response.statusCode = HttpStatus.internalServerError;
    };
    final target = url('/flaky');

    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    // A manual retry ignores the local heuristic TTL and hits the network.
    expect(
      await FullTextExtractionService.instance.extractFullText(
        target,
        forceRefresh: true,
      ),
      isNull,
    );
    expect(counts['/flaky'], 2);
  });

  test('forceRefresh still honors a server Retry-After wait', () async {
    handlers['/limited'] = (request) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      request.response.headers.set('retry-after', '30');
    };
    final target = url('/limited');

    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    // Even an explicit user retry must not violate the server's mandate.
    expect(
      await FullTextExtractionService.instance.extractFullText(
        target,
        forceRefresh: true,
      ),
      isNull,
    );
    expect(counts['/limited'], 1);
  });

  test('an HTTP-date Retry-After also blocks a forced retry', () async {
    final until = DateTime.now().toUtc().add(const Duration(minutes: 7));
    handlers['/dated'] = (request) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      request.response.headers.set('retry-after', HttpDate.format(until));
    };
    final target = url('/dated');

    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    expect(
      await FullTextExtractionService.instance.extractFullText(
        target,
        forceRefresh: true,
      ),
      isNull,
    );
    expect(counts['/dated'], 1);
  });

  group('shared feed backoff', () {
    FeedFetchException rateLimit({DateTime? retryAfter}) => FeedFetchException(
      FeedFetchErrorKind.httpStatus,
      'status 429',
      retryAfter: retryAfter,
      statusCode: 429,
    );

    test('a host cooldown learned by feed refresh blocks extraction', () async {
      handlers['/art'] = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html><body>never fetched</body></html>');
      };
      // The RSS feed on the same host was rate-limited — the article URL
      // must not be hit while the shared cooldown is active.
      final backoff = FeedBackoff()
        ..recordFailure(url('/feed.xml'), rateLimit(), DateTime.now());
      FullTextExtractionService.instance.backoff = backoff;

      expect(
        await FullTextExtractionService.instance.extractFullText(url('/art')),
        isNull,
      );
      expect(counts['/art'], isNull); // zero HTTP requests
    });

    test('forceRefresh bypasses a local host estimate but honors a server '
        'mandate', () async {
      handlers['/art'] = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><body><article>'
          '<p>${'enough text to extract. ' * 40}</p>'
          '</article></body></html>',
        );
      };
      // Local estimate (no Retry-After): a manual retry may bypass it.
      final local = FeedBackoff()
        ..recordFailure(url('/feed.xml'), rateLimit(), DateTime.now());
      FullTextExtractionService.instance.backoff = local;
      expect(
        await FullTextExtractionService.instance.extractFullText(
          url('/art'),
          forceRefresh: true,
        ),
        isNotNull,
      );
      expect(counts['/art'], 1);

      // Server-mandated host cooldown: forceRefresh must still wait.
      FullTextExtractionService.debugClearSession();
      counts.clear();
      final mandated = FeedBackoff()
        ..recordFailure(
          url('/feed.xml'),
          rateLimit(
            retryAfter: DateTime.now().add(const Duration(minutes: 10)),
          ),
          DateTime.now(),
        );
      FullTextExtractionService.instance.backoff = mandated;
      expect(
        await FullTextExtractionService.instance.extractFullText(
          url('/art'),
          forceRefresh: true,
        ),
        isNull,
      );
      expect(counts['/art'], isNull);
    });
  });

  test('a page with no extractable content is a permanent failure', () async {
    handlers['/empty'] = (request) {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html><body><p>tiny</p></body></html>');
    };
    final target = url('/empty');
    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    expect(FullTextExtractionService.instance.hasFailedAttempt(target), isTrue);
    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    expect(counts['/empty'], 1);
  });

  test('successful extraction caches and does not record failure', () async {
    handlers['/article'] = (request) {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><body><article>'
        '<p>${'substantial paragraph of article body text. ' * 20}</p>'
        '<p>${'more real article content for the scorer. ' * 20}</p>'
        '</article></body></html>',
      );
    };
    final target = url('/article');
    final html = await FullTextExtractionService.instance.extractFullText(
      target,
    );
    expect(html, isNotNull);
    expect(
      FullTextExtractionService.instance.hasFailedAttempt(target),
      isFalse,
    );
    // Cache hit — no second request.
    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      html,
    );
    expect(counts['/article'], 1);
  });
}
