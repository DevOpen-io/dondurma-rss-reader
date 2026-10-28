import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';

FeedItem _fromTitle(String title, {String siteName = 'Site'}) =>
    FeedItem.fromJson({'id': 'a', 'title': title, 'siteName': siteName});

void main() {
  group('FeedItem.fromJson text decoding', () {
    test('decodes entities left in older caches', () {
      expect(_fromTitle('Tom &amp; Jerry').title, 'Tom & Jerry');
      expect(_fromTitle('&#8216;Quoted&#8217;').title, '‘Quoted’');
      expect(_fromTitle('x', siteName: 'A &amp; B').siteName, 'A & B');
    });

    test('keeps literal angle brackets — stored titles are decoded text', () {
      expect(
        _fromTitle('Why the <video> tag & codecs matter').title,
        'Why the <video> tag & codecs matter',
      );
      expect(_fromTitle('a <b> &amp; c').title, 'a <b> & c');
    });

    test('plain text passes through unchanged', () {
      expect(_fromTitle('Plain headline').title, 'Plain headline');
      expect(_fromTitle('Q&A session').title, 'Q&A session');
    });
  });
}
