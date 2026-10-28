import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ice_cream_rss_reader/models/feed_item.dart';
import 'package:ice_cream_rss_reader/services/read_state.dart';

FeedItem _item(String feed, String id) => FeedItem(
  id: id,
  siteName: feed,
  title: id,
  description: '',
  feedUrl: 'https://$feed.test/rss',
);

void main() {
  test('marks are per source instance, not per shared GUID', () {
    final state = ReadState.migrate(legacyIds: const [], stored: null);
    final a = _item('a', 'shared');
    final b = _item('b', 'shared');
    state.mark(a, read: true);
    expect(state.isRead(a), isTrue);
    expect(state.isRead(b), isFalse);
  });

  test('legacy ids bind once to the instances present when first seen', () {
    final state = ReadState.migrate(legacyIds: ['old', 'later'], stored: null);
    final a = _item('a', 'old');
    expect(state.bindLegacy([a]), isTrue);
    expect(state.isRead(a), isTrue);
    // A source that brings the same GUID later inherits nothing.
    state.bindLegacy([_item('b', 'old')]);
    expect(state.isRead(_item('b', 'old')), isFalse);
    // Unresolved history is kept until an instance appears.
    expect(state.pendingLegacy, {'later'});
  });

  test('legacy binding covers every instance present in the first batch', () {
    final state = ReadState.migrate(legacyIds: ['dup'], stored: null);
    final a = _item('a', 'dup');
    final b = _item('b', 'dup');
    state.bindLegacy([a, b]);
    expect(state.isRead(a), isTrue);
    expect(state.isRead(b), isTrue);
  });

  test('stored state round-trips and is preferred over legacy ids', () {
    final first = ReadState.migrate(legacyIds: ['x'], stored: null);
    final a = _item('a', 'x');
    first.bindLegacy([a]);
    first.mark(a, read: false);
    final restored = ReadState.migrate(
      legacyIds: ['x'],
      stored: first.toStored(),
    );
    expect(restored.isRead(a), isFalse);
    expect(restored.pendingLegacy, isEmpty);
  });

  test('keys are typed, never a delimiter join', () {
    final state = ReadState.migrate(legacyIds: const [], stored: null);
    state.mark(_item('a', 'x|y'), read: true);
    expect(state.isRead(FeedItem.fromJson(_item('a', 'x|y').toJson())), isTrue);
    expect(ReadState.keyOf('a|x', 'y'), isNot(ReadState.keyOf('a', 'x|y')));
  });

  test('pruning above the cap keeps live instances only', () {
    final state = ReadState.migrate(legacyIds: const [], stored: null);
    final live = _item('a', 'live');
    state.mark(live, read: true);
    for (var i = 0; i < 5; i++) {
      state.mark(_item('a', 'gone-$i'), read: true);
    }
    state.prune(live: [live], cap: 3);
    expect(state.isRead(live), isTrue);
    expect(state.toStored()['refs'], hasLength(1));
  });

  test('the stored format is the JSON-encoded instance key', () {
    final key = jsonEncode(['https://a.test/rss', 'x']);
    final state = ReadState.migrate(
      legacyIds: const [],
      stored: {
        'refs': [key, 'not-a-key'],
      },
    );
    expect(state.isRead(_item('a', 'x')), isTrue);
    expect(state.toStored()['refs'], [key]);
  });
}
