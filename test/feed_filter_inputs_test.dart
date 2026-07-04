import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/providers/feed_provider.dart';

void main() {
  group('FeedProvider.filterInputsChanged', () {
    const global = ['spam', 'clickbait'];
    const feedKw = {
      'https://a': ['crypto'],
    };
    const bookmarks = {'id-1', 'id-2'};

    test('reports changed when no previous snapshot exists', () {
      expect(
        FeedProvider.filterInputsChanged(
          prevGlobalKeywords: null,
          nextGlobalKeywords: global,
          prevFeedKeywords: null,
          nextFeedKeywords: feedKw,
          prevBookmarkIds: null,
          nextBookmarkIds: bookmarks,
        ),
        isTrue,
      );
    });

    test('reports unchanged for identical inputs', () {
      expect(
        FeedProvider.filterInputsChanged(
          prevGlobalKeywords: ['spam', 'clickbait'],
          nextGlobalKeywords: global,
          prevFeedKeywords: {
            'https://a': ['crypto'],
          },
          nextFeedKeywords: feedKw,
          prevBookmarkIds: {'id-2', 'id-1'},
          nextBookmarkIds: bookmarks,
        ),
        isFalse,
      );
    });

    test('detects global keyword change', () {
      expect(
        FeedProvider.filterInputsChanged(
          prevGlobalKeywords: ['spam'],
          nextGlobalKeywords: global,
          prevFeedKeywords: feedKw,
          nextFeedKeywords: feedKw,
          prevBookmarkIds: bookmarks,
          nextBookmarkIds: bookmarks,
        ),
        isTrue,
      );
    });

    test('detects per-feed keyword change', () {
      expect(
        FeedProvider.filterInputsChanged(
          prevGlobalKeywords: global,
          nextGlobalKeywords: global,
          prevFeedKeywords: {
            'https://a': ['crypto', 'nft'],
          },
          nextFeedKeywords: feedKw,
          prevBookmarkIds: bookmarks,
          nextBookmarkIds: bookmarks,
        ),
        isTrue,
      );
    });

    test('detects per-feed keyword map key change', () {
      expect(
        FeedProvider.filterInputsChanged(
          prevGlobalKeywords: global,
          nextGlobalKeywords: global,
          prevFeedKeywords: {
            'https://b': ['crypto'],
          },
          nextFeedKeywords: feedKw,
          prevBookmarkIds: bookmarks,
          nextBookmarkIds: bookmarks,
        ),
        isTrue,
      );
    });

    test('detects bookmark toggle', () {
      expect(
        FeedProvider.filterInputsChanged(
          prevGlobalKeywords: global,
          nextGlobalKeywords: global,
          prevFeedKeywords: feedKw,
          nextFeedKeywords: feedKw,
          prevBookmarkIds: {'id-1'},
          nextBookmarkIds: bookmarks,
        ),
        isTrue,
      );
    });

    test('ignores unrelated input (same snapshots)', () {
      // Theme/search-history style changes never reach these inputs, so
      // identical snapshots must report unchanged.
      expect(
        FeedProvider.filterInputsChanged(
          prevGlobalKeywords: const [],
          nextGlobalKeywords: const [],
          prevFeedKeywords: const {},
          nextFeedKeywords: const {},
          prevBookmarkIds: const {},
          nextBookmarkIds: const {},
        ),
        isFalse,
      );
    });
  });
}
