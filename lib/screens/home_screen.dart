import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/feed_list_item.dart';
import '../widgets/add_feed_dialog.dart';
import '../widgets/home/home_bottom_nav.dart';
import '../widgets/home/home_search_history_panel.dart';
import '../widgets/home/home_pagination_footer.dart';
import '../widgets/home/feed_list_skeleton.dart';
import '../widgets/home/add_folder_dialog.dart';
import 'folders_screen.dart';
import 'bookmarks_screen.dart';
import 'settings_screen.dart';

/// Main screen with bottom navigation bar hosting Feeds, Folders, Bookmarks,
/// and Settings tabs. The Feeds tab includes a search bar, unread filter,
/// and category/feed selection via the drawer.
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddFeedDialog(),
    );
  }

  void _showAddFolderDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const AddFolderDialog(),
    );
  }

  Widget _buildHomeBody(
    BuildContext context,
    FeedProvider provider,
    List<FeedItem> todayItems,
    List<FeedItem> yesterdayItems,
    List<FeedItem> olderItems,
  ) {
    final l10n = AppLocalizations.of(context);
    final bool hasAnyItems =
        todayItems.isNotEmpty ||
        yesterdayItems.isNotEmpty ||
        olderItems.isNotEmpty;

    // Flatten items into a single list with headers
    final List<Widget> listItems = [];

    if (todayItems.isNotEmpty) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildSectionHeader(l10n.today),
        ),
      );
      listItems.addAll(
        todayItems.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FeedListItem(item: item),
          ),
        ),
      );
    }

    if (yesterdayItems.isNotEmpty) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildSectionHeader(l10n.yesterday),
        ),
      );
      listItems.addAll(
        yesterdayItems.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FeedListItem(item: item),
          ),
        ),
      );
    }

    if (olderItems.isNotEmpty) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildSectionHeader(l10n.older),
        ),
      );
      listItems.addAll(
        olderItems.map(
          (item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FeedListItem(item: item),
          ),
        ),
      );
    }

    // Pagination footer
    listItems.add(HomePaginationFooter(provider: provider));

    // Empty states
    if (provider.items.isEmpty && !provider.isLoading) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.rss_feed,
                size: 56,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noFeedsFound,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.55),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _showAddFeedDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.semanticAddFeed),
              ),
            ],
          ),
        ),
      );
    } else if (!hasAnyItems && !provider.isLoading) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              provider.selectedCategory != null
                  ? l10n.noFeedsInCategory(provider.selectedCategory!)
                  : l10n.noFeedsMatchFilter,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    // Bottom padding
    listItems.add(const SizedBox(height: 80));

    return RefreshIndicator(
      onRefresh: () async {
        await provider.refreshAll();
      },
      child: provider.isLoading && provider.items.isEmpty
          ? const FeedListSkeleton()
          : Column(
              children: [
                // ── Offline banner ─────────────────────────────────────────
                if (provider.isOffline && provider.items.isNotEmpty)
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.wifi_off,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.offlineBanner,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Feed list ──────────────────────────────────────────────
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      if (!provider.isLoadingMore &&
                          provider.hasMoreItems &&
                          scrollInfo.metrics.pixels >=
                              scrollInfo.metrics.maxScrollExtent - 300) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          provider.loadMoreItems();
                        });
                      }
                      return false;
                    },
                    child: ScrollablePositionedList.builder(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      itemCount: listItems.length,
                      itemBuilder: (context, index) {
                        return listItems[index];
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appBarTitle = context.select<FeedProvider, String>((p) {
      switch (_selectedIndex) {
        case 1:
          return l10n.foldersTab;
        case 2:
          return l10n.bookmarksTab;
        case 3:
          return l10n.settingsTab;
        case 0:
        default:
          return p.selectedCategory ?? l10n.myFeeds;
      }
    });
    final showUnreadOnly = context.select<FeedProvider, bool>(
      (p) => p.showUnreadOnly,
    );

    return Scaffold(
      extendBody: true,
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
                    hintText: l10n.searchFeeds,
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
                    context.read<FeedProvider>().setSearchQuery(value);
                  },
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      context.read<SettingsProvider>().addSearchQuery(value);
                    }
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
                  showUnreadOnly
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: showUnreadOnly
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                tooltip: showUnreadOnly
                    ? l10n.semanticShowAll
                    : l10n.semanticFilterUnread,
                onPressed: () {
                  context.read<FeedProvider>().toggleShowUnreadOnly();
                },
              ),
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.semanticCloseSearch,
                onPressed: () {
                  final query = _searchController.text.trim();
                  if (query.isNotEmpty) {
                    context.read<SettingsProvider>().addSearchQuery(query);
                  }
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                  });
                  context.read<FeedProvider>().setSearchQuery('');
                },
              )
            else
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: l10n.semanticOpenSearch,
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
          ? Consumer<FeedProvider>(
              builder: (context, provider, _) {
                final todayItems = provider.todayItems;
                final yesterdayItems = provider.yesterdayItems;
                final olderItems = provider.olderItems;
                return Column(
                  children: [
                    // ── Search history suggestions ────────────────────────────
                    if (_isSearching)
                      HomeSearchHistoryPanel(
                        searchController: _searchController,
                        onQuerySelected: (query) {
                          _searchController.text = query;
                          _searchController.selection =
                              TextSelection.fromPosition(
                            TextPosition(offset: query.length),
                          );
                          provider.setSearchQuery(query);
                        },
                      ),
                    Expanded(
                      child: _buildHomeBody(
                        context,
                        provider,
                        todayItems,
                        yesterdayItems,
                        olderItems,
                      ),
                    ),
                  ],
                );
              },
            )
          : _selectedIndex == 1
          ? const FoldersScreen()
          : _selectedIndex == 2
          ? const BookmarksScreen()
          : const SettingsScreen(),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    Expanded(
                      child: NavBarItem(
                        icon: _selectedIndex == 0
                            ? Icons.list
                            : Icons.list_outlined,
                        label: l10n.feedsTab,
                        selected: _selectedIndex == 0,
                        onTap: () => _onItemTapped(0),
                      ),
                    ),
                    Expanded(
                      child: NavBarItem(
                        icon: _selectedIndex == 1
                            ? Icons.folder
                            : Icons.folder_outlined,
                        label: l10n.foldersTab,
                        selected: _selectedIndex == 1,
                        onTap: () => _onItemTapped(1),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: AnimatedOpacity(
                        opacity: _selectedIndex <= 1 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: _selectedIndex > 1,
                          child: Tooltip(
                            message: _selectedIndex == 0
                                ? l10n.semanticAddFeed
                                : l10n.addFolder,
                            child: GestureDetector(
                              onTap: _selectedIndex == 0
                                  ? _showAddFeedDialog
                                  : _showAddFolderDialog,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _selectedIndex == 0
                                      ? Icons.rss_feed
                                      : Icons.create_new_folder_outlined,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: NavBarItem(
                        icon: _selectedIndex == 2
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        label: l10n.bookmarksTab,
                        selected: _selectedIndex == 2,
                        onTap: () => _onItemTapped(2),
                      ),
                    ),
                    Expanded(
                      child: NavBarItem(
                        icon: _selectedIndex == 3
                            ? Icons.settings
                            : Icons.settings_outlined,
                        label: l10n.settingsTab,
                        selected: _selectedIndex == 3,
                        onTap: () => _onItemTapped(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {String? trailingText}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: colorScheme.primary.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          if (trailingText != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                trailingText,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                  fontSize: 11.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

