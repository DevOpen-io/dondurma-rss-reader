import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_subscription.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/folders/feed_action_sheet.dart';
import '../widgets/folders/folder_dialogs.dart';

/// Screen for managing feed categories (folders) and their subscriptions.
///
/// Supports adding/renaming/deleting categories, moving feeds between
/// categories, editing feed details, and per-feed keyword exclusion.
class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  void _showEditCategoryDialog(BuildContext context, String currentCategory) {
    showDialog<void>(
      context: context,
      builder: (context) => EditCategoryDialog(currentCategory: currentCategory),
    );
  }

  void _showIconPicker(BuildContext context, String categoryName) {
    final icons = SubscriptionProvider.categoryIconOptions;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select Icon for $categoryName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: icons.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final iconData = icons[index];
                    return InkWell(
                      onTap: () {
                        context.read<SubscriptionProvider>().setCategoryIcon(
                          categoryName,
                          iconData,
                        );
                        Navigator.pop(bottomSheetContext);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Center(
                        child: Icon(
                          iconData,
                          size: 28,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showEditSubscriptionDialog(BuildContext context, FeedSubscription sub) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => EditSubscriptionDialog(sub: sub),
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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.moveToFolder,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: allCategories.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 16,
                      color: cs.outline.withValues(alpha: 0.2),
                    ),
                    itemBuilder: (_, index) {
                      final category = allCategories[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: Icon(
                          subscriptionProvider.getCategoryIcon(category),
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        title: Text(category, style: tt.bodyMedium),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        onTap: () {
                          subscriptionProvider
                              .moveFeedToCategory(sub.url, category)
                              .then((_) {
                                if (sheetCtx.mounted) {
                                  Navigator.of(sheetCtx).pop();
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
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFeedActionSheet(BuildContext context, FeedSubscription sub) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FeedActionSheet(
        subUrl: sub.url,
        onMove: () {
          Navigator.of(ctx).pop();
          _showMoveFeedDialog(context, sub);
        },
        onEdit: () {
          Navigator.of(ctx).pop();
          _showEditSubscriptionDialog(context, sub);
        },
        onDelete: () {
          Navigator.of(ctx).pop();
          _showDeleteConfirmation(context, sub);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subscriptionProvider = context.watch<SubscriptionProvider>();
    final subscriptions = subscriptionProvider.subscriptions;

    final Map<String, List<FeedSubscription>> categoryFeeds = {};
    for (var sub in subscriptions) {
      categoryFeeds.putIfAbsent(sub.category, () => []).add(sub);
    }
    for (var cat in subscriptionProvider.categories) {
      categoryFeeds.putIfAbsent(cat, () => []);
    }
    final sortedCategoryNames = categoryFeeds.keys.toList()..sort();

    if (sortedCategoryNames.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.15),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.noFolders,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add a folder to organize your feeds.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedCategoryNames.length,
      itemBuilder: (context, index) {
        final categoryName = sortedCategoryNames[index];
        final subs = categoryFeeds[categoryName]!;
        return _CategorySection(
          categoryName: categoryName,
          subs: subs,
          subscriptionProvider: subscriptionProvider,
          onIconTap: () => _showIconPicker(context, categoryName),
          onRename: () => _showEditCategoryDialog(context, categoryName),
          onDelete: () => _showDeleteCategoryConfirmation(context, categoryName, subs.length),
          onFeedTap: (sub) => _showFeedActionSheet(context, sub),
        );
      },
    );
  }
}

enum _CategoryAction { rename, delete }

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.categoryName,
    required this.subs,
    required this.subscriptionProvider,
    required this.onIconTap,
    required this.onRename,
    required this.onDelete,
    required this.onFeedTap,
  });

  final String categoryName;
  final List<FeedSubscription> subs;
  final SubscriptionProvider subscriptionProvider;
  final VoidCallback onIconTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(FeedSubscription) onFeedTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final icon = subscriptionProvider.getCategoryIcon(categoryName);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                InkWell(
                  onTap: onIconTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: cs.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    categoryName,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${subs.length}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 2),
                PopupMenuButton<_CategoryAction>(
                  icon: Icon(Icons.more_vert, size: 20, color: cs.onSurfaceVariant),
                  onSelected: (action) {
                    if (action == _CategoryAction.rename) onRename();
                    if (action == _CategoryAction.delete) onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _CategoryAction.rename,
                      child: Row(children: [
                        Icon(Icons.drive_file_rename_outline, size: 18),
                        const SizedBox(width: 8),
                        Text(AppLocalizations.of(context).renameFolder),
                      ]),
                    ),
                    PopupMenuItem(
                      value: _CategoryAction.delete,
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 18, color: cs.error),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context).deleteFolder,
                          style: TextStyle(color: cs.error),
                        ),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (subs.isNotEmpty) ...[
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            for (int i = 0; i < subs.length; i++) ...[
              if (i > 0)
                Divider(height: 1, indent: 16, color: cs.outlineVariant.withValues(alpha: 0.3)),
              _FeedRow(sub: subs[i], onTap: () => onFeedTap(subs[i])),
            ],
          ],
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.sub, required this.onTap});

  final FeedSubscription sub;
  final VoidCallback onTap;

  String _domain(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sub.name,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _domain(sub.url),
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sub.notificationsEnabled)
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 14,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                if (sub.fullTextEnabled) ...[
                  if (sub.notificationsEnabled) const SizedBox(width: 4),
                  Icon(
                    Icons.article_outlined,
                    size: 14,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

