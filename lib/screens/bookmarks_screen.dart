import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/bookmark_provider.dart';
import '../widgets/feed_list_item.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bookmarkProvider = context.watch<BookmarkProvider>();
    final bookmarkedItems = bookmarkProvider.bookmarkedItems;

    if (bookmarkedItems.isEmpty) {
      return Center(
        child: Text(
          l10n.noBookmarks,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      itemCount: bookmarkedItems.length,
      itemBuilder: (context, index) {
        return FeedListItem(item: bookmarkedItems[index]);
      },
    );
  }
}
