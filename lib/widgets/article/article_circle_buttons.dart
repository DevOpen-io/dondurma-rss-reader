import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Transparent 48x48 tap target around a 36px visual circle — the icon and
/// layout stay identical while the control meets the 48dp minimum.
class _CircleTarget extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final Color color;
  final Widget child;

  const _CircleTarget({
    required this.onPressed,
    required this.label,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CircleBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const CircleBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      // SliverAppBar's default leadingWidth is 56: 48 target + 4 padding.
      padding: const EdgeInsets.all(4),
      child: _CircleTarget(
        onPressed: onPressed,
        label: AppLocalizations.of(context).back,
        color: colorScheme.surface.withValues(alpha: 0.7),
        child: Icon(
          Icons.arrow_back_rounded,
          size: 20,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}

class CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isActive;

  const CircleActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isActive ? colorScheme.primary : colorScheme.onSurface;

    final button = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: _CircleTarget(
        onPressed: onPressed,
        label: tooltip ?? '',
        color: isActive
            ? colorScheme.primary.withValues(alpha: 0.2)
            : colorScheme.surface.withValues(alpha: 0.7),
        child: Icon(icon, size: 18, color: color),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
