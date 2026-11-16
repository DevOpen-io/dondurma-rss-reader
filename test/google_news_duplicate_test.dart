import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/feed_list_filter.dart';
import 'package:ice_cream_rss_reader/services/feed_service.dart';

// Shape of a live news.google.com search feed: one story syndicated by two
// publishers arrives as two items with their own article ids, the same
// headline and a " - Publisher" suffix naming the copy's outlet.
const _search =
    'https://news.google.com/rss/search?q=bitcoin&hl=en-US&gl=US&ceid=US:en';
const _topic =
    'https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx6TVdZU0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en';

String _item(
  String title,
  String id,
  String date,
  String source,
  String sourceUrl,
) =>
    '''
<item><title>$title - $source</title><link>https://news.google.com/rss/articles/$id?oc=5</link><guid isPermaLink="false">$id</guid><pubDate>$date</pubDate><description>&lt;a href="https://news.google.com/rss/articles/$id?oc=5" target="_blank"&gt;$title&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;$source&lt;/font&gt;</description><source url="$sourceUrl">$source</source></item>''';

String _feed(String title, List<String> items) =>
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><generator>NFE/5.0</generator><title>$title</title><link>https://news.google.com/</link><language>en-US</language><description>Google News</description>${items.join()}</channel></rss>''';

const _fool = "Galaxy Digital Says Now Is the Time to Buy Bitcoin. Here&apos;s Why It&apos;s Right.";

List<FeedItem> _parse(String url, String body) => FeedService.parseFeedBody((
  bodyBytes: utf8.encode(body),
  category: 'News',
  url: url,
  contentType: 'application/xml',
));

List<FeedItem> _view(Iterable<FeedItem> items) => applyFeedFilters(
  items: items,
  isRead: (_) => false,
  selectedCategory: null,
  selectedFeedUrl: null,
  searchQuery: '',
  readFilter: 'all',
  filterCategories: const {},
  globalKeywords: const [],
  feedKeywordsMap: const {},
).toList();

void main() {
  test('one story syndicated by two publishers lists once', () {
    final items = _parse(
      _search,
      _feed('"bitcoin" - Google News', [
        _item(
          _fool,
          'CBMiAAA1',
          'Mon, 16 Nov 2026 01:51:11 GMT',
          'Yahoo Finance',
          'https://finance.yahoo.com',
        ),
        _item(
          _fool,
          'CBMiAAA2',
          'Mon, 16 Nov 2026 01:11:00 GMT',
          'The Motley Fool',
          'https://www.fool.com',
        ),
        _item(
          'Bitcoin ETFs Lose \$2.1 Billion in November',
          'CBMiAAA3',
          'Sun, 15 Nov 2026 14:01:02 GMT',
          'Decrypt',
          'https://decrypt.co',
        ),
      ]),
    );
    expect(items, hasLength(3), reason: 'parsing keeps every copy');

    final view = _view(items);
    expect(view.map((i) => i.title), [
      "Galaxy Digital Says Now Is the Time to Buy Bitcoin. Here's Why It's Right. - Yahoo Finance",
      'Bitcoin ETFs Lose \$2.1 Billion in November - Decrypt',
    ]);
    // The provider groups copies (read marks, unread badges) by this key.
    expect(articleKey(items[0]), articleKey(items[1]));
  });

  test('a hyphenated publisher name is stripped as one suffix', () {
    final items = _parse(
      _search,
      _feed('G', [
        _item(
          'Gulf talks resume',
          'CBMiB1',
          'Mon, 16 Nov 2026 08:00:00 GMT',
          'Al-Monitor',
          'https://www.al-monitor.com',
        ),
        _item(
          'Gulf talks resume',
          'CBMiB2',
          'Mon, 16 Nov 2026 08:20:00 GMT',
          'Reuters',
          'https://www.reuters.com',
        ),
      ]),
    );
    expect(_view(items), hasLength(1));
  });

  test('the same item in two Google News feeds still lists once', () {
    String body(String t) => _feed(t, [
      _item(
        'Fed holds rates',
        'CBMiC1',
        'Mon, 16 Nov 2026 08:00:00 GMT',
        'CNBC',
        'https://www.cnbc.com',
      ),
    ]);
    final view = _view([
      ..._parse(_search, body('"fed" - Google News')),
      ..._parse(_topic, body('Business - Latest - Google News')),
    ]);
    expect(view, hasLength(1));
  });

  test('a recurring headline on another day is a different story', () {
    final items = _parse(
      _search,
      _feed('G', [
        _item(
          'Stock market today',
          'CBMiD1',
          'Mon, 16 Nov 2026 14:00:00 GMT',
          'CNBC',
          'https://www.cnbc.com',
        ),
        _item(
          'Stock market today',
          'CBMiD2',
          'Fri, 13 Nov 2026 14:00:00 GMT',
          'CNBC',
          'https://www.cnbc.com',
        ),
      ]),
    );
    expect(_view(items), hasLength(2));
  });

  test('same-titled items outside Google News are left alone', () {
    const body = '''<rss version="2.0"><channel><title>Blog</title>
<item><title>Weekly links - Blog</title><link>https://blog.test/1</link><pubDate>Mon, 16 Nov 2026 08:00:00 GMT</pubDate></item>
<item><title>Weekly links - Blog</title><link>https://blog.test/2</link><pubDate>Mon, 16 Nov 2026 09:00:00 GMT</pubDate></item>
</channel></rss>''';
    expect(_view(_parse('https://blog.test/feed', body)), hasLength(2));
  });
}
