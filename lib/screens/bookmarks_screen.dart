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
      return const Center(
        child: Text(
          'No bookmarked articles yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: bookmarkedItems.length,
      itemBuilder: (context, index) {
        return FeedListItem(item: bookmarkedItems[index]);
      },
    );
  }
}
