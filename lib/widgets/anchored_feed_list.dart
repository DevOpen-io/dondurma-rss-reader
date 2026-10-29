import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../models/feed_item.dart';

/// GUIDs are source-local. Occurrences also avoid duplicate widget keys when
/// a source supplies the same GUID twice.
List<Object> articleRowIds(Iterable<FeedItem> items) {
  final occurrences = <(String, String), int>{};
  return [
    for (final item in items)
      (
        item.feedUrl,
        item.id,
        occurrences.update(
          (item.feedUrl, item.id),
          (n) => n + 1,
          ifAbsent: () => 0,
        ),
      ),
  ];
}

/// Offset 0 is the rebased center, not the head. Callers asking for 0 (e.g.
/// the iOS status-bar tap through [PrimaryScrollController]) mean "top".
class AnchoredScrollController extends ScrollController {
  double _resolve(double offset) =>
      offset == 0 && hasClients ? position.minScrollExtent : offset;

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) => super.animateTo(_resolve(offset), duration: duration, curve: curve);

  @override
  void jumpTo(double value) => super.jumpTo(_resolve(value));
}

/// A lazy, single-viewport list that keeps a visible article stationary when
/// results are inserted, reordered or removed. IDs must be unique per row;
/// headers/footers should return false from [isArticle].
///
/// Rebasing the sliver center to a surviving visible article avoids estimating
/// heights of newly inserted, off-screen rows. Both sides remain lazy slivers
/// in ONE viewport (not a pair of synchronized scrollables).
class AnchoredFeedList extends StatefulWidget {
  const AnchoredFeedList({
    super.key,
    required this.rowIds,
    required this.itemBuilder,
    this.isArticle,
    this.controller,
    this.physics,
    this.cacheExtent = 200,
    this.onArticlesScrolledPast,
  });

  final List<Object> rowIds;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function(int index)? isArticle;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final double cacheExtent;

  /// Called once a scroll has settled with the indexes of the article rows
  /// the user scrolled past: rows that were on screen and then left through
  /// the top edge while scrolling down. Rows a rebuild inserted or moved
  /// above the screen are not reported, and each row is reported once.
  /// Batching keeps the caller's rebuild away from the finger.
  final void Function(List<int> indexes)? onArticlesScrolledPast;

  @override
  State<AnchoredFeedList> createState() => _AnchoredFeedListState();
}

class _AnchoredFeedListState extends State<AnchoredFeedList> {
  final _ownController = AnchoredScrollController();
  final _viewportKey = GlobalKey();
  final _centerKey = GlobalKey();
  final _rowKeys = <Object, GlobalKey>{};
  // Row index of each ID in the last built rowIds.
  var _indexes = <Object, int>{};
  Object? _centerId;
  double? _pendingPixels;
  // Scrolled-past tracking: rows on screen at the last check, rows passed
  // but not reported yet, and rows already passed.
  var _visibleIds = <Object>{};
  final _pendingIds = <Object>{};
  final _passedIds = <Object>{};
  var _scrolledDown = false;
  var _rowsMoved = false;
  var _passCheckScheduled = false;
  Timer? _reportTimer;

  ScrollController get _controller => widget.controller ?? _ownController;

  @override
  void initState() {
    super.initState();
    _centerId = widget.rowIds.firstOrNull;
  }

  @override
  void didUpdateWidget(covariant AnchoredFeedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Identical IDs can still carry new titles, text scale or row heights.
    _captureAnchor(oldWidget);
    if (!listEquals(oldWidget.rowIds, widget.rowIds)) _rowsMoved = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _captureAnchor(widget);
  }

  void _captureAnchor(AnchoredFeedList oldWidget) {
    final remaining = widget.rowIds.toSet();
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    Object? anchor;
    double? anchorY;
    final distanceFromTop = _controller.hasClients
        ? (_controller.position.pixels - _controller.position.minScrollExtent)
              .clamp(0.0, double.infinity)
        : 0.0;
    if (_controller.hasClients &&
        viewport != null &&
        viewport.attached &&
        viewport.hasSize &&
        _controller.position.pixels >
            _controller.position.minScrollExtent + 0.5) {
      // Only mounted rows can be visible: walk keys, not every row ID.
      for (final MapEntry(key: id, value: key) in _rowKeys.entries) {
        final index = _indexes[id];
        if (index == null ||
            !remaining.contains(id) ||
            !(oldWidget.isArticle?.call(index) ?? true)) {
          continue;
        }
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        // A kept-alive offscreen row can still be attached and sized, but its
        // transform is singular. NaN comparisons do not reject it as offscreen;
        // using that coordinate would poison the viewport's scroll offset.
        if (!y.isFinite ||
            !box.size.height.isFinite ||
            y + box.size.height <= 0 ||
            y >= viewport.size.height) {
          continue;
        }
        if (anchorY == null || y < anchorY) {
          anchor = id;
          anchorY = y;
        }
      }
    }
    _centerId = anchor ?? widget.rowIds.firstOrNull;
    // At the top show the new head. If every visible article disappeared,
    // retain the previous distance from the head; layout clamps it to bounds.
    _pendingPixels = anchorY == null ? distanceFromTop : -anchorY;
    // Disposed offscreen rows get a fresh key when rebuilt; dropping them
    // keeps the map bounded by mounted rows instead of rows ever seen.
    _rowKeys.removeWhere(
      (id, key) => !remaining.contains(id) || key.currentContext == null,
    );
    _visibleIds.retainAll(remaining);
    _pendingIds.retainAll(remaining);
    _passedIds.retainAll(remaining);
  }

