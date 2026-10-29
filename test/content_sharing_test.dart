import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/article_identity.dart';
import 'package:ice_cream_rss_reader/services/article_media_store.dart';
import 'package:ice_cream_rss_reader/services/article_preparation_service.dart';
import 'package:ice_cream_rss_reader/services/article_record_store.dart';
import 'package:ice_cream_rss_reader/services/observed_article_persistence_io.dart';

FeedItem _item(String feed, {String title = 'Same story'}) => FeedItem(
  id: 'guid-1',
  siteName: feed,
  title: title,
  description: '',
  feedUrl: 'https://$feed.test/rss',
  link: 'https://news.test/story',
  content: '<p>Excerpt from $feed</p>',
);

/// Longer than the excerpt — an extraction that only repeats the RSS body
/// is not saved as full text.
final _fullText = '<p>Full text</p><p>${'Story paragraph. ' * 20}</p>';

void main() {
  late Directory root;
  late ArticleRecordStore records;
  late int extractions;
  late ArticlePreparationService prep;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('content-sharing-');
    records = ArticleRecordStore(
      FileObservedArticlePersistence(
        stateFile: File('${root.path}/archive.json'),
      ),
    );
    extractions = 0;
    prep = ArticlePreparationService(
      recordStore: records,
      mediaStore: ArticleMediaStore(root: Directory('${root.path}/media')),
      minHostGap: Duration.zero,
      client: MockClient((_) async => http.Response('', 404)),
      extractFullText: (_) async {
        extractions++;
        return _fullText;
      },
    );
  });
  tearDown(() async {
    prep.dispose();
    await root.delete(recursive: true);
  });

  test('a proven same article from another source reuses the extracted body '
      'as its own copy', () async {
    final a = _item('a');
    final b = _item('b');
    await prep.registerArticle(a, {'bookmark'});
    await prep.prepareArticle(ArticleRef.of(a));
    expect(extractions, 1);

    await prep.registerArticle(b, {'bookmark'});
    final copy = (await records.read(ArticleRef.of(b)))!;
    expect(copy.body, _fullText);
    expect(copy.bodyState, MediaState.ready);
    expect(copy.bodySource, 'extracted');
    expect(copy.feedUrl, b.feedUrl);
    await prep.prepareArticle(ArticleRef.of(b));
    expect(extractions, 1, reason: 'Already proven content is not refetched');

    // Separate records: changing one never changes the other.
    await records.mutate(
      ArticleRef.of(a),
      (current) => current!.copyWith(body: () => '<p>Edited</p>'),
    );
    expect((await records.read(ArticleRef.of(b)))!.body, _fullText);
  });

  test('without matching title the instances stay fully independent', () async {
    final a = _item('a');
    final b = _item('b', title: 'Different story, same link');
    await prep.registerArticle(a, {'bookmark'});
    await prep.prepareArticle(ArticleRef.of(a));
    await prep.registerArticle(b, {'bookmark'});
    final own = (await records.read(ArticleRef.of(b)))!;
    expect(own.body, '<p>Excerpt from b</p>');
    expect(own.bodyState, MediaState.pending);
  });
}
