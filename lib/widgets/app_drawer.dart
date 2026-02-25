import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedProvider>();
    final categories = provider.categories.toList()..sort();

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
                    'Ice Cream Reader',
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
                  _buildSectionHeader('CATEGORIES'),
                  _buildDrawerItem(
                    icon: Icons.article,
                    title: 'All News',
                    count: '${provider.items.length}',
                    isSelected: provider.selectedCategory == null,
                    context: context,
                    onTap: () {
                      provider.selectCategory(null);
                      Navigator.pop(context);
                    },
                  ),

                  ...categories.where((c) => c != 'Uncategorized').map((
                    category,
                  ) {
                    final feedSources = provider.subscriptions
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
                    _buildSectionHeader('UNCATEGORIZED'),
                    _buildExpandableCategoryItem(
                      icon: Icons.rss_feed,
                      title: 'Random Blogs',
                      feedSources: provider.subscriptions
                          .where((sub) => sub.category == 'Uncategorized')
                          .toList(),
                      provider: provider,
                      context: context,
                      isUncategorizedNode: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 8.0,
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
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
            color: isCategorySelected ? colorScheme.primary : Colors.grey,
            size: 22,
          ),
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              provider.selectCategory(targetCategory);
              Navigator.pop(context);
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
                            : Colors.grey,
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
                  Navigator.pop(context);
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
          color: isSelected ? colorScheme.primary : Colors.grey,
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
                    color: isSelected ? colorScheme.primary : Colors.grey,
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
