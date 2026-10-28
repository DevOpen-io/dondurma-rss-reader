import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/feed_provider.dart';
import 'feed_list_skeleton.dart';

/// "Load more" / "all caught up" row under the article list. Selects its
/// own inputs, so the list around it does not rebuild for paging state.
class HomePaginationFooter extends StatelessWidget {
  const HomePaginationFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (hasItems, isLoadingMore, hasMoreItems) = context
        .select<FeedProvider, (bool, bool, bool)>(
          (p) => (p.items.isNotEmpty, p.isLoadingMore, p.hasMoreItems),
        );
    if (!hasItems) return const SizedBox.shrink();

    if (isLoadingMore) {
      return const FeedListSkeleton(itemCount: 2, showHeader: false);
    }

    if (hasMoreItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: TextButton.icon(
            onPressed: context.read<FeedProvider>().loadMoreItems,
            icon: const Icon(Icons.expand_more),
            label: Text(l10n.loadMore),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Center(
        child: Text(
          l10n.allCaughtUp,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
