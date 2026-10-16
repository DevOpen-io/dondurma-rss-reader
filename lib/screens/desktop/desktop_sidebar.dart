import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_toast.dart';
import '../../widgets/adaptive_dialog.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/folders/category_action_sheet.dart';
import '../../widgets/folders/feed_action_sheet.dart';
import '../../widgets/folders/folder_dialogs.dart';
import '../../widgets/folders/move_feed_sheet.dart';

/// Left navigation column of the desktop layout: app identity, primary
/// destinations (Articles / Bookmarks), the category+feed tree, and
/// Discover/Settings entries. Selection writes through to [FeedProvider]'s
/// existing category/feed filters — no second filter engine.
class DesktopSidebar extends StatelessWidget {
  /// Currently selected library section.
  final DesktopSection section;

  /// Articles vs bookmarks section switch.
  final ValueChanged<DesktopSection> onSectionChanged;

  /// Add-feed and add-category affordances.
  final VoidCallback onAddFeed;
  final VoidCallback onAddCategory;

  /// Opens Discover and Settings as pushed routes — both are self-contained
  /// screens with their own Scaffold/AppBar, so embedding them inside the
  /// pane would nest navigation badly.
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenSettings;

  const DesktopSidebar({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.onAddFeed,
    required this.onAddCategory,
    required this.onOpenDiscover,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          // ── App identity ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/logo.ico',
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.appName,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Library + feed tree ──────────────────────────────────────
          Expanded(
            child: Consumer3<
              FeedProvider,
              SubscriptionProvider,
              BookmarkProvider
            >(
              builder: (context, feed, subs, bookmarks, _) {
                final categories = subs.categoriesOrdered;
                final nonUncategorized = categories
                    .where((c) => c != 'Uncategorized')
                    .toList();
                final hasUncategorized = categories.contains('Uncategorized');

                final inArticles = section == DesktopSection.articles;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  children: [
                    _NavItem(
                      icon: Icons.dynamic_feed_rounded,
                      label: l10n.allNews,
                      count: feed.unreadCount(),
                      selected: inArticles && feed.selectedCategory == null,
                      onTap: () {
                        feed.selectCategory(null);
                        onSectionChanged(DesktopSection.articles);
                      },
                    ),
                    _NavItem(
                      icon: Icons.bookmark_outline_rounded,
                      label: l10n.bookmarksTab,
                      count: bookmarks.bookmarkedItemIds.length,
                      selected: section == DesktopSection.bookmarks,
                      onTap: () => onSectionChanged(DesktopSection.bookmarks),
                    ),

                    _SectionLabel(l10n.categories),
                    for (final category in nonUncategorized)
                      _CategoryNode(
                        key: ValueKey('cat-$category'),
                        title: category,
                        category: category,
                        feedSources: subs.subscriptions
                            .where((s) => s.category == category)
                            .toList(),
                        feed: feed,
                        subs: subs,
                        active: inArticles,
                        onSelect: () =>
                            onSectionChanged(DesktopSection.articles),
                      ),
                    if (hasUncategorized)
                      _CategoryNode(
                        key: const ValueKey('cat-uncategorized'),
                        title: l10n.randomBlogs,
                        category: 'Uncategorized',
                        feedSources: subs.subscriptions
                            .where((s) => s.category == 'Uncategorized')
                            .toList(),
                        feed: feed,
                        subs: subs,
                        active: inArticles,
                        isUncategorized: true,
                        onSelect: () =>
                            onSectionChanged(DesktopSection.articles),
                      ),
                    _ActionRow(
                      icon: Icons.add,
                      label: l10n.semanticAddFeed,
                      onTap: onAddFeed,
                    ),
                    _ActionRow(
                      icon: Icons.create_new_folder_outlined,
                      label: l10n.addFolder,
                      onTap: onAddCategory,
                    ),

                    _SectionLabel(l10n.discover),
                    _NavItem(
                      icon: Icons.lightbulb_outline_rounded,
                      label: l10n.suggestedFeeds,
                      selected: false,
                      onTap: onOpenDiscover,
                    ),
                    _NavItem(
                      icon: Icons.settings_outlined,
                      label: l10n.settingsTab,
                      selected: false,
                      onTap: onOpenSettings,
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

enum DesktopSection { articles, bookmarks }

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: cs.onSurface.withValues(alpha: 0.05),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: selected
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count != null && count! > 0)
                  Text(
                    '$count',
                    style: tt.labelSmall?.copyWith(
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: cs.onSurface.withValues(alpha: 0.05),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expandable category node listing its feeds — mirrors the mobile drawer's
/// semantics (select category vs select feed) without the drawer chrome.
class _CategoryNode extends StatelessWidget {
  final String title;
  final String category;
  final List<FeedSubscription> feedSources;
  final FeedProvider feed;
  final SubscriptionProvider subs;
  final bool active;
  final bool isUncategorized;
  final VoidCallback onSelect;

  const _CategoryNode({
    super.key,
    required this.title,
    required this.category,
    required this.feedSources,
    required this.feed,
    required this.subs,
    required this.active,
    required this.onSelect,
    this.isUncategorized = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected =
        active && feed.selectedCategory == category && feed.selectedFeedUrl == null;
    final count = feed.unreadCount(category: category);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: feed.selectedCategory == category,
          tilePadding: const EdgeInsets.only(left: 12, right: 8),
          childrenPadding: const EdgeInsets.only(left: 8, bottom: 4),
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.3)
              : Colors.transparent,
          collapsedBackgroundColor: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          iconColor: cs.onSurfaceVariant,
          collapsedIconColor: cs.onSurfaceVariant.withValues(alpha: 0.6),
          leading: CategoryIcon(
            category: category,
            size: 17,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    feed.selectCategory(category);
                    onSelect();
                  },
                  child: Text(
                    title,
                    style: tt.bodyMedium?.copyWith(
                      color: isSelected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.8),
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: tt.labelSmall?.copyWith(
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (!isUncategorized)
                Semantics(
                  label: l10n.semanticCategoryOptions,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showCategoryActions(context),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.more_horiz,
                        size: 16,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          children: [
            for (final sub in feedSources)
              _FeedRow(sub: sub, feed: feed, onSelect: onSelect),
          ],
        ),
      ),
    );
  }

  void _showCategoryActions(BuildContext context) {
    showAdaptiveSheet<void>(
      context,
      CategoryActionSheet(
        category: category,
        onMarkAllRead: () {
          Navigator.pop(context);
          feed.markAllInCategoryAsRead(category);
        },
        onChangeIcon: () {
          Navigator.pop(context);
          showDialog<void>(
            context: context,
            builder: (_) => EmojiIconDialog(category: category),
          );
        },
        onRename: () {
          Navigator.pop(context);
          showDialog<void>(
            context: context,
            builder: (_) => EditCategoryDialog(currentCategory: category),
          );
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDeleteCategory(context);
        },
      ),
    );
  }

  void _confirmDeleteCategory(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteFolder),
        content: Text(
          l10n.deleteFolderConfirm(category, feedSources.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              context
                  .read<SubscriptionProvider>()
                  .removeCategory(category)
                  .then((_) {
                    if (context.mounted) {
                      context.read<FeedProvider>().refreshAll();
                    }
                  });
              Navigator.of(dialogContext).pop();
            },
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  final FeedSubscription sub;
  final FeedProvider feed;
  final VoidCallback onSelect;

  const _FeedRow({
    required this.sub,
    required this.feed,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = feed.selectedFeedUrl == sub.url;
    final count = feed.unreadCount(feedUrl: sub.url);
    final hasError = feed.feedErrorFor(sub.url) != null;

    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 1, bottom: 1),
      child: Material(
        color: isSelected
            ? cs.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: cs.onSurface.withValues(alpha: 0.05),
          onTap: () {
            feed.selectFeed(sub.url);
            onSelect();
          },
          onSecondaryTapDown: (_) => _showFeedActions(context),
          onLongPress: () => _showFeedActions(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sub.name,
                    style: tt.bodySmall?.copyWith(
                      fontSize: 13,
                      color: isSelected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.7),
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasError) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: cs.error,
                  ),
                ],
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: tt.labelSmall?.copyWith(
                      color: isSelected
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFeedActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showAdaptiveSheet<void>(
      context,
      FeedActionSheet(
        subUrl: sub.url,
        onMove: () {
          Navigator.pop(context);
          MoveToCategorySheet.show(
            context,
            sub,
            onMoved: (movedSub, category) {
              if (context.mounted) {
                context.read<FeedProvider>().refreshAll();
                showAppToast(
                  l10n.feedMovedToFolder(movedSub.name, category),
                  type: AppToastType.success,
                );
              }
            },
          );
        },
        onEdit: () {
          Navigator.pop(context);
          showAdaptiveSheet<void>(
            context,
            EditSubscriptionDialog(sub: sub),
          );
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDeleteFeed(context);
        },
      ),
    );
  }

  void _confirmDeleteFeed(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteFeed),
        content: Text(l10n.deleteFeedConfirm(sub.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
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
              Navigator.of(dialogContext).pop();
            },
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        ],
      ),
    );
  }
}
