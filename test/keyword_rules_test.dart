import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/feed_list_filter.dart';

FeedItem _item(
  String id,
  String title, {
  String body = '',
  String feed = 'a',
}) => FeedItem(
  id: id,
  siteName: feed,
  title: title,
  description: body,
  feedUrl: 'https://$feed.test/feed',
  link: 'https://$feed.test/$id',
);

List<String> _ids(Iterable<FeedItem> items) => [for (final i in items) i.id];

Iterable<FeedItem> _filter(
  List<FeedItem> items, {
  List<String> global = const [],
  Map<String, List<String>> feed = const {},
  Map<String, List<String>> only = const {},
}) => applyFeedFilters(
  items: items,
  isRead: (_) => false,
  selectedCategory: null,
  selectedFeedUrl: null,
  searchQuery: '',
  readFilter: 'all',
  filterCategories: const {},
  globalKeywords: global,
  feedKeywordsMap: feed,
  feedOnlyKeywordsMap: only,
);

void main() {
  bool matches(String rule, String title, [String body = '']) =>
      KeywordRule.tryParse(rule)!.matches(title: title, description: body);

  test('plain words match whole words in title or summary, any case', () {
    expect(matches('crypto', 'New Crypto rules'), isTrue);
    expect(matches('crypto', 'Cryptography 101'), isFalse);
    expect(matches('crypto', 'Markets', 'a crypto story'), isTrue);
  });

  test('/regex/ is a case-insensitive regular expression', () {
    expect(matches(r'/^\[ad\]/', '[AD] Buy now'), isTrue);
    expect(matches(r'/^\[ad\]/', 'Read [ad] later'), isFalse);
    expect(matches('/iphone 1[5-7]/', 'iPhone 16 review'), isTrue);
    expect(matches('/a{1,3}b/', 'aab'), isTrue);
  });

  test('title: looks at the title only', () {
    expect(matches('title:sponsored', 'Sponsored post'), isTrue);
    expect(matches('title:sponsored', 'News', 'sponsored by X'), isFalse);
    expect(matches('TITLE: /^live/', 'Live: election'), isTrue);
  });

  test('an invalid or empty rule does not compile', () {
    expect(KeywordRule.tryParse('/(unclosed/'), isNull);
    expect(KeywordRule.tryParse('title:'), isNull);
    expect(KeywordRule.tryParse('   '), isNull);
    // An empty pattern, or bare punctuation that is never a word.
    for (final rule in ['//', '/', '://', 'title: //', '...']) {
      expect(KeywordRule.tryParse(rule), isNull, reason: rule);
    }
    expect(KeywordRule.tryParse('C++'), isNotNull);
  });

  test('an invalid stored rule is skipped, the rest still hide', () {
    final items = [_item('1', 'Crypto news'), _item('2', 'Weather')];
    expect(_ids(_filter(items, global: ['/(bad/', 'crypto'])), ['2']);
  });

  test('"only show" keeps the matching articles of that feed alone', () {
    final items = [
      _item('a1', 'Flutter 4 released'),
      _item('a2', 'Company picnic'),
      _item('b1', 'Company picnic', feed: 'b'),
    ];
    final only = {
      'https://a.test/feed': ['flutter', '/dart/'],
    };
    expect(_ids(_filter(items, only: only)), ['a1', 'b1']);
    // Hiding still applies on top of "only show".
    expect(
      _ids(
        _filter(
          items,
          only: only,
          feed: {
            'https://a.test/feed': ['released'],
          },
        ),
      ),
      ['b1'],
    );
    // A list of only invalid rules keeps everything instead of hiding all.
    expect(
      _ids(
        _filter(
          items,
          only: {
            'https://a.test/feed': ['/(bad/'],
          },
        ),
      ),
      ['a1', 'a2', 'b1'],
    );
  });

  test('unsafe patterns are refused: empty matches, nested repeats', () {
    for (final rule in [
      '/.*/',
      '/a*/',
      '/x|/',
      '/^/',
      r'/(\w+\s?)+$/',
      '/(a+)+b/',
    ]) {
      expect(KeywordRule.tryParse(rule), isNull, reason: rule);
    }
    expect(KeywordRule.tryParse(r'/^\d+ (deals|offers)$/'), isNotNull);
  });

  test('whole words work beyond ASCII', () {
    expect(matches('çay', 'Bir çay molası'), isTrue);
    expect(matches('çay', 'Çaykur haberleri'), isFalse);
    expect(matches('москва', 'Новости: Москва сегодня'), isTrue);
  });

  test('typed input splits at commas but keeps a pattern whole', () {
    expect(KeywordRule.split('crypto, nft'), ['crypto', 'nft']);
    expect(KeywordRule.split('/a{1,3}b/, word'), ['/a{1,3}b/', 'word']);
    expect(KeywordRule.split('/foo/, /bar/'), ['/foo/', '/bar/']);
    expect(KeywordRule.split('title: /x,y/'), ['title: /x,y/']);
  });
}
