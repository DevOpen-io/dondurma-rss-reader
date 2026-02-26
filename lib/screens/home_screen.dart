import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/feed_list_item.dart';
import '../widgets/add_feed_dialog.dart';
import 'folders_screen.dart';
import 'bookmarks_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showAddFeedDialog() {
    showDialog(context: context, builder: (context) => const AddFeedDialog());
  }

  Widget _buildHomeBody(
    BuildContext context,
    FeedProvider provider,
    List<FeedItem> todayItems,
    List<FeedItem> yesterdayItems,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        await provider.refreshAll();
      },
      child: provider.isLoading && provider.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                if (scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 200) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    provider.loadMoreItems();
                  });
                }
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (todayItems.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      sliver: SliverToBoxAdapter(
                        child: _buildSectionHeader(
                          'LATEST',
                          trailingText: 'Subscribed Only',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      sliver: SliverList.builder(
                        itemCount: todayItems.length,
                        itemBuilder: (context, index) {
                          return FeedListItem(item: todayItems[index]);
                        },
                      ),
                    ),
                  ],
                  if (yesterdayItems.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      sliver: SliverToBoxAdapter(
                        child: _buildSectionHeader('OLDER'),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      sliver: SliverList.builder(
                        itemCount: yesterdayItems.length,
                        itemBuilder: (context, index) {
                          return FeedListItem(item: yesterdayItems[index]);
                        },
                      ),
                    ),
                  ],
                  if (provider.items.isEmpty && !provider.isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(
                          child: Text(
                            'No feeds found. Add a new feed using the + button.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else if (todayItems.isEmpty &&
                      yesterdayItems.isEmpty &&
                      !provider.isLoading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Text(
                            'No feeds found in ${provider.selectedCategory}.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedProvider>();
    final todayItems = provider.todayItems;
    final yesterdayItems = provider.yesterdayItems;

    String appBarTitle;
    switch (_selectedIndex) {
      case 1:
        appBarTitle = 'Folders';
        break;
      case 2:
        appBarTitle = 'Bookmarks';
        break;
      case 3:
        appBarTitle = 'Settings';
        break;
      case 0:
      default:
        appBarTitle = provider.selectedCategory ?? 'My Feeds';
    }

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _isSearching && _selectedIndex == 0
              ? TextField(
                  key: const ValueKey('searchField'),
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search feeds...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                  ),
                  onChanged: (value) {
                    provider.setSearchQuery(value);
                  },
                )
              : Text(
                  appBarTitle,
                  key: ValueKey(appBarTitle),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
        actions: [
          if (_selectedIndex == 0) ...[
            if (!_isSearching)
              IconButton(
                icon: Icon(
                  provider.showUnreadOnly
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: provider.showUnreadOnly
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: () {
                  provider.toggleShowUnreadOnly();
                },
              ),
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                  });
                  provider.setSearchQuery('');
                },
              )
            else
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() {
                    _isSearching = true;
                  });
                },
              ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      drawer: AppDrawer(
        onFeedSelected: () {
          if (_selectedIndex != 0) {
            _onItemTapped(0);
          }
        },
      ),
      body: _selectedIndex == 0
          ? _buildHomeBody(context, provider, todayItems, yesterdayItems)
          : _selectedIndex == 1
          ? const FoldersScreen()
          : _selectedIndex == 2
          ? const BookmarksScreen()
          : const SettingsScreen(),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddFeedDialog,
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add, size: 28),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_outlined),
            selectedIcon: Icon(Icons.list),
            label: 'Feeds',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Folders',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Bookmarks',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {String? trailingText}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12.0,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          if (trailingText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                trailingText,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 11.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
