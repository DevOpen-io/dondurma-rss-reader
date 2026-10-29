import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/motion.dart';

/// Summary / full-article switch above the article body: one pill track
/// with a thumb in the theme color that slides to the active mode.
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

  /// Track height; also the read-aloud button's size beside it.
  static const height = 48.0;
  static const _inset = 4.0;

  @override
  Widget build(BuildContext context) {
    final duration = motionDuration(context, const Duration(milliseconds: 220));
    return Container(
      height: height,
      decoration: ShapeDecoration(
        color: colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: isFullText
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.all(_inset),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colorScheme.primaryContainer,
                    shape: const StadiumBorder(),
                    shadows: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
              Expanded(
                child: _ModeOption(
                  label: isLoading ? l10n.fullTextLoading : l10n.modeFull,
                  icon: Icons.article_outlined,
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
  final IconData icon;
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
    final color = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          // The tap target is the whole half of the 48dp track.
          height: ArticleReadingModeToggle.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: motionDuration(
                      context,
                      const Duration(milliseconds: 220),
                    ),
                    style: TextStyle(
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: color,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
