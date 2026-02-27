import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../models/feed_subscription.dart';
import 'explore_feeds_dialog.dart';

class AppDrawer extends StatelessWidget {
  final VoidCallback? onFeedSelected;

  const AppDrawer({super.key, this.onFeedSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<FeedProvider>();
    final subscriptionProvider = context.watch<SubscriptionProvider>();
    final categories = subscriptionProvider.categories.toList()..sort();

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
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
                  const SizedBox(width: 12),
                  Text(
                    l10n.appName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildSectionHeader(context, l10n.categories),
                  _buildDrawerItem(
                    icon: Icons.article,
                    title: l10n.allNews,
                    count: '${provider.items.length}',
                    isSelected: provider.selectedCategory == null,
                    context: context,
                    onTap: () {
                      provider.selectCategory(null);
                      onFeedSelected?.call();
                      context.pop();
                    },
                  ),

                  ...categories.where((c) => c != 'Uncategorized').map((
                    category,
                  ) {
                    final feedSources = subscriptionProvider.subscriptions
                        .where((sub) => sub.category == category)
                        .toList();

                    return _buildExpandableCategoryItem(
                      icon: Icons.folder,
                      title: category,
                      feedSources: feedSources,
                      provider: provider,
                      context: context,
                    );
                  }),

                  Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    height: 32,
                  ),

                  if (categories.contains('Uncategorized')) ...[
                    _buildSectionHeader(context, l10n.uncategorized),
                    _buildExpandableCategoryItem(
                      icon: Icons.rss_feed,
                      title: l10n.randomBlogs,
                      feedSources: subscriptionProvider.subscriptions
                          .where((sub) => sub.category == 'Uncategorized')
                          .toList(),
                      provider: provider,
                      context: context,
                      isUncategorizedNode: true,
                    ),
                    Divider(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.1),
                      height: 32,
                    ),
                  ],

                  _buildSectionHeader(context, l10n.discover),
                  _buildDrawerItem(
                    icon: Icons.lightbulb_outline,
                    title: l10n.suggestedFeeds,
                    context: context,
                    onTap: () {
                      context.pop();
                      showDialog(
                        context: context,
                        builder: (context) => const ExploreFeedsDialog(),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 8.0,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildExpandableCategoryItem({
    required IconData icon,
    required String title,
    required List<FeedSubscription> feedSources,
    required FeedProvider provider,
    required BuildContext context,
    bool isUncategorizedNode = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final String targetCategory = isUncategorizedNode ? 'Uncategorized' : title;
    final bool isCategorySelected =
        provider.selectedCategory == targetCategory &&
        provider.selectedFeedUrl == null;

    final count = provider.items
        .where((item) => item.category == targetCategory)
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent, // Remove expansion lines
        ),
        child: ExpansionTile(
          initiallyExpanded: provider.selectedCategory == targetCategory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isCategorySelected
              ? colorScheme.primary.withAlpha((0.05 * 255).toInt())
              : Colors.transparent,
          collapsedBackgroundColor: isCategorySelected
              ? colorScheme.primary.withAlpha((0.1 * 255).toInt())
              : Colors.transparent,
          leading: Icon(
            icon,
            color: isCategorySelected
                ? colorScheme.primary
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
            size: 22,
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
                    style: TextStyle(
                      color: isCategorySelected
                          ? colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: isCategorySelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isCategorySelected
                          ? colorScheme.primary.withAlpha((0.2 * 255).toInt())
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count.toString(),
                      style: TextStyle(
                        color: isCategorySelected
                            ? colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          children: feedSources.map((sub) {
            final bool isFeedSelected = provider.selectedFeedUrl == sub.url;
            final feedCount = provider.items
                .where((item) => item.feedUrl == sub.url)
                .length;

            return Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 2.0),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  sub.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: isFeedSelected
                        ? colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: isFeedSelected
                        ? FontWeight.bold
                        : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: feedCount > 0
                    ? Text(
                        feedCount.toString(),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      )
                    : null,
                selected: isFeedSelected,
                selectedTileColor: colorScheme.primary.withAlpha(
                  (0.05 * 255).toInt(),
                ),
                onTap: () {
                  provider.selectFeed(sub.url);
                  onFeedSelected?.call();
                  context.pop();
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    String? count,
    bool isSelected = false,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          icon,
          color: isSelected
              ? colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? colorScheme.primary
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: (count != null && count != '0')
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withAlpha((0.2 * 255).toInt())
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count,
                  style: TextStyle(
                    color: isSelected
                        ? colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        selected: isSelected,
        selectedTileColor: colorScheme.primary.withAlpha((0.1 * 255).toInt()),
        onTap: onTap,
      ),
    );
  }
}
