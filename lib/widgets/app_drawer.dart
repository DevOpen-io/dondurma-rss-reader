import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_subscription.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../screens/what_is_rss_page.dart';
import '../screens/explore_feeds_page.dart';
import 'category_icon.dart';
import 'folders/explorer_tree.dart';
import 'folders/folder_actions.dart';
import 'saved_searches.dart';

/// Navigation drawer showing category-based feed filtering.
///
/// Displays all categories (derived from subscriptions), with expandable
/// sections for individual feeds. Also provides a "Suggested Feeds" discovery
/// action.
class AppDrawer extends StatelessWidget {
  final VoidCallback? onFeedSelected;

  /// Runs a saved search's query in the feed list (#71).
  final ValueChanged<String>? onSavedSearch;

  const AppDrawer({super.key, this.onFeedSelected, this.onSavedSearch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Drawer(
      backgroundColor: cs.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(
          end: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/logo.ico',
                      width: 32,
                      height: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.appName,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer2<FeedProvider, SubscriptionProvider>(
                builder: (context, provider, subscriptionProvider, _) {
                  final ordered = subscriptionProvider.categoriesOrdered;
                  final nonUncategorized = ordered
                      .where((c) => c != 'Uncategorized')
                      .toList();
                  final hasUncategorized = ordered.contains('Uncategorized');
                  final byCategory = feedsByCategory(
                    subscriptionProvider.subscriptions,
                  );

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      _buildSectionHeader(context, l10n.categories),
                      _buildDrawerItem(
                        icon: Icons.article_outlined,
                        title: l10n.allArticles,
                        count: provider.unreadCount(),
                        isSelected: provider.selectedCategory == null &&
                            provider.selectedFeedUrl == null,
                        context: context,
                        onTap: () {
                          provider.selectCategory(null);
                          onFeedSelected?.call();
                          context.pop();
                        },
                      ),

                      // Single Theme override for the entire reorderable list.
                      // Previously each ExpansionTile had its own Theme.copyWith
                      // which clones the full ThemeData on every rebuild for every
                      // category — O(N) ThemeData copies per frame.
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (_, _) => Material(
                                elevation: 8,
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.transparent,
                                shadowColor: cs.shadow.withValues(alpha: 0.3),
                                child: child,
                              ),
                            );
                          },
                          onReorderItem: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex--;
                            subscriptionProvider.reorderCategory(
                              oldIndex,
                              newIndex,
                            );
                          },
                          children: [
                            for (int i = 0; i < nonUncategorized.length; i++)
                              ReorderableDelayedDragStartListener(
                                key: ValueKey(nonUncategorized[i]),
                                index: i,
                                child: _buildExpandableCategoryItem(
                                  title: nonUncategorized[i],
                                  feedSources:
                                      byCategory[nonUncategorized[i]] ??
                                      const [],
                                  provider: provider,
                                  subscriptionProvider: subscriptionProvider,
                                  context: context,
                                ),
                              ),
                          ],
                        ),
                      ),

                      if (hasUncategorized) ...[
                        _buildSectionHeader(context, l10n.uncategorized),
                        _buildExpandableCategoryItem(
                          title: l10n.randomBlogs,
                          feedSources: byCategory['Uncategorized'] ?? const [],
                          provider: provider,
                          subscriptionProvider: subscriptionProvider,
                          context: context,
                          isUncategorizedNode: true,
                        ),
                      ],

                      if (onSavedSearch case final open?)
                        SavedSearchList(
                          header: _buildSectionHeader,
                          onOpen: (query) {
                            Scaffold.of(context).closeDrawer();
                            open(query);
                          },
                        ),

                      _buildSectionHeader(context, l10n.discover),
                      _buildDrawerItem(
                        icon: Icons.lightbulb_outline,
                        title: l10n.suggestedFeeds,
                        context: context,
                        onTap: () {
                          context.pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ExploreFeedsPage(),
                            ),
                          );
                        },
                      ),
                      _buildDrawerItem(
                        icon: Icons.help_outline,
                        title: l10n.whatIsRss,
                        context: context,
                        onTap: () {
                          context.pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WhatIsRssPage(),
                            ),
                          );
                        },
                      ),
                      _buildDrawerItem(
                        icon: Icons.mail_outline,
                        title: l10n.contactUs,
                        context: context,
                        onTap: () {
                          context.pop();
                          launchUrl(
                            Uri(scheme: 'mailto', path: 'info@devopen.io'),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
            _buildAboutTile(context, l10n),
          ],
        ),
      ),
    );
  }

  /// Section header label (e.g. "Categories", "Discover").
  Widget _buildSectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Text(
        title,
        style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }

  /// Leading icon of drawer rows.
  Widget _buildRowIcon(
    BuildContext context, {
    required Widget icon,
    required bool isSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IconTheme(
      data: IconThemeData(
        size: 20,
        color: isSelected ? cs.primary : cs.onSurfaceVariant,
      ),
      child: icon,
    );
  }

  /// Article count at the trailing edge of rows.
  Widget _buildCount(BuildContext context, int count, bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      '$count',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: isSelected ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }

  /// Expandable category tile with child feed items.
  Widget _buildExpandableCategoryItem({
    required String title,
    required List<FeedSubscription> feedSources,
    required FeedProvider provider,
    required SubscriptionProvider subscriptionProvider,
    required BuildContext context,
    bool isUncategorizedNode = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final String targetCategory = isUncategorizedNode ? 'Uncategorized' : title;
    final bool isCategorySelected =
        provider.selectedCategory == targetCategory &&
        provider.selectedFeedUrl == null;
    final bool isAncestorCategory =
        provider.selectedFeedParentCategory == targetCategory;
    final emphasis = CategoryEmphasis.of(
      selected: isCategorySelected,
      ancestor: isAncestorCategory,
    );

    final count = provider.unreadCount(category: targetCategory);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Semantics(
        selected: isCategorySelected,
        hint: isAncestorCategory
            ? AppLocalizations.of(context).semanticAncestorCategory
            : null,
        child: Container(
          decoration: isAncestorCategory
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(
                      color: CategoryEmphasis.accent(cs),
                      width: 3,
                    ),
                  ),
                )
              : null,
          // The 48dp options target plus M3's 8dp minimum vertical padding
          // would grow the 56dp header; 4dp keeps it at 56. Leading width
          // and gap match the plain drawer rows so titles line up.
          child: ListTileTheme.merge(
            minVerticalPadding: 4,
            minLeadingWidth: 20,
            horizontalTitleGap: 12,
            child: ExpansionTile(
              initiallyExpanded: provider.selectedCategory == targetCategory,
              tilePadding: const EdgeInsets.only(left: 10, right: 10),
              childrenPadding: const EdgeInsets.only(
                left: 12,
                right: 8,
                bottom: 8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: emphasis.fill(cs, selectedAlpha: 0.22),
              collapsedBackgroundColor: emphasis.fill(cs, selectedAlpha: 0.35),
              iconColor: cs.onSurfaceVariant,
              collapsedIconColor: cs.onSurfaceVariant.withValues(alpha: 0.6),
              leading: _buildRowIcon(
                context,
                icon: CategoryIcon(
                  category: targetCategory,
                  size: 20,
                  color: emphasis.tint(
                    cs,
                    selectedColor: cs.onPrimaryContainer,
                  ),
                ),
                isSelected: isCategorySelected,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        provider.selectCategory(targetCategory);
                        onFeedSelected?.call();
                        context.pop();
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: tt.bodyMedium?.copyWith(
                                color: emphasis.labelColor(cs),
                                fontWeight: emphasis.labelWeight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (count > 0) ...[
                            const SizedBox(width: 8),
                            _buildCount(context, count, isCategorySelected),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!isUncategorizedNode)
                    Semantics(
                      label: AppLocalizations.of(
                        context,
                      ).semanticCategoryOptions,
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showCategoryActions(
                          context,
                          targetCategory,
                          feedSources.length,
                        ),
                        // 48dp hit target (visual icon unchanged at 18px); it
                        // absorbs the 4px gap that used to precede it.
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Icon(
                              Icons.more_vert,
                              size: 18,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              children: [
                for (final sub in feedSources)
                  ExplorerFeedTile(
                    sub: sub,
                    feed: provider,
                    onTap: () {
                      provider.selectFeed(sub.url);
                      onFeedSelected?.call();
                      context.pop();
                    },
                    onShowActions: () => showFeedActions(context, sub),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Simple drawer item with icon, title, optional count badge.
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    int? count,
    bool isSelected = false,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Material(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _buildRowIcon(
                  context,
                  icon: Icon(icon),
                  isSelected: isSelected,
                ),
                const SizedBox(width: 12),
                Expanded(
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
                if (count != null && count > 0) ...[
                  const SizedBox(width: 8),
                  _buildCount(context, count, isSelected),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Footer "About" row opening the standard about dialog.
  Widget _buildAboutTile(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showAboutDialog(context, l10n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _buildRowIcon(
                context,
                icon: const Icon(Icons.info_outline),
                isSelected: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.aboutApp,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) => Text(
                    snap.hasData ? 'v${snap.data!.version}' : '',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAboutDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    final cs = Theme.of(context).colorScheme;
    showAboutDialog(
      context: context,
      applicationName: l10n.appName,
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset('assets/logo.ico', width: 48, height: 48),
      ),
      applicationVersion: info.version,
      children: [
        const SizedBox(height: 16),
        Text(
          'Talha Aksoy & Eren Gün',
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () {
            launchUrl(Uri.parse('mailto:info@devopen.io'));
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.email_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'info@devopen.io',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () {
            launchUrl(
              Uri.parse('https://github.com/DevOpen-io/Dondurma-Rss-Reader'),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.code, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'GitHub',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
