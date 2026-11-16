import 'package:flutter/material.dart';

/// The add action in the middle of the bottom navigation: always there, in
/// the theme color, named for what it adds on the current tab. It is not a
/// tab — tapping it opens the add sheet and the selection stays put.
class AddDestination extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// Shows [label] under the button; the side rail of a landscape phone has
  /// no height for it and names it in a tooltip instead.
  final bool showLabel;

  const AddDestination({
    super.key,
    required this.label,
    required this.onPressed,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final button = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 34,
              decoration: ShapeDecoration(
                color: cs.primary,
                shape: const StadiumBorder(),
                shadows: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 24),
            ),
            if (showLabel) ...[
              const SizedBox(height: 4),
              // The bar's labels share a fixed height; large system text is
              // clamped as theirs is.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                // A longer name ("Add category") shrinks to fit its slot,
                // keeping the tabs' margin so it never meets their labels.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    // The button already carries the label for screen readers.
    return showLabel
        ? button
        : Tooltip(message: label, excludeFromSemantics: true, child: button);
  }
}
