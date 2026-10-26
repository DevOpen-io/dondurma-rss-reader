import 'dart:convert';

import '../models/feed_item.dart';

/// Read marks per source instance `(feedUrl, id)`: two feeds sharing a GUID
/// are different articles. Legacy global `readItemIds` stay untouched on
/// disk; each legacy id binds once, to the instances present when it is
/// first seen, so a later source with the same GUID inherits nothing.
class ReadState {
  ReadState._(this._refs, this._pending);

  /// [stored] is the persisted `readItemRefs` value; null means first run on
  /// this schema, so every legacy id starts as unresolved history.
  factory ReadState.migrate({
    required Iterable<String> legacyIds,
    required Map<dynamic, dynamic>? stored,
  }) {
    if (stored == null) return ReadState._({}, legacyIds.toSet());
    return ReadState._(
      {for (final ref in stored['refs'] as List? ?? const []) ref.toString()},
      {
        for (final id in stored['pendingLegacy'] as List? ?? const [])
          id.toString(),
      },
    );
  }

  final Set<String> _refs;
  final Set<String> _pending;

  /// Typed, collision-free instance key.
  static String keyOf(String feedUrl, String id) => jsonEncode([feedUrl, id]);
  static String _key(FeedItem item) => keyOf(item.feedUrl, item.id);

  Set<String> get pendingLegacy => Set.unmodifiable(_pending);

  bool isRead(FeedItem item) => _refs.contains(_key(item));

  /// Returns whether the state changed.
  bool mark(FeedItem item, {required bool read}) =>
      read ? _refs.add(_key(item)) : _refs.remove(_key(item));

  /// Binds unresolved legacy ids to the instances of [items]. Every instance
  /// of an id in this batch inherits the mark — that is how they looked
  /// before the migration. Returns whether anything changed.
  bool bindLegacy(Iterable<FeedItem> items) {
    if (_pending.isEmpty) return false;
    final bound = <String>{};
    for (final item in items) {
      if (!_pending.contains(item.id)) continue;
      _refs.add(_key(item));
      bound.add(item.id);
    }
    _pending.removeAll(bound);
    return bound.isNotEmpty;
  }

  /// Above [cap] marks, keeps only marks of still-reachable [live] items.
  void prune({required Iterable<FeedItem> live, required int cap}) {
    if (_refs.length <= cap) return;
    final keep = {for (final item in live) _key(item)};
    _refs.removeWhere((ref) => !keep.contains(ref));
  }

  void clear() {
    _refs.clear();
    _pending.clear();
  }

  Map<String, Object> toStored() => {
    'version': 1,
    'refs': _refs.toList(),
    'pendingLegacy': _pending.toList(),
  };
}