  bool _onScroll(ScrollNotification notification) {
    if (widget.onArticlesScrolledPast == null || notification.depth != 0) {
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      if ((notification.scrollDelta ?? 0) > 0) _scrolledDown = true;
      _reportTimer?.cancel();
      _schedulePassCheck();
    } else if (notification is ScrollEndNotification) {
      _schedulePassCheck();
      // Wheel ticks each end a scroll; wait for the burst to settle.
      _reportTimer?.cancel();
      _reportTimer = Timer(const Duration(milliseconds: 300), _reportPassed);
    }
    return false;
  }

  // Row geometry is only current after layout, so look once per frame.
  void _schedulePassCheck() {
    if (_passCheckScheduled) return;
    _passCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passCheckScheduled = false;
      if (mounted) _checkScrolledPast();
    });
  }

  void _checkScrolledPast() {
    final down = _scrolledDown;
    final moved = _rowsMoved;
    _scrolledDown = false;
    _rowsMoved = false;
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.attached || !viewport.hasSize) return;
    final visible = <Object>{};
    int? firstVisible;
    for (final MapEntry(key: id, value: key) in _rowKeys.entries) {
      final index = _indexes[id];
      if (index == null) continue;
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (!y.isFinite) continue; // Kept-alive offscreen row, see above.
      if (y + box.size.height <= 0 || y >= viewport.size.height) continue;
      visible.add(id);
      if (firstVisible == null || index < firstVisible) firstVisible = index;
    }
    // A row that was on screen and now lies above the first visible one
    // left through the top edge — even when it is no longer mounted, as a
    // fling can carry it past the cache extent between two frames. After a
    // rebuild that changed the rows, the order moved, not the user.
    if (down && !moved && firstVisible != null) {
      for (final id in _visibleIds) {
        final index = _indexes[id];
        if (index != null &&
            index < firstVisible &&
            (widget.isArticle?.call(index) ?? true) &&
            _passedIds.add(id)) {
          _pendingIds.add(id);
        }
      }
    }
    _visibleIds = visible;
  }

  void _reportPassed() {
    final report = widget.onArticlesScrolledPast;
    final indexes = [for (final id in _pendingIds) ?_indexes[id]]..sort();
    _pendingIds.clear();
    if (report != null && indexes.isNotEmpty) report(indexes);
  }

  @override
  void dispose() {
    _reportTimer?.cancel();
    // Leaving the list mid-scroll still reports what was passed — after
    // this frame, outside the tree teardown.
    final report = widget.onArticlesScrolledPast;
    final indexes = [for (final id in _pendingIds) ?_indexes[id]]..sort();
    if (report != null && indexes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => report(indexes));
    }
    _ownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Capture the old geometry before a viewport/text-scale dependency change
    // lays out variable-height rows with its new constraints.
    MediaQuery.maybeSizeOf(context);
    MediaQuery.maybeTextScalerOf(context);
    assert(widget.rowIds.toSet().length == widget.rowIds.length);
    final indexes = _indexes = {
      for (var i = 0; i < widget.rowIds.length; i++) widget.rowIds[i]: i,
    };
    final split = _centerId == null ? 0 : (indexes[_centerId!] ?? 0);
    // Records what this layout puts on screen.
    if (widget.onArticlesScrolledPast != null) _schedulePassCheck();
    final keyIndexes = {
      for (final e in _rowKeys.entries) e.value: indexes[e.key],
    };
    Widget row(BuildContext context, int index) {
      final id = widget.rowIds[index];
      return KeyedSubtree(
        key: _rowKeys.putIfAbsent(id, GlobalKey.new),
        child: widget.itemBuilder(context, index),
      );
    }

    return SizedBox.expand(
      key: _viewportKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pixels = _pendingPixels;
          if (pixels != null && _controller.hasClients) {
            // Applied during layout, before the single viewport reads its offset.
            _controller.position.correctBy(
              pixels - _controller.position.pixels,
            );
            _pendingPixels = null;
          }
          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              controller: _controller,
              physics: widget.physics,
              center: _centerKey,
              semanticChildCount: widget.rowIds.length,
              scrollCacheExtent: ScrollCacheExtent.pixels(widget.cacheExtent),
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => row(context, split - index - 1),
                    childCount: split,
                    semanticIndexCallback: (_, index) => split - index - 1,
                    findChildIndexCallback: (key) {
                      final index = keyIndexes[key];
                      return index != null && index < split
                          ? split - index - 1
                          : null;
                    },
                  ),
                ),
                SliverList(
                  key: _centerKey,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => row(context, split + index),
                    childCount: widget.rowIds.length - split,
                    semanticIndexCallback: (_, index) => split + index,
                    findChildIndexCallback: (key) {
                      final index = keyIndexes[key];
                      return index != null && index >= split
                          ? index - split
                          : null;
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
