import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';
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
import '../widgets/home/add_category_dialog.dart';
import '../widgets/home/filter_bottom_sheet.dart';
import 'categories_screen.dart';
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
      builder: (ctx) => const AddCategoryDialog(),
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
    final cs = Theme.of(context).colorScheme;
    final bool hasAnyItems =
        todayItems.isNotEmpty ||
        yesterdayItems.isNotEmpty ||
        olderItems.isNotEmpty;

    // Build a descriptor list — lightweight data objects, no widgets yet.
    // FeedListItem widgets are constructed lazily inside itemBuilder when the
    // row scrolls into view. This gives true virtualization equivalent to
    // React Virtuoso: only visible rows are in the widget tree.
    final List<_FeedListEntry> entries = [];

    if (todayItems.isNotEmpty) {
      entries.add(_HeaderEntry(l10n.today));
      for (final item in todayItems) {
        entries.add(_ItemEntry(item));
      }
    }
    if (yesterdayItems.isNotEmpty) {
      entries.add(_HeaderEntry(l10n.yesterday));
      for (final item in yesterdayItems) {
        entries.add(_ItemEntry(item));
      }
    }
    if (olderItems.isNotEmpty) {
      entries.add(_HeaderEntry(l10n.older));
      for (final item in olderItems) {
        entries.add(_ItemEntry(item));
      }
    }

    entries.add(_WidgetEntry(HomePaginationFooter(provider: provider)));

    if (provider.items.isEmpty && !provider.isLoading) {
      entries.add(
        _WidgetEntry(
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 48.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.rss_feed,
                  size: 56,
                  color: cs.onSurface.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.noFeedsFound,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.55),
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
        ),
      );
    } else if (!hasAnyItems && !provider.isLoading) {
      entries.add(
        _WidgetEntry(
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.selectedCategory != null
                      ? l10n.noFeedsInCategory(provider.selectedCategory!)
                      : l10n.noFeedsMatchFilter,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
                if (provider.hasActiveSheetFilter ||
                    provider.searchQuery.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      provider.setSearchQuery('');
                      if (provider.hasActiveSheetFilter) {
                        provider.clearSheetFilter();
                      }
                    },
                    child: Text(l10n.clearFilters),
                  ),
                ],
                if (provider.showUnreadOnly) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.readSwipeHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    entries.add(const _WidgetEntry(SizedBox(height: 80)));

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
                    color: cs.errorContainer,
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
                            color: cs.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.offlineBanner,
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Feed list — virtualized ────────────────────────────────
                // itemBuilder is called only for visible rows. FeedListItem
                // widgets for off-screen items are never constructed.
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
                    // ListView.builder: single viewport, true lazy rendering.
                    // cacheExtent = 200px pre-renders ~2 items outside the
                    // visible area so fast scrolling never shows blank frames.
                    // ScrollablePositionedList used dual viewports internally
                    // (anchor + main) even though we never used position-jump;
                    // replaced to eliminate that overhead entirely.
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      scrollCacheExtent: ScrollCacheExtent.pixels(200),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return switch (entry) {
                          _HeaderEntry(:final label) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildSectionHeader(label),
                          ),
                          _ItemEntry(:final item) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: FeedListItem(item: item),
                          ),
                          _WidgetEntry(:final child) => child,
                        };
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
    final hasActiveFilter = context.select<FeedProvider, bool>(
      (p) => p.hasActiveSheetFilter,
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
                icon: Badge(
                  isLabelVisible: hasActiveFilter,
                  smallSize: 8,
                  child: Icon(
                    Icons.filter_list,
                    color: hasActiveFilter
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                tooltip: l10n.filterSheetTitle,
                onPressed: () => FilterBottomSheet.show(context),
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
          ? const CategoriesScreen()
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
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _selectedIndex == 0
                                      ? Icons.add
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

// ---------------------------------------------------------------------------
// Virtual list descriptors — lightweight data objects used to build the feed
// list. Widgets are constructed by itemBuilder only when rows scroll into view.
// ---------------------------------------------------------------------------

sealed class _FeedListEntry {
  const _FeedListEntry();
}

final class _HeaderEntry extends _FeedListEntry {
  final String label;
  const _HeaderEntry(this.label);
}

final class _ItemEntry extends _FeedListEntry {
  final FeedItem item;
  const _ItemEntry(this.item);
}

final class _WidgetEntry extends _FeedListEntry {
  final Widget child;
  const _WidgetEntry(this.child);
}
