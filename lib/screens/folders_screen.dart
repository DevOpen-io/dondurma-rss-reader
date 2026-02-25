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
            'Are you sure you want to completely remove "\${sub.name}" from your subscriptions?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () {
                provider.removeFeed(sub.url);
                Navigator.pop(context);
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
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
      return const Center(
        child: Text(
          'No folders yet. Categories will appear here.',
          style: TextStyle(color: Colors.grey),
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
                if (categoryName != 'Uncategorized')
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                    onPressed: () => _showEditCategoryDialog(
                      context,
                      categoryName,
                      provider,
                    ),
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
                        color: Colors.grey.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onPressed: () => _showEditSubscriptionDialog(
                            context,
                            sub,
                            provider,
                          ),
                          tooltip: 'Edit Feed',
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.redAccent,
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
