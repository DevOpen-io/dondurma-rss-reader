import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/suggested_feed.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/suggested_feeds_service.dart';
import '../utils/app_toast.dart';
import '../widgets/explore_feeds/explore_feeds_widgets.dart';

/// Full-screen page that displays a curated list of suggested RSS feeds,
/// fetched from a remote JSON endpoint.
///
/// Users can search by name, filter by category (via a bottom sheet picker),
/// and subscribe with a single tap. Undo is offered via a global toast.
class ExploreFeedsPage extends StatefulWidget {
  const ExploreFeedsPage({super.key});

  @override
  State<ExploreFeedsPage> createState() => _ExploreFeedsPageState();
}

class _ExploreFeedsPageState extends State<ExploreFeedsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _service = SuggestedFeedsService();

  List<SuggestedFeed> _globalFeeds = [];
  List<SuggestedFeed> _trFeeds = [];
  bool _isLoadingGlobal = true;
  bool _isLoadingTr = true;
  bool _hasErrorGlobal = false;
  bool _hasErrorTr = false;
  String? _selectedCategoryGlobal;
  String? _selectedCategoryTr;
  final Set<String> _subscribingUrls = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadGlobalFeeds();
    _loadTrFeeds();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<SuggestedFeed> get _activeFeeds =>
      _tabController.index == 0 ? _globalFeeds : _trFeeds;

  bool get _activeIsLoading =>
      _tabController.index == 0 ? _isLoadingGlobal : _isLoadingTr;

  bool get _activeHasError =>
      _tabController.index == 0 ? _hasErrorGlobal : _hasErrorTr;

  String? get _activeCategory =>
      _tabController.index == 0 ? _selectedCategoryGlobal : _selectedCategoryTr;

  void _setActiveCategory(String? val) {
    if (_tabController.index == 0) {
      _selectedCategoryGlobal = val;
    } else {
      _selectedCategoryTr = val;
    }
  }

  Future<void> _loadGlobalFeeds() async {
    try {
      final feeds = await _service.fetchGlobal();
      setState(() {
        _globalFeeds = feeds;
        _isLoadingGlobal = false;
      });
    } catch (e) {
      debugPrint('Error loading global feeds: $e');
      setState(() {
        _isLoadingGlobal = false;
        _hasErrorGlobal = true;
      });
    }
  }

  Future<void> _loadTrFeeds() async {
    try {
      final feeds = await _service.fetchTurkish();
      setState(() {
        _trFeeds = feeds;
        _isLoadingTr = false;
      });
    } catch (e) {
      debugPrint('Error loading TR feeds: $e');
      setState(() {
        _isLoadingTr = false;
        _hasErrorTr = true;
      });
    }
  }

  List<SuggestedFeed> get _displayedFeeds {
    var feeds = _activeCategory == null
        ? _activeFeeds
        : _activeFeeds.where((f) => f.category == _activeCategory).toList();
    if (_searchQuery.isNotEmpty) {
      feeds = feeds
          .where(
            (f) =>
                f.name.toLowerCase().contains(_searchQuery) ||
                f.url.toLowerCase().contains(_searchQuery),
          )
          .toList();
    }
    feeds.sort((a, b) {
      if (b.popularity != a.popularity) {
        return b.popularity.compareTo(a.popularity);
      }
      return a.name.compareTo(b.name);
    });
    return feeds;
  }

  Map<String, int> get _categoryCounts {
    final counts = <String, int>{};
    for (final f in _activeFeeds) {
      counts[f.category] = (counts[f.category] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get _categoryPopularity {
    final maxPop = <String, int>{};
    for (final f in _activeFeeds) {
      if (f.popularity > (maxPop[f.category] ?? 0)) {
        maxPop[f.category] = f.popularity;
      }
    }
    return maxPop;
  }

  Future<void> _subscribeToFeed(
    BuildContext context,
    String name,
    String url,
    String category,
  ) async {
    if (_subscribingUrls.contains(url)) return;
    setState(() => _subscribingUrls.add(url));
    final l10n = AppLocalizations.of(context);
    final subscriptionProvider = context.read<SubscriptionProvider>();
    final feedProvider = context.read<FeedProvider>();
    try {
      final added = await feedProvider.addSubscriptionAndRefresh(
        url,
        name,
        category,
      );
      if (!added) {
        // Canonical duplicate — the suggested URL differs only in
        // scheme/host/trailing-slash from an existing subscription.
        showAppToast(l10n.feedAlreadyExists, type: AppToastType.error);
        return;
      }

      showAppToast(
        l10n.addedSubscription(name),
        type: AppToastType.success,
        action: AppToastAction(
          label: l10n.undo,
          onPressed: () async {
            await subscriptionProvider.removeFeed(url);
            feedProvider.refreshAll();
          },
        ),
      );
    } catch (_) {
      showAppToast(l10n.feedAddError, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _subscribingUrls.remove(url));
    }
  }

  Future<void> _unsubscribeFromFeed(
    BuildContext context,
    String name,
    String url,
    String category,
  ) async {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.removeFeed,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.removeFeedConfirm(name),
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(l10n.delete),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final subscriptionProvider = context.read<SubscriptionProvider>();
    final feedProvider = context.read<FeedProvider>();
    await subscriptionProvider.removeFeed(url);
    if (context.mounted) feedProvider.refreshAll();

    showAppToast(
      l10n.removedSubscription(name),
      type: AppToastType.success,
      action: AppToastAction(
        label: l10n.undo,
        onPressed: () async {
          await subscriptionProvider.addFeed(url, name, category);
          feedProvider.refreshAll();
        },
      ),
    );
  }

  void _openCategorySheet() {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final counts = _categoryCounts;
    final popMap = _categoryPopularity;
    final categories = counts.keys.toList()
      ..sort((a, b) => (popMap[b] ?? 0).compareTo(popMap[a] ?? 0));

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.categoriesSheetTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ExploreSheetChip(
                      label: l10n.all,
                      count: _activeFeeds.length,
                      selected: _activeCategory == null,
                      colorScheme: colorScheme,
                      onTap: () {
                        setState(() => _setActiveCategory(null));
                        Navigator.of(ctx).pop();
                      },
                    ),
                    ...categories.map(
                      (cat) => ExploreSheetChip(
                        label: cat,
                        count: counts[cat]!,
                        selected: _activeCategory == cat,
                        colorScheme: colorScheme,
                        onTap: () {
                          setState(
                            () => _setActiveCategory(
                              _activeCategory == cat ? null : cat,
                            ),
                          );
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final hasContent = !_activeIsLoading && _activeFeeds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.suggestedFeeds),
        leading: const BackButton(),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(hasContent ? 104 : 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: l10n.tabGlobal),
                  Tab(text: l10n.tabTurkish),
                ],
              ),
              if (hasContent) ...[
                Divider(
                  height: 1,
                  color: colorScheme.onSurface.withValues(alpha: 0.1),
                ),
                ExploreSearchBar(controller: _searchController),
              ],
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (hasContent)
            ExploreFilterBar(
              selectedCategory: _activeCategory,
              totalCount: _displayedFeeds.length,
              onTap: _openCategorySheet,
              colorScheme: colorScheme,
              l10n: l10n,
            ),
          Expanded(
            child: _activeIsLoading
                ? const Center(child: CircularProgressIndicator())
                : _activeHasError
                ? const ExploreErrorState()
                : Builder(
                    builder: (context) {
                      final feeds = _displayedFeeds;
                      if (feeds.isEmpty) {
                        return Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? l10n.noFeedsMatchFilter
                                : l10n.noFeedsInThisCategory,
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        itemCount: feeds.length,
                        itemBuilder: (context, index) => SuggestedFeedTile(
                          feed: feeds[index],
                          isSubscribing: _subscribingUrls.contains(
                            feeds[index].url,
                          ),
                          onSubscribe: _subscribeToFeed,
                          onUnsubscribe: _unsubscribeFromFeed,
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              l10n.suggestedFeedsWarning,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
