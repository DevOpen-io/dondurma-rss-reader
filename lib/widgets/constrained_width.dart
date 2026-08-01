import 'package:flutter/widgets.dart';

/// Caps content width for readability on large screens (tablets, unfolded
/// foldables) and centers it — mirrors the article screen's 680px column so
/// list rows never stretch edge-to-edge.
class ConstrainedWidth extends StatelessWidget {
  const ConstrainedWidth({super.key, required this.child, this.maxWidth = 680});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
