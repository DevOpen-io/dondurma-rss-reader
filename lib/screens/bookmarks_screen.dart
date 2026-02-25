import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../widgets/feed_list_item.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedProvider>();
    final bookmarkedItems = provider.bookmarkedItems;

    if (bookmarkedItems.isEmpty) {
      return Center(
        child: Text(
          'No bookmarked articles yet.',
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
