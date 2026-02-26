import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  void _showEditCategoryDialog(
    BuildContext context,
    String currentCategory,
    FeedProvider provider,
  ) {
    final TextEditingController nameController = TextEditingController(
      text: currentCategory,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Folder'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Folder Name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty && newName != currentCategory) {
                  provider.renameCategory(currentCategory, newName);
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showEditSubscriptionDialog(
    BuildContext context,
    FeedSubscription sub,
    FeedProvider provider,
  ) {
    final TextEditingController feedNameController = TextEditingController(
      text: sub.name,
    );
    final TextEditingController feedUrlController = TextEditingController(
      text: sub.url,
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Feed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: feedNameController,
                decoration: const InputDecoration(
                  labelText: 'Feed Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: feedUrlController,
                decoration: const InputDecoration(
                  labelText: 'Feed URL',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = feedNameController.text.trim();
                final newUrl = feedUrlController.text.trim();
                if (newName.isNotEmpty && newUrl.isNotEmpty) {
                  provider.editSubscription(sub.url, newUrl, newName);
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    FeedSubscription sub,
    FeedProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Feed'),
          content: Text(
            'Are you sure you want to completely remove "${sub.name}" from your subscriptions?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                provider.removeFeed(sub.url);
                Navigator.pop(context);
              },
              child: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteCategoryConfirmation(
    BuildContext context,
    String categoryName,
    int feedCount,
    FeedProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Folder'),
          content: Text(
            'Are you sure you want to delete the folder "$categoryName"?\n\nThis will permanently remove all $feedCount RSS feeds inside it from your subscriptions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                provider.removeCategory(categoryName);
                Navigator.pop(context);
              },
              child: Text(
                'Delete All',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedProvider>();
    final subscriptions = provider.subscriptions;

    // Group subscriptions by category
    final Map<String, List<FeedSubscription>> categories = {};
    for (var sub in subscriptions) {
      if (!categories.containsKey(sub.category)) {
        categories[sub.category] = [];
      }
      categories[sub.category]!.add(sub);
    }

    final sortedCategoryNames = categories.keys.toList()..sort();

    if (sortedCategoryNames.isEmpty) {
      return Center(
        child: Text(
          'No folders yet. Categories will appear here.',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: sortedCategoryNames.length,
      itemBuilder: (context, index) {
        final categoryName = sortedCategoryNames[index];
        final subs = categories[categoryName]!;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(
              Icons.folder_open,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.8),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    categoryName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.8),
                  ),
                  onPressed: () => _showDeleteCategoryConfirmation(
                    context,
                    categoryName,
                    subs.length,
                    provider,
                  ),
                  tooltip: 'Delete Folder',
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    size: 20,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onPressed: () =>
                      _showEditCategoryDialog(context, categoryName, provider),
                  tooltip: 'Rename Folder',
                ),
              ],
            ),
            children: subs.map((sub) {
              return Column(
                children: [
                  Divider(
                    height: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.only(
                      left: 48.0,
                      right: 16.0,
                    ),
                    title: Text(
                      sub.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      sub.url,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          onPressed: () => _showEditSubscriptionDialog(
                            context,
                            sub,
                            provider,
                          ),
                          tooltip: 'Edit Feed',
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () =>
                              _showDeleteConfirmation(context, sub, provider),
                          tooltip: 'Delete Feed',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
