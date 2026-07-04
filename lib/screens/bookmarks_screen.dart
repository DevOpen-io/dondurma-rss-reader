import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/bookmark_provider.dart';
import '../widgets/feed_list_item.dart';

/// Displays the user's saved/bookmarked articles in a scrollable list.
///
/// Shows an empty-state message when no articles are bookmarked.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bookmarkProvider = context.watch<BookmarkProvider>();
    final bookmarkedItems = bookmarkProvider.bookmarkedItems;

    if (bookmarkedItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_border_rounded,
                size: 64,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.noBookmarks,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.bookmarksSwipeHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: 16.0,
        left: 16.0,
        right: 16.0,
        bottom: 120.0,
      ),
      itemCount: bookmarkedItems.length,
      itemBuilder: (context, index) {
        return FeedListItem(item: bookmarkedItems[index]);
      },
    );
  }
}
