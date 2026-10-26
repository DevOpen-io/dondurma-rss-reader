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
  });

  final List<Object> rowIds;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function(int index)? isArticle;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final double cacheExtent;

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
  }

  @override
  void dispose() {
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
          return CustomScrollView(
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
          );
        },
      ),
    );
  }
}
