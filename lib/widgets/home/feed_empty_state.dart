import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/feed_provider.dart';
import '../empty_state.dart';

/// Empty article list shared by the mobile feed tab and the desktop list
/// pane: a first-run prompt when nothing is cached yet, otherwise why the
/// current filters match nothing.
class FeedEmptyState extends StatelessWidget {
  final FeedProvider provider;
  final VoidCallback onAddFeed;

  /// The caller's search field, cleared together with the provider filters.
  final TextEditingController searchController;

  /// Mobile marks articles read by swiping; desktop has no swipe.
  final bool showSwipeHint;

  const FeedEmptyState({
    super.key,
    required this.provider,
    required this.onAddFeed,
    required this.searchController,
    this.showSwipeHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (provider.items.isEmpty) {
      return EmptyState(
        icon: Icons.rss_feed,
        title: l10n.noFeedsFound,
        action: FilledButton.icon(
          onPressed: onAddFeed,
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.semanticAddFeed),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            provider.selectedCategory != null
                ? l10n.noFeedsInCategory(provider.selectedCategory!)
                : l10n.noFeedsMatchFilter,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
          if (provider.hasActiveSheetFilter ||
              provider.searchQuery.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                searchController.clear();
                provider.setSearchQuery('');
                if (provider.hasActiveSheetFilter) {
                  provider.clearSheetFilter();
                }
              },
              child: Text(l10n.clearFilters),
            ),
          ],
          if (showSwipeHint && provider.showUnreadOnly) ...[
            const SizedBox(height: 8),
            Text(
              l10n.readSwipeHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
