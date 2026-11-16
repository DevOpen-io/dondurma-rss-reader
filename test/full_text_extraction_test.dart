import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/services/feed_backoff.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';
import 'package:ice_cream_rss_reader/services/full_text_extraction_service.dart';
import 'package:ice_cream_rss_reader/utils/host_pacer.dart';

/// Transient-vs-permanent failure classification in
/// [FullTextExtractionService]: a dead page must not be retried forever,
/// but a temporary outage must not kill the article for the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  final counts = <String, int>{};
  final handlers = <String, FutureOr<void> Function(HttpRequest)>{};

  String url(String path) =>
      'http://${server.address.host}:${server.port}$path';

  FeedFetchException rateLimit({DateTime? retryAfter}) => FeedFetchException(
    FeedFetchErrorKind.httpStatus,
    'status 429',
    retryAfter: retryAfter,
    statusCode: 429,
  );

  setUpAll(() async {
    // flutter_test installs a 400-only HttpOverrides client — extraction
    // needs a real loopback server.
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      counts.update(request.uri.path, (v) => v + 1, ifAbsent: () => 1);
      final handler = handlers[request.uri.path];
      if (handler != null) {
        await handler(request);
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
    FullTextExtractionService.instance.pacer = HostPacer(
      minGap: const Duration(seconds: 1),
    );
  });

  test('a page over the size limit is rejected, not extracted', () async {
    handlers['/huge'] = (request) {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html><body><article><p>');
      final words = 'readable article text ' * 4096;
      for (
        var written = 0;
        written <= FullTextExtractionService.maxPageBytes;
        written += words.length
      ) {
        request.response.write(words);
      }
      request.response.write('</p></article></body></html>');
    };
    final target = url('/huge');
    expect(
      await FullTextExtractionService.instance.extractFullText(target),
      isNull,
    );
    // Size is permanent for the session — no retry of the same page.
    expect(FullTextExtractionService.instance.hasFailedAttempt(target), isTrue);
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

    test('a page 429 is reported to the shared host backoff — the '
        'whole origin cools down', () async {
      final backoff = FeedBackoff();
      FullTextExtractionService.instance.backoff = backoff;
      handlers['/art'] = (request) {
        request.response.statusCode = HttpStatus.tooManyRequests;
        request.response.headers.set('retry-after', '300');
      };

      expect(
        await FullTextExtractionService.instance.extractFullText(url('/art')),
        isNull,
      );
      expect(counts['/art'], 1);
      // The cooldown is host-level and server-mandated — a sibling
      // feed fetch or media download on the same origin must skip.
      final now = DateTime.now();
      expect(backoff.isBackedOff(url('/other'), now), isTrue);
      expect(backoff.isMandatedBackedOff(url('/other'), now), isTrue);
    });
  });

  group('post-pacing recheck', () {
    test('a request queued behind a slower sibling rechecks its failure '
        'cooldown before firing', () async {
      // Gap outlives the sibling's round trip: the queued call passes
      // its initial check before the 500 lands, then must re-evaluate
      // after pacing instead of firing blindly.
      FullTextExtractionService.instance.pacer = HostPacer(
        minGap: const Duration(milliseconds: 400),
      );
      handlers['/flaky'] = (request) {
        request.response.statusCode = HttpStatus.internalServerError;
      };
      final target = url('/flaky');
      final first = FullTextExtractionService.instance.extractFullText(target);
      final second = FullTextExtractionService.instance.extractFullText(target);
      expect(await first, isNull);
      expect(await second, isNull);
      expect(counts['/flaky'], 1); // the queued request never fired
    });

    test('a host cooldown learned while queued blocks the pending request '
        'with zero network traffic', () async {
      FullTextExtractionService.instance.pacer = HostPacer(
        minGap: const Duration(milliseconds: 400),
      );
      final backoff = FeedBackoff();
      FullTextExtractionService.instance.backoff = backoff;
      handlers['/art1'] = (request) {
        // The sibling response carries the 429 signal: recording the
        // cooldown here guarantees call 1 already passed its recheck
        // while call 2 still sits in the pacing queue.
        backoff.recordFailure(url('/feed.xml'), rateLimit(), DateTime.now());
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><body><article>'
          '<p>${'extractable body text. ' * 40}</p>'
          '</article></body></html>',
        );
      };
      handlers['/art2'] = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html><body>never fetched</body></html>');
      };
      // Call 1 grabs the pacing slot and fetches; call 2 queues behind
      // it. The host gets rate-limited while call 2 waits.
      final first = FullTextExtractionService.instance.extractFullText(
        url('/art1'),
      );
      final second = FullTextExtractionService.instance.extractFullText(
        url('/art2'),
      );

      expect(await first, isNotNull);
      expect(await second, isNull);
      expect(counts['/art2'], isNull); // deferred — zero HTTP requests
    });
  });

  group('server-mandate preservation', () {
    test('a slower sibling failure cannot shorten a server Retry-After '
        'mandate on the same URL', () async {
      // Zero pacing gap → both calls fire before either response
      // lands. The 429 records a mandate, then the 500's local
      // cooldown must merge without erasing it.
      FullTextExtractionService.instance.pacer = HostPacer(
        minGap: Duration.zero,
      );
      var hits = 0;
      handlers['/race'] = (request) {
        hits++;
        if (hits == 1) {
          request.response.statusCode = HttpStatus.tooManyRequests;
          request.response.headers.set('retry-after', '60');
        } else {
          request.response.statusCode = HttpStatus.internalServerError;
        }
      };
      final target = url('/race');
      await Future.wait([
        FullTextExtractionService.instance.extractFullText(target),
        FullTextExtractionService.instance.extractFullText(target),
      ]);
      expect(counts['/race'], 2);

      // The mandated window survives — a forced retry is still blocked.
      expect(
        await FullTextExtractionService.instance.extractFullText(
          target,
          forceRefresh: true,
        ),
        isNull,
      );
      expect(counts['/race'], 2);
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

  group('real-page structures', () {
    Uint8List fixture(String name) =>
        File('test/fixtures/full_text/$name').readAsBytesSync();

    test('layout classes around the story do not discard it', () {
      // `globalheader-dark`, `no-sidebar`, `ContainerWithSidebarWrapper`
      // describe the layout; matching them as boilerplate removed the
      // whole document or the wrapper holding <main>.
      final html = FullTextExtractionService.extractArticleHtml(
        fixture('layout_classes_on_body.html'),
      );
      expect(html, isNotNull);
      expect(html, contains('first pass that catches the mechanical issues'));
      expect(html, isNot(contains('Popular this week')));
    });

    test('a comment thread longer than the story is still removed', () {
      // slashdot.org: the story text has no <p>, so one comment thread
      // holds most of the page's paragraphs — comments are never the story.
      final reply =
          '<li id="tree_2" class="comment oneline"><div class="commentBody">'
          '<p>${'What is with the black leather jacket he always wears? ' * 12}'
          '</p></div></li>';
      final page =
          '<html><body><div id="firehose">'
          '<article><h2>Nvidia chief seen as target of spy plot</h2>'
          '<div class="body"><i>${'American spy agencies had gathered '
                  'striking intelligence about the plot.<br>' * 4}</i></div>'
          '</article>'
          '<ul id="commentlisting" class="d2"><li id="tree_1" class="comment">'
          '<div class="commentBody"><p>First!</p></div>'
          '<ul id="commtree_1">$reply</ul></li></ul>'
          '</div></body></html>';

      final html = FullTextExtractionService.extractArticleHtml(
        Uint8List.fromList(utf8.encode(page)),
      );

      expect(html, contains('striking intelligence'));
      expect(html, isNot(contains('leather jacket')));
    });

    test('a headline-only <article> loses to the story body beside it', () {
      // gzt.com: the <article> holds the headline and the feed's summary
      // line; taking it returned exactly the feed excerpt.
      final html = FullTextExtractionService.extractArticleHtml(
        fixture('gzt_header_article.html'),
      );
      expect(html, contains('double-double yapan Nene'));
      expect(html, contains('İsmail Kartal döneminde'));
    });
  });

  group('page leftovers', () {
    String? extract(String page) =>
        FullTextExtractionService.extractArticleHtml(
          Uint8List.fromList(utf8.encode(page)),
        );
    String page(String article) =>
        '<html><body><div class="site"><article class="post">$article'
        '</article></div></body></html>';
    final story =
        '<h1>Chipmakers race to cool data centers</h1>'
        '<p>${'Engineers are rebuilding server halls around liquid '
                'cooling as power budgets climb. ' * 6}</p>'
        '<figure><img src="https://example.com/rack.jpg" alt="Rack">'
        '<figcaption>A liquid-cooled rack in Oregon.</figcaption></figure>'
        '<h2>What changes for operators</h2>'
        '<p>${'Operators must retrain staff and redesign the plumbing '
                'that feeds every aisle of machines. ' * 6}</p>'
        '<ul><li>Pumps replace most of the fans in each rack.</li>'
        '<li>Water loops run under the raised floor.</li>'
        '<li>Heat is sold to nearby district heating grids.</li></ul>'
        '<p>${'Analysts expect the shift to finish within five years '
                'across the largest providers. ' * 6}</p>';
    void expectStory(String? html) {
      expect(html, isNotNull);
      expect(html, contains('Chipmakers race to cool data centers'));
      expect(html, contains('liquid cooling as power budgets climb'));
      expect(html, contains('What changes for operators'));
      expect(html, contains('Pumps replace most of the fans'));
      expect(html, contains('Heat is sold to nearby district heating'));
      expect(html, contains('<figure>'));
      expect(html, contains('A liquid-cooled rack in Oregon.'));
      expect(html, contains('finish within five years'));
    }

    test('breadcrumb trails are dropped', () {
      final html = extract(
        page(
          '<ol aria-label="Breadcrumb"><li><a href="/">Home</a></li>'
          '<li><a href="/tech">Technology</a></li>'
          '<li><a href="/tech/hw">Hardware</a></li></ol>'
          '<div itemscope itemtype="https://schema.org/BreadcrumbList">'
          '<span itemprop="itemListElement"><a href="/">Start</a></span> › '
          '<span itemprop="itemListElement"><a href="/news">Newsroom</a>'
          '</span></div>'
          '$story',
        ),
      );
      expectStory(html);
      expect(html, isNot(contains('Hardware')));
      expect(html, isNot(contains('Newsroom')));
    });

    test('trending and related link lists inside the article are dropped', () {
      final html = extract(
        page(
          '$story'
          '<div class="box"><h3>Trending</h3><ul>'
          '<li><a href="/a">Phone makers cut prices again</a></li>'
          '<li><a href="/b">Rocket startup lands its booster</a></li>'
          '<li><a href="/c">City bans scooters downtown</a></li></ul></div>'
          '<h2>You may also like</h2><ol>'
          '<li><a href="/d">Solar farms on old mines</a></li>'
          '<li><a href="/e">The quiet return of vinyl</a></li></ol>'
          '<h4>Read more:</h4><ul>'
          '<li><a href="/f">Why routers still crash</a></li></ul>'
          '<div class="most-popular-list"><a href="/g">Celebrity chef '
          'opens bakery</a><a href="/h">Markets slip on rate fears</a></div>',
        ),
      );
      expectStory(html);
      for (final leftover in [
        'Trending',
        'Phone makers cut prices',
        'You may also like',
        'quiet return of vinyl',
        'Read more',
        'Why routers still crash',
        'Celebrity chef',
      ]) {
        expect(html, isNot(contains(leftover)), reason: leftover);
      }
    });

    test('tag rows at the end of the article are dropped', () {
      final html = extract(
        page(
          '$story'
          '<p><strong>Tags:</strong> <a href="/t/cooling">cooling</a>, '
          '<a href="/t/datacenters">datacenters</a></p>'
          '<div class="entry-meta">Filed in <a rel="tag" href="/c/infra">'
          'Infrastructure</a> <a rel="category tag" href="/c/energy">'
          'Energy policy</a></div>'
          '<ul class="article-topics"><li><a href="/topic/hvac">HVAC'
          '</a></li><li><a href="/topic/water">Water use</a></li></ul>',
        ),
      );
      expectStory(html);
      for (final leftover in [
        'Tags:',
        '/t/datacenters',
        'Infrastructure',
        'Energy policy',
        'HVAC',
        'Water use',
      ]) {
        expect(html, isNot(contains(leftover)), reason: leftover);
      }
    });

    test('share-button rows are dropped', () {
      final html = extract(
        page(
          '<div class="post-actions">'
          '<a href="https://www.facebook.com/sharer/sharer.php?u=x">'
          'Facebook</a>'
          '<a href="https://twitter.com/intent/tweet?url=x">Post on X</a>'
          '<a href="https://www.linkedin.com/shareArticle?url=x">'
          'LinkedIn</a>'
          '<a href="mailto:?subject=Chipmakers">Email</a></div>'
          '$story',
        ),
      );
      expectStory(html);
      expect(html, isNot(contains('Facebook')));
      expect(html, isNot(contains('Post on X')));
      expect(html, isNot(contains('LinkedIn')));
    });

    test('a story container with trending/topic post classes stays', () {
      // WordPress post_class slugs land on the story element itself.
      final html = extract(
        '<html><body><article class="post type-post category-trending '
        'tag-popular-science">'
        '<p>${'A short post about chip cooling in the desert. ' * 3}</p>'
        '<p>${'It still deserves to be read in full by everyone. ' * 3}</p>'
        '</article><div id="comments">'
        '<p>${'I disagree with every word of this post, honestly. ' * 8}</p>'
        '</div></body></html>',
      );
      expect(html, contains('chip cooling in the desert'));
      expect(html, contains('deserves to be read in full'));
    });

    test('media beside a share row and labelled figures stay', () {
      final html = extract(
        page(
          '<div class="hero"><figure><img src="https://example.com/a.jpg" '
          'alt="Hall"><figcaption>The new hall.</figcaption></figure>'
          '<div><a href="https://twitter.com/intent/tweet?url=x">Tweet</a>'
          '<a href="https://www.facebook.com/sharer/sharer.php?u=x">'
          'Facebook</a></div></div>'
          '<table aria-label="Market share by vendor"><tr><td>Vendor A'
          '</td><td>41%</td></tr></table>'
          '$story',
        ),
      );
      expectStory(html);
      expect(html, contains('The new hall.'));
      expect(html, contains('Vendor A'));
      expect(html, isNot(contains('Tweet')));
    });

    test('prose about trends and plain lists under such headings stay', () {
      final html = extract(
        page(
          '$story'
          '<h2>Trending</h2>'
          '<p>${'Liquid cooling is trending among hyperscalers because '
                  'air simply cannot move enough heat. ' * 4}</p>'
          '<h3>Related</h3><ul>'
          '<li>Older halls can be retrofitted one row at a time.</li>'
          '<li>See <a href="/report">the full report</a> for the method '
          'we used to estimate savings.</li></ul>'
          '<p>Readers can <a href="mailto:tips@example.com">email us</a> '
          'with tips about cooling projects.</p>',
        ),
      );
      expectStory(html);
      expect(html, contains('Liquid cooling is trending among'));
      expect(html, contains('<h2>Trending</h2>'));
      expect(html, contains('retrofitted one row at a time'));
      expect(html, contains('the full report'));
      expect(html, contains('email us'));
    });
  });

  group('Google News article links', () {
    // news.google.com/rss/articles/... answers with a JS redirect stub;
    // the publisher URL comes from Google's batchexecute endpoint.
    String stub(String id) =>
        '<html><body><c-wiz><div jscontroller="aLI87" data-n-a-id="$id" '
        'data-n-a-ts="1793308169" data-n-a-sg="AdwtSYNLf5MZ"></div>'
        '</c-wiz></body></html>';
    final story =
        '<html><body><article>'
        '<p>${'The publisher story paragraph with real reporting. ' * 12}</p>'
        '<p>${'A second paragraph only the full article carries. ' * 12}</p>'
        '</article></body></html>';
    const batchPath = '/_/DotsSplashUi/data/batchexecute';

    test('resolves the publisher page and extracts it', () async {
      String? batchBody;
      handlers['/rss/articles/CBMiAbc'] = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(stub('CBMiAbc'));
      };
      handlers[batchPath] = (request) async {
        batchBody = await utf8.decodeStream(request);
        request.response.write(
          ")]}'\n\n"
          '[["wrb.fr","Fbv4je","[\\"garturlres\\",\\"${url('/story')}\\",1]",'
          'null,null,null,"generic"]]',
        );
      };
      handlers['/story'] = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(story);
      };

      final html = await FullTextExtractionService.instance.extractFullText(
        url('/rss/articles/CBMiAbc?oc=5'),
      );

      expect(html, contains('only the full article carries'));
      expect(
        Uri.splitQueryString(batchBody!)['f.req'],
        allOf(
          contains('CBMiAbc'),
          contains('1793308169'),
          contains('AdwtSYNLf5MZ'),
        ),
      );
      expect(counts['/story'], 1);
    });

    test('a publisher page under /articles/ is extracted as itself', () async {
      // nature.com, ign.com: their own article paths start with /articles/.
      handlers['/articles/plain-story'] = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(story);
      };
      final target = url('/articles/plain-story');

      final html = await FullTextExtractionService.instance.extractFullText(
        target,
      );

      expect(html, contains('only the full article carries'));
      expect(counts[batchPath], isNull);
      expect(
        FullTextExtractionService.instance.hasFailedAttempt(target),
        isFalse,
      );
    });

    test('an unresolvable link fails honestly and a retry refetches', () async {
      handlers['/rss/articles/CBMiDead'] = (request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(stub('CBMiDead'));
      };
      handlers[batchPath] = (request) {
        request.response.statusCode = HttpStatus.badRequest;
      };
      final target = url('/rss/articles/CBMiDead');

      expect(
        await FullTextExtractionService.instance.extractFullText(target),
        isNull,
      );
      expect(
        FullTextExtractionService.instance.hasFailedAttempt(target),
        isTrue,
      );
      expect(
        await FullTextExtractionService.instance.extractFullText(
          target,
          forceRefresh: true,
        ),
        isNull,
      );
      expect(counts['/rss/articles/CBMiDead'], 2);
    });
  });
}
