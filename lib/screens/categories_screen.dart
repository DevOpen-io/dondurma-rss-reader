import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_subscription.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../utils/platform_caps.dart';
import '../widgets/category_icon.dart';
import '../widgets/folders/folder_actions.dart';
import '../widgets/constrained_width.dart';

/// Screen for managing feed categories (folders) and their subscriptions.
///
/// Supports adding/renaming/deleting categories, moving feeds between
/// categories, editing feed details, and per-feed keyword exclusion.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, this.onFeedSelected});

  /// Called when a feed's navigate affordance is tapped — HomeScreen switches
  /// to the Feeds tab so the feed-filtered list becomes visible.
  final VoidCallback? onFeedSelected;

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
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.noFolders,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.addCategoryEmptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ConstrainedWidth(
      maxWidth: PlatformCaps.isDesktop ? 860 : 680,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        itemCount: sortedCategoryNames.length,
        itemBuilder: (context, index) {
          final categoryName = sortedCategoryNames[index];
          final subs = categoryFeeds[categoryName]!;
          return _CategorySection(
            categoryName: categoryName,
            subs: subs,
            onIconTap: () => showCategoryIconDialog(context, categoryName),
            onRename: () => showRenameCategoryDialog(context, categoryName),
            onDelete: () =>
                confirmDeleteCategory(context, categoryName, subs.length),
            onFeedTap: (sub) => showFeedActions(context, sub),
            onFeedNavigate: (sub) {
              context.read<FeedProvider>().selectFeed(sub.url);
              onFeedSelected?.call();
            },
          );
        },
      ),
    );
  }
}

enum _CategoryAction { rename, delete }

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.categoryName,
    required this.subs,
    required this.onIconTap,
    required this.onRename,
    required this.onDelete,
    required this.onFeedTap,
    required this.onFeedNavigate,
  });

  final String categoryName;
  final List<FeedSubscription> subs;
  final VoidCallback onIconTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(FeedSubscription) onFeedTap;
  final void Function(FeedSubscription) onFeedNavigate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final icon = CategoryIcon(
      category: categoryName,
      size: 20,
      color: cs.onSurfaceVariant,
    );

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
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: icon,
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
                Text(
                  '${subs.length}',
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 2),
                PopupMenuButton<_CategoryAction>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  onSelected: (action) {
                    if (action == _CategoryAction.rename) onRename();
                    if (action == _CategoryAction.delete) onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _CategoryAction.rename,
                      child: Row(
                        children: [
                          Icon(Icons.drive_file_rename_outline, size: 18),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context).renameFolder),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _CategoryAction.delete,
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: cs.error),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context).deleteFolder,
                            style: TextStyle(color: cs.error),
                          ),
                        ],
                      ),
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
                Divider(
                  height: 1,
                  indent: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
              _FeedRow(
                sub: subs[i],
                onTap: () => onFeedTap(subs[i]),
                onNavigate: () => onFeedNavigate(subs[i]),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.sub,
    required this.onTap,
    required this.onNavigate,
  });

  final FeedSubscription sub;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

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
                // Only the exceptions to the defaults are marked: a muted
                // feed and a feed forced to full text.
                if (!sub.notificationsEnabled)
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                if (sub.fullTextEnabled == true) ...[
                  if (!sub.notificationsEnabled) const SizedBox(width: 4),
                  Icon(
                    Icons.article_outlined,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ],
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onNavigate,
                  child: Padding(
                    // 16px icon + 16px padding = 48dp minimum touch target.
                    padding: const EdgeInsets.all(16.0),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
