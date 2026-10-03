import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/services/feed_decisions.dart';
import 'package:ice_cream_rss_reader/widgets/feed_list_item.dart';

void main() {
  group('feedPassesRuntimeFilter', () {
    test('all + no categories passes everything', () {
      expect(
        feedPassesRuntimeFilter(
          isRead: true,
          category: 'Tech',
          readFilter: 'all',
          categories: const {},
        ),
        isTrue,
      );
      expect(
        feedPassesRuntimeFilter(
          isRead: false,
          category: 'Tech',
          readFilter: 'all',
          categories: const {},
        ),
        isTrue,
      );
    });

    test('unread filter drops read items', () {
      expect(
        feedPassesRuntimeFilter(
          isRead: true,
          category: 'Tech',
          readFilter: 'unread',
          categories: const {},
        ),
        isFalse,
      );
      expect(
        feedPassesRuntimeFilter(
          isRead: false,
          category: 'Tech',
          readFilter: 'unread',
          categories: const {},
        ),
        isTrue,
      );
    });

    test('read filter drops unread items', () {
      expect(
        feedPassesRuntimeFilter(
          isRead: false,
          category: 'Tech',
          readFilter: 'read',
          categories: const {},
        ),
        isFalse,
      );
      expect(
        feedPassesRuntimeFilter(
          isRead: true,
          category: 'Tech',
          readFilter: 'read',
          categories: const {},
        ),
        isTrue,
      );
    });

    test('category set keeps only matching categories', () {
      expect(
        feedPassesRuntimeFilter(
          isRead: false,
          category: 'Tech',
          readFilter: 'all',
          categories: const {'Tech', 'News'},
        ),
        isTrue,
      );
      expect(
        feedPassesRuntimeFilter(
          isRead: false,
          category: 'Sports',
          readFilter: 'all',
          categories: const {'Tech', 'News'},
        ),
        isFalse,
      );
    });

    test('read status and categories combine with AND', () {
      expect(
        feedPassesRuntimeFilter(
          isRead: true,
          category: 'Tech',
          readFilter: 'unread',
          categories: const {'Tech'},
        ),
        isFalse,
      );
      expect(
        feedPassesRuntimeFilter(
          isRead: false,
          category: 'Tech',
          readFilter: 'unread',
          categories: const {'Tech'},
        ),
        isTrue,
      );
    });
  });

  group('truncateLabel', () {
    test('short text unchanged', () {
      expect(truncateLabel('Tech', 14), 'Tech');
    });

    test('exact-limit text unchanged', () {
      expect(truncateLabel('a' * 14, 14), 'a' * 14);
    });

    test('long text cut with ellipsis at limit', () {
      final result = truncateLabel('"site:apnews.com" - Google News', 20);
      expect(result.length, 20);
      expect(result.endsWith('…'), isTrue);
      expect(result, '"site:apnews.com" -…');
    });
  });
}
