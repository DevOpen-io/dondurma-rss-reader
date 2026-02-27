import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../models/feed_subscription.dart';

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  void _showAddCategoryDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final TextEditingController nameController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(l10n.addFolder),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n.newFolderName,
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                autofocus: true,
                onChanged: (_) {
                  if (errorText != null) {
                    setDialogState(() {
                      errorText = null;
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = l10n.pleaseEnterFolderName;
                      });
                      return;
                    }
                    final provider = context.read<SubscriptionProvider>();
                    provider.addCategory(name).then((success) {
                      if (!success && context.mounted) {
                        setDialogState(() {
                          errorText = l10n.folderAlreadyExists;
                        });
                      } else if (context.mounted) {
                        context.pop();
                      }
                    });
                  },
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditCategoryDialog(BuildContext context, String currentCategory) {
    final l10n = AppLocalizations.of(context);
    final TextEditingController nameController = TextEditingController(
      text: currentCategory,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.renameFolder),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: l10n.folderName,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty && newName != currentCategory) {
                  context
                      .read<SubscriptionProvider>()
                      .renameCategory(currentCategory, newName)
                      .then((_) {
                        if (context.mounted) {
                          context.read<FeedProvider>().refreshAll();
                        }
                      });
                }
                context.pop();
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
  }

  void _showEditSubscriptionDialog(BuildContext context, FeedSubscription sub) {
    final l10n = AppLocalizations.of(context);
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
          title: Text(l10n.editFeed),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: feedNameController,
                decoration: InputDecoration(
                  labelText: l10n.feedName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: feedUrlController,
                decoration: InputDecoration(
                  labelText: l10n.feedUrl,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = feedNameController.text.trim();
                final newUrl = feedUrlController.text.trim();
                if (newName.isNotEmpty && newUrl.isNotEmpty) {
                  context
                      .read<SubscriptionProvider>()
                      .editSubscription(sub.url, newUrl, newName)
                      .then((_) {
                        if (context.mounted) {
                          context.read<FeedProvider>().refreshAll();
                        }
                      });
                }
                context.pop();
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, FeedSubscription sub) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.deleteFeed),
          content: Text(l10n.deleteFeedConfirm(sub.name)),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                context.read<SubscriptionProvider>().removeFeed(sub.url).then((
                  _,
                ) {
                  if (context.mounted) {
                    context.read<FeedProvider>().refreshAll();
                  }
                });
                context.pop();
              },
              child: Text(
                l10n.delete,
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
  ) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.deleteFolder),
          content: Text(l10n.deleteFolderConfirm(categoryName, feedCount)),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                context
                    .read<SubscriptionProvider>()
                    .removeCategory(categoryName)
                    .then((_) {
                      if (context.mounted) {
                        context.read<FeedProvider>().refreshAll();
                      }
                    });
                context.pop();
              },
              child: Text(
                l10n.deleteAll,
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMoveFeedDialog(BuildContext context, FeedSubscription sub) {
    final l10n = AppLocalizations.of(context);
    final subscriptionProvider = context.read<SubscriptionProvider>();
    final allCategories =
        subscriptionProvider.categories.where((c) => c != sub.category).toList()
          ..sort();

    if (allCategories.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.moveToFolder),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allCategories.length,
              itemBuilder: (context, index) {
                final category = allCategories[index];
                return ListTile(
                  leading: Icon(
                    Icons.folder_open,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.8),
                  ),
                  title: Text(category),
                  onTap: () {
                    subscriptionProvider
                        .moveFeedToCategory(sub.url, category)
                        .then((_) {
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            context.read<FeedProvider>().refreshAll();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  l10n.feedMovedToFolder(sub.name, category),
                                ),
                              ),
                            );
                          }
                        });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subscriptionProvider = context.watch<SubscriptionProvider>();
    final subscriptions = subscriptionProvider.subscriptions;

    // Group subscriptions by category
    final Map<String, List<FeedSubscription>> categoryFeeds = {};
    for (var sub in subscriptions) {
      if (!categoryFeeds.containsKey(sub.category)) {
        categoryFeeds[sub.category] = [];
      }
      categoryFeeds[sub.category]!.add(sub);
    }

    // Include empty custom categories
    for (var cat in subscriptionProvider.categories) {
      if (!categoryFeeds.containsKey(cat)) {
        categoryFeeds[cat] = [];
      }
    }

    final sortedCategoryNames = categoryFeeds.keys.toList()..sort();

    if (sortedCategoryNames.isEmpty) {
      return Stack(
        children: [
          Center(
            child: Text(
              l10n.noFolders,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: () => _showAddCategoryDialog(context),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.create_new_folder, size: 28),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          itemCount: sortedCategoryNames.length,
          itemBuilder: (context, index) {
            final categoryName = sortedCategoryNames[index];
            final subs = categoryFeeds[categoryName]!;

            return Card(
              margin: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
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
                      ),
                      tooltip: l10n.deleteFolder,
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
                          _showEditCategoryDialog(context, categoryName),
                      tooltip: l10n.renameFolder,
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
                                Icons.drive_file_move_outline,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.7),
                              ),
                              onPressed: () =>
                                  _showMoveFeedDialog(context, sub),
                              tooltip: l10n.moveToFolder,
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                              onPressed: () =>
                                  _showEditSubscriptionDialog(context, sub),
                              tooltip: l10n.editFeed,
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              onPressed: () =>
                                  _showDeleteConfirmation(context, sub),
                              tooltip: l10n.deleteFeed,
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
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () => _showAddCategoryDialog(context),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.create_new_folder, size: 28),
          ),
        ),
      ],
    );
  }
}
