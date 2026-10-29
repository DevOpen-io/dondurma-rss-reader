import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/full_text_extraction_service.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

void main() {
  test('a manual full-text failure is reported exactly once', () async {
    final page = ArticlePageProvider(
      item: FeedItem(
        id: 'a',
        siteName: 'Example',
        title: 'Article',
        description: '',
        link: 'https://full-text-failure.test/article',
        feedUrl: 'https://full-text-failure.test/feed',
      ),
    );
    addTearDown(page.dispose);

    await http.runWithClient(
      page.activateFullText,
      () => MockClient((_) async => http.Response('', 404)),
    );

    expect(page.fullTextFailed, isTrue);
    expect(page.consumeFullTextFailure(), isTrue);
    // Later notifications (saved-copy refreshes, settings) keep the failed
    // state but must not report the same failure again.
    expect(page.fullTextFailed, isTrue);
    expect(page.consumeFullTextFailure(), isFalse);
  });

  test('a story body inside an "inread" wrapper survives ad cleanup', () {
    // ntv.com.tr wraps the whole story in `inread-photo-area`; the ad
    // filter's bare `ad-` matched it and left only the headline.
    final page = ArticlePageProvider(
      item: FeedItem(
        id: 'ntv',
        siteName: 'NTV',
        title: 'Süper Loto',
        description: '',
        link: 'https://www.ntv.com.tr/a',
        content: File(
          'test/fixtures/full_text/ntv_inread.html',
        ).readAsStringSync(),
        feedUrl: 'https://www.ntv.com.tr/gundem.rss',
      ),
    );
    addTearDown(page.dispose);

    expect(page.displayContent, contains('Haftanın 3 günü'));
    expect(page.displayContent, contains('Çıkan sayılar şöyle'));
  });

  test('a story wrapper whose class names ad features survives', () {
    // Future plc (gamesradar.com, tomshardware.com) lists every block type
    // the story may hold on its wrapper — `flw-article-sponsored-
    // disclaimer` among them — so the whole story read as sponsored.
    final page = ArticlePageProvider(
      item: FeedItem(
        id: 'future',
        siteName: 'GamesRadar+',
        title: 'Patrick Stewart dies at 86',
        description: '',
        link: 'https://www.gamesradar.com/a',
        content:
            '<div class="widget-content flw-article-text-content '
            'flw-article-sponsored-disclaimer flw-article-product-block">'
            '<p>${'Patrick Stewart, the Star Trek and X-Men actor, has died. ' * 4}</p>'
            '<p>${'His career on stage and screen spanned seven decades. ' * 4}</p>'
            '<div class="sponsored-post"><p>Sponsored: buy the box set.</p></div>'
            '</div>',
        feedUrl: 'https://www.gamesradar.com/feeds.xml',
      ),
    );
    addTearDown(page.dispose);

    expect(page.displayContent, contains('spanned seven decades'));
    expect(page.displayContent, isNot(contains('buy the box set')));
  });

  group('full text that only repeats the feed excerpt', () {
    const excerpt =
        'Spanish football clubs were among those to hold a minute’s '
        'silence for the victims of Wednesday’s train collision.';
    // aljazeera.com video page: headline, the excerpt, a dateline — the
    // page has nothing more to give.
    const echoPage =
        '<html><body><article>'
        '<h1>Real Madrid and FC Barcelona honour Spain train crash '
        'victims</h1>'
        '<p>Spanish football clubs Real Madrid and FC Barcelona were among '
        'those to hold a minute’s silence for the victims of Wednesday’s '
        'train collision, which killed at least 69 people south of '
        'Madrid.</p><p>Published On 29 Oct 2026</p>'
        '</article></body></html>';

    FeedItem item(String link) => FeedItem(
      id: link,
      siteName: 'Al Jazeera',
      title: 'Real Madrid and FC Barcelona honour Spain train crash victims',
      description: excerpt,
      content: '<p>$excerpt</p>',
      link: link,
      feedUrl: 'https://www.aljazeera.com/xml/rss/all.xml',
    );

    setUp(FullTextExtractionService.debugClearSession);

    test('is a manual failure, and a retry fetches the page again', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(
          echoPage,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final page = ArticlePageProvider(item: item('https://echo.test/manual'));
      addTearDown(page.dispose);

      await http.runWithClient(page.activateFullText, () => client);

      expect(page.fullTextActive, isFalse);
      expect(page.fullTextContent, isNull);
      expect(page.fullTextFailed, isTrue);
      expect(page.consumeFullTextFailure(), isTrue);

      // The rejected result is not cached — retry goes back to the page.
      await http.runWithClient(page.activateFullText, () => client);
      expect(requests, 2);
      expect(page.fullTextFailed, isTrue);
    });

    test('is an automatic failure shown as the subtle notice', () async {
      final page = ArticlePageProvider(item: item('https://echo.test/auto'));
      addTearDown(page.dispose);

      await http.runWithClient(
        () => page.activateFullText(automatic: true),
        () => MockClient(
          (_) async => http.Response(
            echoPage,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );

      expect(page.fullTextActive, isFalse);
      expect(page.autoFullTextFailed, isTrue);
      expect(page.fullTextFailed, isFalse);
    });

    test('a saved "extracted" copy is not shown as full text', () async {
      final dir = await Directory.systemTemp.createTemp('echo-saved-');
      addTearDown(() => dir.delete(recursive: true));
      final records = ArticleRecordStore(
        FileObservedArticlePersistence(stateFile: File('${dir.path}/r.json')),
      );
      final article = item('https://echo.test/saved');
      await records.write(
        ArticleRecord(
          id: article.id,
          feedUrl: article.feedUrl,
          link: article.link,
          body: echoPage,
          bodyState: MediaState.ready,
          bodySource: 'extracted',
          owners: const {'tempCache'},
          generation: 1,
        ),
      );
      expect(await records.read(ArticleRef.of(article)), isNotNull);
      final page = ArticlePageProvider(item: article);
      addTearDown(page.dispose);
      await page.loadSavedCopy(
        records: records,
        media: ArticleMediaStore(root: Directory('${dir.path}/media')),
      );

      var requests = 0;
      await http.runWithClient(
        page.activateFullText,
        () => MockClient((_) async {
          requests++;
          return http.Response('', 404);
        }),
      );

      // The saved copy is no better than the excerpt — the page is tried
      // live instead, and its failure is reported.
      expect(requests, 1);
      expect(page.fullTextActive, isFalse);
      expect(page.fullTextFailed, isTrue);
    });
  });
}
