import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 5),
              Text(
                l10n.readingModeLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ModeOption(
                  label: l10n.modeShort,
                  icon: Icons.short_text_rounded,
                  isSelected: !isFullText,
                  isLoading: false,
                  onTap: isFullText && !isLoading ? onToggle : null,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeOption(
                  label: isLoading ? l10n.fullTextLoading : l10n.modeFull,
                  icon: isLoading ? null : Icons.auto_stories_rounded,
                  isSelected: isFullText,
                  isLoading: isLoading,
                  onTap: !isFullText && !isLoading ? onToggle : null,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;

  const _ModeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else if (icon != null)
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                if (!isLoading) const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
