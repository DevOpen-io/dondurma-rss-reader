import 'package:flutter/material.dart';

import '../../models/feed_subscription.dart';
import '../../providers/feed_provider.dart';

// Pieces shared by the mobile drawer and the desktop sidebar feed trees.
// Their category nodes stay separate widgets: chip vs bare icon, pill vs
// plain count, accent border vs accent bar and desktop's auto-expand differ
// too much to merge without changing either look.

/// Subscriptions grouped by category — built once per tree build instead of
/// filtering the whole list again for every category node.
Map<String, List<FeedSubscription>> feedsByCategory(
  Iterable<FeedSubscription> subscriptions,
) {
  final byCategory = <String, List<FeedSubscription>>{};
  for (final sub in subscriptions) {
    byCategory.putIfAbsent(sub.category, () => []).add(sub);
  }
  return byCategory;
}

/// Category node emphasis. `selected`: the category itself is the active
/// scope (full primary treatment). `ancestor`: a feed inside it is selected
/// (accent + brighter label, no selection fill).
enum CategoryEmphasis {
  selected,
  ancestor,
  none;

  /// The category's own selection wins over containing the selected feed.
  static CategoryEmphasis of({
    required bool selected,
    required bool ancestor,
  }) => selected
      ? CategoryEmphasis.selected
      : ancestor
      ? CategoryEmphasis.ancestor
      : CategoryEmphasis.none;

  /// Node fill; the selected strength differs per surface and per
  /// expanded/collapsed state.
  Color fill(ColorScheme cs, {required double selectedAlpha}) => switch (this) {
    selected => cs.primaryContainer.withValues(alpha: selectedAlpha),
    ancestor => cs.primary.withValues(alpha: 0.05),
    none => Colors.transparent,
  };

  /// Icon/count tint; only the selected color differs per surface.
  Color tint(ColorScheme cs, {required Color selectedColor}) => switch (this) {
    selected => selectedColor,
    ancestor => cs.primary.withValues(alpha: 0.8),
    none => cs.onSurfaceVariant,
  };

  Color labelColor(ColorScheme cs) => switch (this) {
    selected => cs.primary,
    ancestor => cs.onSurface,
    none => cs.onSurface.withValues(alpha: 0.8),
  };

  FontWeight get labelWeight => switch (this) {
    selected => FontWeight.w700,
    ancestor => FontWeight.w600,
    none => FontWeight.w500,
  };

  /// The slim "contains the selected feed" accent at the node's left edge.
  static Color accent(ColorScheme cs) => cs.primary.withValues(alpha: 0.75);
}

/// Feed row inside a category node: selection dot, name, last-fetch error
/// icon and unread count.
class ExplorerFeedTile extends StatelessWidget {
  const ExplorerFeedTile({
    super.key,
    required this.sub,
    required this.feed,
    required this.onTap,
    required this.onShowActions,
    this.dense = false,
  });

  final FeedSubscription sub;
  final FeedProvider feed;
  final VoidCallback onTap;

  /// Long-press, plus right-click when [dense].
  final VoidCallback onShowActions;

  /// Desktop sidebar metrics: tighter padding and radius, hover tint and a
  /// right-click menu.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = feed.selectedFeedUrl == sub.url;
    final count = feed.unreadCount(feedUrl: sub.url);
    final hasError = feed.feedErrorFor(sub.url) != null;
    final radius = BorderRadius.circular(dense ? 8 : 10);

    return Padding(
      padding: dense
          ? const EdgeInsets.only(left: 22, top: 1, bottom: 1)
          : const EdgeInsets.only(left: 22, top: 2),
      child: Semantics(
        selected: isSelected,
        child: Material(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            hoverColor: dense ? cs.onSurface.withValues(alpha: 0.05) : null,
            onTap: onTap,
            onSecondaryTapDown: dense ? (_) => onShowActions() : null,
            onLongPress: onShowActions,
            child: Padding(
              padding: dense
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sub.name,
                      style: tt.bodySmall?.copyWith(
                        fontSize: 13,
                        color: isSelected
                            ? cs.primary
                            : cs.onSurface.withValues(
                                alpha: dense ? 0.7 : 0.65,
                              ),
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasError) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.error_outline_rounded,
                      size: 14,
                      color: cs.error,
                    ),
                  ],
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: tt.labelSmall?.copyWith(
                        color: isSelected
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
