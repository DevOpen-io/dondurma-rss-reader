import 'package:flutter/material.dart';

/// The add action in the middle of the bottom navigation: always there, in
/// the theme color, named for what it adds on the current tab. It is not a
/// tab — tapping it opens the add sheet and the selection stays put.
class AddDestination extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const AddDestination({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
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
            const SizedBox(height: 4),
            // The bar's labels share a fixed height; large system text is
            // clamped as theirs is.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
