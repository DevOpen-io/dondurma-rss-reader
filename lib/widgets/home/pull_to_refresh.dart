import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pull-to-refresh for the feed list. A circle fills as the list is pulled
/// past its top; letting go once it is full refreshes, letting go earlier
/// (or pulling back) does nothing. Only the finger counts — a fling that
/// bounces off the top never refreshes.
///
/// The child must scroll with bouncing physics, so a pull overscrolls the
/// top. While the refresh runs, the screen's own progress shows it; the
/// circle is only the gesture's feedback.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// How far the list must be pulled past its top (after the bounce's
  /// resistance) to fill the circle: about 160dp (2.5 cm) of finger travel.
  static const double threshold = 70;

  /// The filling circle, for tests.
  static const progressKey = ValueKey('pull-to-refresh-progress');

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  double _pull = 0;
  bool _armed = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final overscroll = math.max(
      0.0,
      n.metrics.minScrollExtent - n.metrics.pixels,
    );
    final dragging = switch (n) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (dragging) {
      _setPull(overscroll);
    } else if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      // The finger is off the screen: the list springs back on its own.
      if (_armed) {
        unawaited(widget.onRefresh());
      }
      _setPull(0);
    }
    return false;
  }

  void _setPull(double pull) {
    final armed = pull >= PullToRefresh.threshold;
    if (armed && !_armed) unawaited(HapticFeedback.mediumImpact());
    if (pull == _pull && armed == _armed) return;
    setState(() {
      _pull = pull;
      _armed = armed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = (_pull / PullToRefresh.threshold).clamp(0.0, 1.0);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (_pull > 0)
            Positioned(
              // Follows the pull at half its speed, never past the gap the
              // pull opened above the list.
              top: math.min(_pull, PullToRefresh.threshold) / 2 - 18,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: math.min(1, progress * 2),
                    child: Material(
                      type: MaterialType.circle,
                      color: cs.surfaceContainerHigh,
                      elevation: _armed ? 3 : 1,
                      child: SizedBox.square(
                        dimension: 36,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.square(
                              dimension: 26,
                              child: CircularProgressIndicator(
                                key: PullToRefresh.progressKey,
                                value: progress,
                                strokeWidth: 2.5,
                                color: cs.primary,
                                backgroundColor: cs.primary.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                            ),
                            Transform.rotate(
                              angle: progress * math.pi,
                              child: Icon(
                                Icons.refresh_rounded,
                                size: 16,
                                color: _armed
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
