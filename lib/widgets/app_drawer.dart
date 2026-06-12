import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_subscription.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../screens/what_is_rss_page.dart';
import 'explore_feeds_dialog.dart';

/// Navigation drawer showing category-based feed filtering.
///
/// Displays all categories (derived from subscriptions), with expandable
/// sections for individual feeds. Also provides a "Suggested Feeds" discovery
/// action.
class AppDrawer extends StatelessWidget {
  final VoidCallback? onFeedSelected;

  const AppDrawer({super.key, this.onFeedSelected});

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
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/logo.ico',
                        width: 30,
                        height: 30,
                      ),
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
                  final nonUncategorized = ordered.where((c) => c != 'Uncategorized').toList();
                  final hasUncategorized = ordered.contains('Uncategorized');

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      _buildSectionHeader(context, l10n.categories),
                      _buildDrawerItem(
                        icon: Icons.article_outlined,
                        title: l10n.allNews,
                        count: provider.items.length,
                        isSelected: provider.selectedCategory == null,
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
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (_, __) => Material(
                                elevation: 8,
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.transparent,
                                shadowColor: cs.shadow.withValues(alpha: 0.3),
                                child: child,
                              ),
                            );
                          },
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex--;
                            subscriptionProvider.reorderCategory(oldIndex, newIndex);
                          },
                          children: [
                            for (int i = 0; i < nonUncategorized.length; i++)
                              ReorderableDelayedDragStartListener(
                                key: ValueKey(nonUncategorized[i]),
                                index: i,
                                child: _buildExpandableCategoryItem(
                                  categoryIcon: subscriptionProvider.getCategoryIcon(nonUncategorized[i]),
                                  title: nonUncategorized[i],
                                  feedSources: subscriptionProvider.subscriptions
                                      .where((sub) => sub.category == nonUncategorized[i])
                                      .toList(),
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
                          categoryIcon: subscriptionProvider.getCategoryIcon('Uncategorized'),
                          title: l10n.randomBlogs,
                          feedSources: subscriptionProvider.subscriptions
                              .where((sub) => sub.category == 'Uncategorized')
                              .toList(),
                          provider: provider,
                          subscriptionProvider: subscriptionProvider,
                          context: context,
                          isUncategorizedNode: true,
                        ),
                      ],

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
                          launchUrl(Uri(scheme: 'mailto', path: 'info@devopen.io'));
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
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
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  /// Small rounded icon chip used as the leading element of drawer rows.
  Widget _buildIconChip(
    BuildContext context, {
    required IconData icon,
    required bool isSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primaryContainer
            : cs.surfaceContainerHigh.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 17,
        color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
    );
  }

  /// Rounded count pill shown at the trailing edge of rows.
  Widget _buildCountPill(BuildContext context, int count, bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primary.withValues(alpha: 0.14)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: tt.labelSmall?.copyWith(
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Expandable category tile with child feed items.
  Widget _buildExpandableCategoryItem({
    required IconData categoryIcon,
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

    final count = provider.items
        .where((item) => item.category == targetCategory)
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: ExpansionTile(
          initiallyExpanded: provider.selectedCategory == targetCategory,
          tilePadding: const EdgeInsets.only(left: 10, right: 10),
          childrenPadding: const EdgeInsets.only(left: 12, right: 8, bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: isCategorySelected
              ? cs.primaryContainer.withValues(alpha: 0.22)
              : Colors.transparent,
          collapsedBackgroundColor: isCategorySelected
              ? cs.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          iconColor: cs.onSurfaceVariant,
          collapsedIconColor: cs.onSurfaceVariant.withValues(alpha: 0.6),
          leading: _buildIconChip(
            context,
            icon: categoryIcon,
            isSelected: isCategorySelected,
          ),
          title: GestureDetector(
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
                      color: isCategorySelected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.8),
                      fontWeight:
                          isCategorySelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  _buildCountPill(context, count, isCategorySelected),
                ],
              ],
            ),
          ),
          children: feedSources.map((sub) {
            final bool isFeedSelected = provider.selectedFeedUrl == sub.url;
            final feedCount = provider.items
                .where((item) => item.feedUrl == sub.url)
                .length;

            return Padding(
              padding: const EdgeInsets.only(left: 22.0, top: 2.0),
              child: Material(
                color: isFeedSelected
                    ? cs.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    provider.selectFeed(sub.url);
                    onFeedSelected?.call();
                    context.pop();
                  },
                  onLongPress: () => _showDeleteFeedDialog(context, sub, subscriptionProvider),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFeedSelected
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
                              color: isFeedSelected
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.65),
                              fontWeight: isFeedSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (feedCount > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$feedCount',
                            style: tt.labelSmall?.copyWith(
                              color: isFeedSelected
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
          }).toList(),
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
                _buildIconChip(context, icon: icon, isSelected: isSelected),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: tt.bodyMedium?.copyWith(
                      color: isSelected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.8),
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 8),
                  _buildCountPill(context, count, isSelected),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteFeedDialog(
    BuildContext context,
    FeedSubscription sub,
    SubscriptionProvider subscriptionProvider,
  ) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.deleteFeed),
        content: Text(l10n.deleteFeedConfirm(sub.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              subscriptionProvider.removeFeed(sub.url);
            },
            child: Text(l10n.delete),
          ),
        ],
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
              _buildIconChip(
                context,
                icon: Icons.info_outline,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'v1.0.0',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    showAboutDialog(
      context: context,
      applicationName: l10n.appName,
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset('assets/logo.ico', width: 48, height: 48),
      ),
      applicationVersion: '1.0.0',
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
            launchUrl(
              Uri.parse('mailto:info@devopen.io'),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 4.0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.email_outlined,
                  size: 20,
                  color: cs.primary,
                ),
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
              Uri.parse(
                'https://github.com/DevOpen-io/Dondurma-Rss-Reader',
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 4.0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.code,
                  size: 20,
                  color: cs.primary,
                ),
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
