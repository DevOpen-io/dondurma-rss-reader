import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/bookmark_tags.dart';
import '../widgets/feed_list_item.dart';
import '../widgets/constrained_width.dart';
import '../widgets/empty_state.dart';

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
        child: EmptyState(
          icon: Icons.bookmark_border_rounded,
          title: l10n.noBookmarks,
          hint: l10n.bookmarksSwipeHint,
        ),
      );
    }

    final flat = context.select<SettingsProvider, bool>(
      (s) => s.articleListStyle == 'list',
    );
    final visible = bookmarkProvider.visibleBookmarks;
    return ConstrainedWidth(
      child: Column(
        children: [
          const BookmarkTagFilter(),
          Expanded(
            child: ListView.builder(
              // List rows run edge to edge; cards keep margins.
              padding: EdgeInsets.only(
                top: flat ? 8 : 16.0,
                left: flat ? 0 : 16.0,
                right: flat ? 0 : 16.0,
                bottom: 16.0,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final item = visible[index];
                // Bookmarks show the live read state — the stored JSON
                // freezes isRead at save time, which would disagree with the
                // feed list on the same record. A per-row Selector avoids
                // rebuilding the whole list on every FeedProvider notify.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Selector<FeedProvider, bool>(
                      selector: (_, feed) => feed.isRead(item),
                      builder: (_, isRead, _) => FeedListItem(
                        item: item.copyWith(isRead: isRead),
                        navigationItems: visible,
                        flat: flat,
                        onLongPress: () =>
                            BookmarkTagsSheet.show(context, item),
                        longPressHint: l10n.editTags,
                      ),
                    ),
                    BookmarkTagLine(
                      item: item,
                      padding: EdgeInsets.fromLTRB(flat ? 16 : 4, 0, 16, 8),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
