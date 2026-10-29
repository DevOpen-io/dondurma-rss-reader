import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Summary / full-article switch above the article body.
class ArticleReadingModeToggle extends StatelessWidget {
  final bool isFullText;
  final bool isLoading;
  final VoidCallback onToggle;
  final ColorScheme colorScheme;
  final AppLocalizations l10n;

  const ArticleReadingModeToggle({
    super.key,
    required this.isFullText,
    required this.isLoading,
    required this.onToggle,
    required this.colorScheme,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        // 48dp touch target.
        minimumSize: const Size(0, 48),
        selectedBackgroundColor: colorScheme.primary.withValues(alpha: 0.12),
        selectedForegroundColor: colorScheme.primary,
      ),
      segments: [
        ButtonSegment(value: false, label: Text(l10n.modeShort)),
        ButtonSegment(
          value: true,
          icon: isLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : null,
          label: Text(
            isLoading ? l10n.fullTextLoading : l10n.modeFull,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      selected: {isFullText},
      onSelectionChanged: isLoading ? null : (_) => onToggle(),
    );
  }
}
