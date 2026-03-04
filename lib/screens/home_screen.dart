import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/feed_list_item.dart';
import '../widgets/add_feed_dialog.dart';
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
    showDialog(context: context, builder: (context) => const AddFeedDialog());
  }

  void _showAddFolderDialog() {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    String? errorText;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.addFolder),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.newFolderName,
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() {
                    errorText = l10n.pleaseEnterFolderName;
                  });
                  return;
                }
                context.read<SubscriptionProvider>().addCategory(name).then((
                  success,
                ) {
                  if (!success && ctx.mounted) {
                    setDialogState(() {
                      errorText = l10n.folderAlreadyExists;
                    });
                  } else if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                });
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
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
          child: _buildSectionHeader(
            l10n.today,
            trailingText: l10n.subscribedOnly,
          ),
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
    listItems.add(_PaginationFooter(provider: provider));

    // Empty states
    if (provider.items.isEmpty && !provider.isLoading) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Text(
              l10n.noFeedsFound,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
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
              style: const TextStyle(color: Colors.grey),
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
          ? const _FeedListSkeleton()
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
    final provider = context.watch<FeedProvider>();
    final todayItems = provider.todayItems;
    final yesterdayItems = provider.yesterdayItems;
    final olderItems = provider.olderItems;

    String appBarTitle;
    switch (_selectedIndex) {
      case 1:
        appBarTitle = l10n.foldersTab;
        break;
      case 2:
        appBarTitle = l10n.bookmarksTab;
        break;
      case 3:
        appBarTitle = l10n.settingsTab;
        break;
      case 0:
      default:
        appBarTitle = provider.selectedCategory ?? l10n.myFeeds;
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
                    provider.setSearchQuery(value);
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
                  provider.showUnreadOnly
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: provider.showUnreadOnly
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                tooltip: provider.showUnreadOnly
                    ? l10n.semanticShowAll
                    : l10n.semanticFilterUnread,
                onPressed: () {
                  provider.toggleShowUnreadOnly();
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
                  provider.setSearchQuery('');
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
          ? Column(
              children: [
                // ── Search history suggestions ────────────────────────────
                if (_isSearching)
                  _SearchHistoryPanel(
                    searchController: _searchController,
                    onQuerySelected: (query) {
                      _searchController.text = query;
                      _searchController.selection = TextSelection.fromPosition(
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
            )
          : _selectedIndex == 1
          ? const FoldersScreen()
          : _selectedIndex == 2
          ? const BookmarksScreen()
          : const SettingsScreen(),
      floatingActionButton: _selectedIndex <= 1
          ? Theme(
              data: Theme.of(context).copyWith(
                floatingActionButtonTheme: const FloatingActionButtonThemeData(
                  sizeConstraints: BoxConstraints.tightFor(
                    width: 80,
                    height: 80,
                  ),
                ),
              ),
              child: FloatingActionButton(
                onPressed: _selectedIndex == 0
                    ? _showAddFeedDialog
                    : _showAddFolderDialog,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                tooltip: _selectedIndex == 0
                    ? l10n.semanticAddFeed
                    : l10n.addFolder,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedIndex == 0
                          ? Icons.rss_feed
                          : Icons.create_new_folder_outlined,
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedIndex == 0 ? 'Add Feed' : 'Add Folder',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Left side: Feeds
              Expanded(
                child: _NavBarItem(
                  icon: _selectedIndex == 0 ? Icons.list : Icons.list_outlined,
                  label: l10n.feedsTab,
                  selected: _selectedIndex == 0,
                  onTap: () => _onItemTapped(0),
                ),
              ),
              // Left side: Folders
              Expanded(
                child: _NavBarItem(
                  icon: _selectedIndex == 1
                      ? Icons.folder
                      : Icons.folder_outlined,
                  label: l10n.foldersTab,
                  selected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1),
                ),
              ),
              // Center gap for FAB
              const SizedBox(width: 94),
              // Right side: Bookmarks
              Expanded(
                child: _NavBarItem(
                  icon: _selectedIndex == 2
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  label: l10n.bookmarksTab,
                  selected: _selectedIndex == 2,
                  onTap: () => _onItemTapped(2),
                ),
              ),
              // Right side: Settings
              Expanded(
                child: _NavBarItem(
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

/// A single navigation bar item used inside the custom [BottomAppBar].
class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            if (selected) ...[
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Panel that shows recent search queries as tappable suggestions.
///
/// Displayed below the AppBar when the search field is active. Filters
/// suggestions based on the current text in [searchController]. Each
/// suggestion can be tapped to fill the search or dismissed with ×.
class _SearchHistoryPanel extends StatelessWidget {
  const _SearchHistoryPanel({
    required this.searchController,
    required this.onQuerySelected,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQuerySelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsProvider = context.watch<SettingsProvider>();
    final history = settingsProvider.searchHistory;

    if (history.isEmpty) return const SizedBox.shrink();

    // Filter suggestions based on the current text
    return ListenableBuilder(
      listenable: searchController,
      builder: (context, _) {
        final currentText = searchController.text.toLowerCase().trim();
        final filtered = currentText.isEmpty
            ? history
            : history
                  .where(
                    (q) =>
                        q.toLowerCase().contains(currentText) &&
                        q.toLowerCase() != currentText,
                  )
                  .toList();

        if (filtered.isEmpty) return const SizedBox.shrink();

        return Material(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  l10n.recentSearches,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              ...filtered.map(
                (query) => InkWell(
                  onTap: () => onQuerySelected(query),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            query,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            context.read<SettingsProvider>().removeSearchQuery(
                              query,
                            );
                          },
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Footer widget shown at the bottom of the feed list.
///
/// - While [FeedProvider.isLoadingMore] is true: shows a spinner.
/// - When [FeedProvider.hasMoreItems] is true but not loading: shows a
///   "Load more" button as a fallback for users who prefer tapping.
/// - When all items are loaded: shows a subtle "You're all caught up" message.
class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.provider});

  final FeedProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (provider.items.isEmpty) return const SizedBox.shrink();

    if (provider.isLoadingMore) {
      return const _FeedListSkeleton(itemCount: 2, showHeader: false);
    }

    if (provider.hasMoreItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: TextButton.icon(
            onPressed: provider.loadMoreItems,
            icon: const Icon(Icons.expand_more),
            label: Text(l10n.loadMore),
          ),
        ),
      );
    }

    // All items rendered
    if (provider.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Text(
            l10n.allCaughtUp,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// =============================================================================
// Skeleton shimmer placeholder for feed list loading states
// =============================================================================

/// Shimmer skeleton that mimics the [FeedListItem] card layout.
///
/// Used both for initial full-screen loading and for pagination "load more"
/// states. [itemCount] controls how many fake cards are shown and
/// [showHeader] adds a fake section header above the cards.
class _FeedListSkeleton extends StatelessWidget {
  const _FeedListSkeleton({this.itemCount = 6, this.showHeader = true});

  final int itemCount;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      effect: ShimmerEffect(
        baseColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.08),
        highlightColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.15),
        duration: const Duration(milliseconds: 1500),
      ),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount + (showHeader ? 1 : 0),
        itemBuilder: (context, index) {
          if (showHeader && index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Bone.text(words: 1, fontSize: 12),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon skeleton
                  Bone.square(
                    size: 44,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  // Content skeleton
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Bone.text(words: 2, fontSize: 12)),
                            const SizedBox(width: 8),
                            Bone.text(words: 1, fontSize: 11),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Bone.multiText(lines: 2, fontSize: 15),
                        const SizedBox(height: 4),
                        Bone.text(words: 5, fontSize: 13),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Action skeleton
                  Bone.icon(size: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
