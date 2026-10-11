import 'package:ice_cream_rss_reader/services/opml_service.dart';
import 'package:ice_cream_rss_reader/models/feed_subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = OpmlService();

  group('parseOpml', () {
    test('parses a flat structure into Imported', () {
      final subs = service.parseOpml('''
<opml version="2.0"><body>
  <outline text="A" xmlUrl="https://a.com/feed" />
  <outline text="B" xmlUrl="https://b.com/feed" />
</body></opml>''');
      expect(subs.map((s) => s.url), [
        'https://a.com/feed',
        'https://b.com/feed',
      ]);
      expect(subs.every((s) => s.category == 'Imported'), isTrue);
    });

    test('parses nested folders with categories', () {
      final subs = service.parseOpml('''
<opml version="2.0"><body>
  <outline text="Tech">
    <outline text="T1" xmlUrl="https://t1.com/feed" />
  </outline>
  <outline text="News">
    <outline text="N1" xmlUrl="https://n1.com/feed" />
    <outline text="N2" xmlUrl="https://n2.com/feed" />
  </outline>
</body></opml>''');
      expect(subs.length, 3);
      expect(subs[0].category, 'Tech');
      expect(subs[2].category, 'News');
    });

    test('mixed folder + root feeds keeps the root feeds (#53)', () {
      // Real-world exports (Feedly et al.) put loose feeds at top level
      // alongside folders — they must not be silently dropped.
      final subs = service.parseOpml('''
<opml version="2.0"><body>
  <outline text="Loose" xmlUrl="https://loose.com/feed" />
  <outline text="Folder">
    <outline text="Inner" xmlUrl="https://inner.com/feed" />
  </outline>
  <outline text="Loose2" xmlUrl="https://loose2.com/feed" />
</body></opml>''');
      expect(
        subs.map((s) => s.url),
        containsAll(<String>[
          'https://loose.com/feed',
          'https://inner.com/feed',
          'https://loose2.com/feed',
        ]),
      );
      expect(subs.length, 3);
      // Root-level feeds keep a real category label.
      final loose = subs.firstWhere((s) => s.url == 'https://loose.com/feed');
      expect(loose.category, 'Imported');
    });

    test('returns empty for invalid XML and missing body', () {
      expect(service.parseOpml('not xml'), isEmpty);
      expect(service.parseOpml('<opml/>'), isEmpty);
      expect(service.parseOpml('<opml><body/></opml>'), isEmpty);
    });

    test('folder-less feeds mixed with empty folders still parse', () {
      // A folder outline with no feed children must not break flat parsing.
      final subs = service.parseOpml('''
<opml version="2.0"><body>
  <outline text="EmptyFolder"></outline>
  <outline text="A" xmlUrl="https://a.com/feed" />
</body></opml>''');
      expect(subs.map((s) => s.url), ['https://a.com/feed']);
    });
  });

  group('generateOpml → parseOpml round-trip', () {
    test('exported subscriptions parse back with categories', () {
      final out = service.generateOpml([
        FeedSubscription(url: 'https://a.com/f', name: 'A', category: 'Tech'),
        FeedSubscription(url: 'https://b.com/f', name: 'B', category: 'News'),
      ]);
      final back = service.parseOpml(out);
      expect(back.length, 2);
      expect(back.first.category, 'Tech');
    });
  });
}
