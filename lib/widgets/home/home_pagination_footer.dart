import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/feed_provider.dart';
import 'feed_list_skeleton.dart';

class HomePaginationFooter extends StatelessWidget {
  const HomePaginationFooter({super.key, required this.provider});

  final FeedProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (provider.items.isEmpty) return const SizedBox.shrink();

    if (provider.isLoadingMore) {
      return const FeedListSkeleton(itemCount: 2, showHeader: false);
    }

    if (provider.hasMoreItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: TextButton.icon(
            onPressed: provider.loadMoreItems,
            icon: const Icon(Icons.expand_more),
            label: Text(l10n.loadMore),
          ),
        ),
      );
    }

    if (provider.items.isNotEmpty) {
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

    return const SizedBox.shrink();
  }
}
