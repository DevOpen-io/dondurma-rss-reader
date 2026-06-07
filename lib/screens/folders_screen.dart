import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_subscription.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/keyword_input_dialog.dart';

/// Screen for managing feed categories (folders) and their subscriptions.
///
/// Supports adding/renaming/deleting categories, moving feeds between
/// categories, editing feed details, and per-feed keyword exclusion.
class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  void _showEditCategoryDialog(BuildContext context, String currentCategory) {
    showDialog<void>(
      context: context,
      builder: (context) => _EditCategoryDialog(currentCategory: currentCategory),
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
    showDialog<void>(
      context: context,
      builder: (context) => _EditSubscriptionDialog(sub: sub),
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
                    subscriptionProvider.getCategoryIcon(category),
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  void _showFeedActionSheet(BuildContext context, FeedSubscription sub) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _FeedActionSheet(
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
        child: Text(
          l10n.noFolders,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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

class _FeedActionSheet extends StatelessWidget {
  const _FeedActionSheet({
    required this.subUrl,
    required this.onMove,
    required this.onEdit,
    required this.onDelete,
  });

  final String subUrl;
  final VoidCallback onMove;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _domain(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SubscriptionProvider>();
    final matches = sp.subscriptions.where((s) => s.url == subUrl);
    if (matches.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    final sub = matches.first;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.rss_feed_rounded, size: 20, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.name,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _domain(sub.url),
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      sub.notificationsEnabled
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      size: 20,
                      color: sub.notificationsEnabled ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(l10n.feedNotifications, style: tt.bodyMedium),
                    trailing: Switch(
                      value: sub.notificationsEnabled,
                      onChanged: (_) => context.read<SubscriptionProvider>().toggleFeedNotifications(sub.url),
                    ),
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      sub.fullTextEnabled ? Icons.article : Icons.article_outlined,
                      size: 20,
                      color: sub.fullTextEnabled ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(l10n.fullTextToggle, style: tt.bodyMedium),
                    trailing: Switch(
                      value: sub.fullTextEnabled,
                      onChanged: (_) => context.read<SubscriptionProvider>().toggleFullText(sub.url),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _ActionTile(
                    icon: Icons.drive_file_move_outline,
                    label: l10n.moveToFolder,
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                    onTap: onMove,
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  _ActionTile(
                    icon: Icons.edit_outlined,
                    label: l10n.editFeed,
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                    onTap: onEdit,
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  _ActionTile(
                    icon: Icons.delete_outline,
                    label: l10n.deleteFeed,
                    color: cs.error,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: effectiveColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: effectiveColor),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _EditCategoryDialog extends StatefulWidget {
  const _EditCategoryDialog({required this.currentCategory});
  final String currentCategory;

  @override
  State<_EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<_EditCategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCategory);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.renameFolder),
      content: TextField(
        controller: _controller,
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
            final newName = _controller.text.trim();
            if (newName.isNotEmpty && newName != widget.currentCategory) {
              context
                  .read<SubscriptionProvider>()
                  .renameCategory(widget.currentCategory, newName)
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
  }
}

class _EditSubscriptionDialog extends StatefulWidget {
  const _EditSubscriptionDialog({required this.sub});
  final FeedSubscription sub;

  @override
  State<_EditSubscriptionDialog> createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<_EditSubscriptionDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late List<String> _keywords;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sub.name);
    _urlController = TextEditingController(text: widget.sub.url);
    _keywords = List.from(widget.sub.excludedKeywords);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.editFeed),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.feedName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: l10n.feedUrl,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => KeywordInputDialog(
                  title: l10n.excludedKeywords,
                  initialKeywords: _keywords,
                  onSave: (keywords) => setState(() => _keywords = keywords),
                  onReset: () => setState(() => _keywords = []),
                ),
              );
            },
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text(
              _keywords.isEmpty
                  ? l10n.excludedKeywords
                  : '${l10n.excludedKeywords} (${_keywords.length})',
            ),
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
            final newName = _nameController.text.trim();
            final newUrl = _urlController.text.trim();
            if (newName.isNotEmpty && newUrl.isNotEmpty) {
              context
                  .read<SubscriptionProvider>()
                  .editSubscription(
                    widget.sub.url,
                    newUrl,
                    newName,
                    excludedKeywords: _keywords,
                  )
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
  }
}
