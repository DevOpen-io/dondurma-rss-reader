import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../models/refresh_progress.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/feed_date_groups.dart';
import '../widgets/app_drawer.dart';
import '../widgets/anchored_feed_list.dart';
import '../widgets/feed_list_item.dart';
import '../widgets/add_feed_dialog.dart';
import '../widgets/home/home_search_history_panel.dart';
import '../widgets/home/home_pagination_footer.dart';
import '../widgets/home/feed_empty_state.dart';
import '../widgets/home/feed_list_skeleton.dart';
import '../models/saved_search.dart';
import '../services/shared_links.dart';
import '../widgets/saved_searches.dart';
import '../widgets/home/add_category_dialog.dart';
import '../widgets/home/add_destination.dart';
import '../widgets/home/filter_bottom_sheet.dart';
import '../widgets/home/mark_all_read_button.dart';
import '../widgets/home/offline_banner.dart';
import '../widgets/home/refresh_progress_count.dart';
import '../widgets/constrained_width.dart';
import '../widgets/adaptive_dialog.dart';
import '../utils/app_toast.dart';
import '../utils/motion.dart';
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
  final _feedScroll = AnchoredScrollController();

  @override
  void initState() {
    super.initState();
    SharedLinks.pending.addListener(_openSharedLink);
    // A link shared before the home screen existed (cold start, onboarding).
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSharedLink());
  }

  @override
  void dispose() {
    SharedLinks.pending.removeListener(_openSharedLink);
    _searchController.dispose();
    _feedScroll.dispose();
    super.dispose();
  }

  /// Runs a saved search on the feed tab: its scope, filters and query.
  void _openSearch(SavedSearch search) {
    setState(() {
      _selectedIndex = 0;
      _isSearching = true;
      _searchController.text = search.query;
    });
    context.read<FeedProvider>().applySavedSearch(search);
    // Show the results, not the keyboard the search field asks for.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FocusManager.instance.primaryFocus?.unfocus(),
    );
  }

  /// A link shared from another app opens "Add feed" with it filled in.
  void _openSharedLink() {
    final text = SharedLinks.pending.value;
    if (text == null || !mounted) return;
    SharedLinks.pending.value = null;
    final url = sharedUrl(text);
    if (url == null) {
      showAppToast(
        AppLocalizations.of(context).noLinkInShare,
        type: AppToastType.info,
      );
      return;
    }
    if (_selectedIndex != 0) _onItemTapped(0);
    // One "Add feed" at a time: a new share replaces whatever is open.
    Navigator.of(context).popUntil((route) => route.isFirst);
    showAdaptiveSheet<void>(context, AddFeedDialog(initialUrl: url));
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showAddFeedDialog() {
    showAdaptiveSheet<void>(context, const AddFeedDialog());
  }

  void _showAddFolderDialog() {
    showAdaptiveSheet<void>(context, const AddCategoryDialog());
  }

  Widget _buildHomeBody(
    BuildContext context,
    FeedProvider provider,
    List<FeedItem> todayItems,
    List<FeedItem> yesterdayItems,
    List<FeedItem> olderItems,
  ) {
    final l10n = AppLocalizations.of(context);
    final flat = context.select<SettingsProvider, bool>(
      (s) => s.articleListStyle == 'list',
    );
    final markOnScroll = context.select<SettingsProvider, bool>(
      (s) => s.markReadOnScroll,
    );
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

    entries.add(const _WidgetEntry(HomePaginationFooter()));

    if (!hasAnyItems && !provider.isLoading) {
      entries.add(
        _WidgetEntry(
          FeedEmptyState(
            provider: provider,
            onAddFeed: _showAddFeedDialog,
            searchController: _searchController,
            showSwipeHint: true,
          ),
        ),
      );
    }

    entries.add(const _WidgetEntry(SizedBox(height: 16)));
    final articleIds = articleRowIds([
      ...todayItems,
      ...yesterdayItems,
      ...olderItems,
    ]);
    var articleIndex = 0;
    var auxiliaryIndex = 0;
    final rowIds = <Object>[
      for (final entry in entries)
        switch (entry) {
          _ItemEntry() => articleIds[articleIndex++],
          _HeaderEntry(:final label) => ('header', label),
          _WidgetEntry() => ('auxiliary', auxiliaryIndex++),
        },
    ];

    return RefreshIndicator(
      // The pull gesture stays, but its own spinner is hidden — the
      // floating progress pill (completed / total) is the single global
      // refresh indicator for this screen.
      color: Colors.transparent,
      backgroundColor: Colors.transparent,
      elevation: 0,
      onRefresh: () async {
        await provider.refreshAll(userInitiated: true);
      },
      child: provider.isLoading && provider.items.isEmpty
          ? const FeedListSkeleton()
          : Column(
              children: [
                // ── Offline banner ─────────────────────────────────────────
                if (provider.isOffline && provider.items.isNotEmpty)
                  const OfflineBanner(),

                // ── Feed list — virtualized ────────────────────────────────
                // itemBuilder is called only for visible rows. FeedListItem
                // widgets for off-screen items are never constructed.
                Expanded(
                  child: FeedLoadMoreListener(
                    // One lazy viewport, anchored to the visible article when
                    // incoming source results insert/reorder rows above it.
                    child: AnchoredFeedList(
                      controller: _feedScroll,
                      rowIds: rowIds,
                      isArticle: (index) => entries[index] is _ItemEntry,
                      onArticlesScrolledPast: markOnScroll
                          ? (indexes) => provider.markItemsAsRead([
                              for (final i in indexes)
                                if (entries[i] case _ItemEntry(:final item))
                                  item,
                            ])
                          : null,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return switch (entry) {
                          _HeaderEntry(:final label) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildSectionHeader(label),
                          ),
                          _ItemEntry(:final item) => Padding(
                            // List rows run edge to edge; cards keep margins.
                            padding: EdgeInsets.symmetric(
                              horizontal: flat ? 0 : 16,
                            ),
                            child: FeedListItem(item: item, flat: flat),
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

    // The feed tab hands the Scaffold its top-aware controller so an iOS
    // status-bar tap reaches the real head, not the rebased center. It is
    // not inherited by other scrollables; other tabs keep the route's.
    final routeScroll = PrimaryScrollController.maybeOf(context);
    final feedTab = _selectedIndex == 0 || routeScroll == null;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: motionDuration(context, const Duration(milliseconds: 300)),
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
                  // addSearchQuery trims and ignores empty queries.
                  onSubmitted: (value) =>
                      context.read<SettingsProvider>().addSearchQuery(value),
                )
              : Text(
                  appBarTitle,
                  key: ValueKey(appBarTitle),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        actions: [
          if (_selectedIndex == 0) ...[
            if (!_isSearching) FilterSheetButton(active: hasActiveFilter),
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.semanticCloseSearch,
                onPressed: () {
                  context.read<SettingsProvider>().addSearchQuery(
                    _searchController.text,
                  );
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
            PopupMenuButton<_FeedMenuAction>(
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _FeedMenuAction.markRead,
                  enabled: context.read<FeedProvider>().hasUnreadInView,
                  child: Text(l10n.markAllAsRead),
                ),
                if (_isSearching)
                  PopupMenuItem(
                    value: _FeedMenuAction.saveSearch,
                    enabled: context
                        .read<FeedProvider>()
                        .searchQuery
                        .trim()
                        .isNotEmpty,
                    child: Text(l10n.saveSearch),
                  ),
              ],
              onSelected: (action) => switch (action) {
                _FeedMenuAction.markRead => showMarkReadDialog(context),
                _FeedMenuAction.saveSearch => saveCurrentSearch(context),
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
        onSavedSearch: _openSearch,
      ),
      body: _selectedIndex == 0
          ? Selector<FeedProvider, _FeedTabInputs>(
              selector: (_, p) => (
                groups: p.dateGroups,
                isLoading: p.isLoading,
                isOffline: p.isOffline,
                hasItems: p.items.isNotEmpty,
                filters: (
                  category: p.selectedCategory,
                  sheetFilter: p.hasActiveSheetFilter,
                  search: p.searchQuery,
                  unreadOnly: p.showUnreadOnly,
                ),
              ),
              builder: (context, inputs, _) {
                final provider = context.read<FeedProvider>();
                final todayItems = inputs.groups.today;
                final yesterdayItems = inputs.groups.yesterday;
                final olderItems = inputs.groups.older;
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
                      child: ConstrainedWidth(
                        child: Stack(
                          children: [
                            _buildHomeBody(
                              context,
                              provider,
                              todayItems,
                              yesterdayItems,
                              olderItems,
                            ),
                            // Compact pull-to-refresh progress — floats above
                            // the list so it never shifts layout or crowds
                            // the AppBar actions.
                            Positioned(
                              top: 8,
                              left: 0,
                              right: 0,
                              child: _RefreshProgressPill(
                                progress: provider.refreshProgress,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          : _selectedIndex == 1
          ? CategoriesScreen(onFeedSelected: () => _onItemTapped(0))
          : _selectedIndex == 2
          ? const BookmarksScreen()
          : const SettingsScreen(),
      // Standard bar: fixed to the bottom edge. Adding is the one action
      // every new reader looks for, so it sits in the middle of the bar on
      // every tab: a folder on the folder tab, a feed everywhere else.
      bottomNavigationBar: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: ConstrainedWidth(
          maxWidth: 480,
          child: NavigationBar(
            height: 68,
            // The add action is the bar's middle slot, not a tab.
            selectedIndex: _selectedIndex < 2
                ? _selectedIndex
                : _selectedIndex + 1,
            onDestinationSelected: (index) {
              if (index != 2) _onItemTapped(index < 2 ? index : index - 1);
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.list_outlined),
                selectedIcon: const Icon(Icons.list),
                label: l10n.feedsTab,
              ),
              NavigationDestination(
                icon: const Icon(Icons.folder_outlined),
                selectedIcon: const Icon(Icons.folder),
                label: l10n.foldersTab,
              ),
              _selectedIndex == 1
                  ? AddDestination(
                      key: const ValueKey('add-folder'),
                      label: l10n.addFolder,
                      onPressed: _showAddFolderDialog,
                    )
                  : AddDestination(
                      key: const ValueKey('add-feed'),
                      label: l10n.addFeedButton,
                      onPressed: _showAddFeedDialog,
                    ),
              NavigationDestination(
                icon: const Icon(Icons.bookmark_border),
                selectedIcon: const Icon(Icons.bookmark),
                label: l10n.bookmarksTab,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: l10n.settingsTab,
              ),
            ],
          ),
        ),
      ),
    );
    return PrimaryScrollController(
      controller: feedTab ? _feedScroll : routeScroll,
      automaticallyInheritForPlatforms: feedTab
          ? const {}
          : const {
              TargetPlatform.android,
              TargetPlatform.iOS,
              TargetPlatform.fuchsia,
            },
      child: scaffold,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Virtual list descriptors — lightweight data objects used to build the feed
// list. Widgets are constructed by itemBuilder only when rows scroll into view.
// ---------------------------------------------------------------------------

/// Feed-tab overflow entries: marking the view read and keeping the
/// current search.
enum _FeedMenuAction { markRead, saveSearch }

/// Everything the feed tab's list renders from [FeedProvider]. Rows select
/// their own read/bookmark/offline state, so a notification that changes
/// none of these (sync stamps, status reloads) leaves the list alone.
typedef _FeedTabInputs = ({
  FeedDateGroups groups,
  bool isLoading,
  bool isOffline,
  bool hasItems,
  // Read by the empty state to explain an empty filtered list.
  ({String? category, bool sheetFilter, String search, bool unreadOnly})
  filters,
});

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

/// Compact floating refresh-progress pill for the mobile feed tab.
///
/// Pull-to-refresh has no persistent toolbar button, so while a pass runs
/// this pill shows `completed / total` above the list. Listens to the shared
/// [RefreshProgress] notifier — only the pill rebuilds per feed.
class _RefreshProgressPill extends StatelessWidget {
  const _RefreshProgressPill({required this.progress});

  final ValueListenable<RefreshProgress> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RefreshProgress>(
      valueListenable: progress,
      builder: (context, value, _) {
        if (value.phase != RefreshPhase.refreshing || value.total == 0) {
          return const SizedBox.shrink();
        }
        return Center(
          child: Semantics(
            liveRegion: true,
            label: AppLocalizations.of(
              context,
            ).refreshingFeeds(value.completed, value.total),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              elevation: 3,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: RefreshProgressCount(progress: value),
              ),
            ),
          ),
        );
      },
    );
  }
}
