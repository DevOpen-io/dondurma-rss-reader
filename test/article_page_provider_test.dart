import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/providers/article_page_provider.dart';

void main() {
  test('a manual full-text failure is reported exactly once', () async {
    final page = ArticlePageProvider(
      item: FeedItem(
        id: 'a',
        siteName: 'Example',
        title: 'Article',
        description: '',
        timeAgo: '',
        siteIcon: Icons.rss_feed,
        iconColor: Colors.blue,
        iconBackgroundColor: Colors.white,
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
}
