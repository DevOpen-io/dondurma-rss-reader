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
                  Icon(
                    Icons.rss_feed,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'RSS Reader',
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
                    final count = provider.items
                        .where((item) => item.category == category)
                        .length;
                    return _buildDrawerItem(
                      icon: Icons.folder,
                      title: category,
                      count: count.toString(),
                      isSelected: provider.selectedCategory == category,
                      context: context,
                      onTap: () {
                        provider.selectCategory(category);
                        Navigator.pop(context);
                      },
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
                    _buildDrawerItem(
                      icon: Icons.rss_feed,
                      title: 'Random Blogs',
                      count: provider.items
                          .where((item) => item.category == 'Uncategorized')
                          .length
                          .toString(),
                      isSelected: provider.selectedCategory == 'Uncategorized',
                      context: context,
                      onTap: () {
                        provider.selectCategory('Uncategorized');
                        Navigator.pop(context);
                      },
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

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    String? count,
    bool isSelected = false,
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
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
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
    );
  }
}
