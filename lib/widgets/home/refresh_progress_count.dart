import 'package:flutter/material.dart';

import '../../models/refresh_progress.dart';

/// Spinner plus `completed / total` for a running refresh pass. Callers
/// decide when it shows and how it is announced (mobile pill, desktop
/// toolbar tooltip).
class RefreshProgressCount extends StatelessWidget {
  final RefreshProgress progress;
  final bool desktop;

  const RefreshProgressCount({
    super.key,
    required this.progress,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spinner = desktop ? 14.0 : 13.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: spinner,
          height: spinner,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
        SizedBox(width: desktop ? 7 : 8),
        Text(
          '${progress.completed} / ${progress.total}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
