import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';

/// Full-screen page that displays a curated list of suggested RSS feeds,
/// fetched from a remote JSON endpoint.
///
/// Users can search by name, filter by category (via a bottom sheet picker),
/// and subscribe with a single tap. Undo is offered via snackbar.
class ExploreFeedsPage extends StatefulWidget {
  const ExploreFeedsPage({super.key});

  @override
  State<ExploreFeedsPage> createState() => _ExploreFeedsPageState();
}

class _ExploreFeedsPageState extends State<ExploreFeedsPage> {
  List<Map<String, String>> _popularFeeds = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFeeds();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeeds() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/DevOpen-io/dondurma-rss-reader/refs/heads/main/remote_data/suggested_feeds.json',
        ),
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        setState(() {
          _popularFeeds = jsonData
              .map(
                (item) => {
                  'name': item['name'].toString(),
                  'url': item['url'].toString(),
                  'category': item['category'].toString(),
                },
              )
              .toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load feeds: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading suggested feeds: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  List<Map<String, String>> get _displayedFeeds {
    var feeds = _selectedCategory == null
        ? _popularFeeds
        : _popularFeeds
              .where((f) => f['category'] == _selectedCategory)
              .toList();
    if (_searchQuery.isNotEmpty) {
      feeds = feeds
          .where(
            (f) =>
                f['name']!.toLowerCase().contains(_searchQuery) ||
                f['url']!.toLowerCase().contains(_searchQuery),
          )
          .toList();
    }
    return feeds;
  }

  Map<String, int> get _categoryCounts {
    final counts = <String, int>{};
    for (final f in _popularFeeds) {
      counts[f['category']!] = (counts[f['category']!] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _subscribeToFeed(
    BuildContext context,
    String name,
    String url,
    String category,
  ) async {
    final l10n = AppLocalizations.of(context);
    final subscriptionProvider = context.read<SubscriptionProvider>();
    final feedProvider = context.read<FeedProvider>();
    final messenger = ScaffoldMessenger.of(context);

    await subscriptionProvider.addFeed(url, name, category);
    if (context.mounted) feedProvider.refreshAll();

    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.addedSubscription(name)),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => subscriptionProvider.removeFeed(url),
        ),
      ),
    );
  }

  void _openCategorySheet() {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final counts = _categoryCounts;
    final categories = counts.keys.toList()..sort();

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
                  'Categories',
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
                    _SheetChip(
                      label: l10n.all,
                      count: _popularFeeds.length,
                      selected: _selectedCategory == null,
                      colorScheme: colorScheme,
                      onTap: () {
                        setState(() => _selectedCategory = null);
                        Navigator.of(ctx).pop();
                      },
                    ),
                    ...categories.map(
                      (cat) => _SheetChip(
                        label: cat,
                        count: counts[cat]!,
                        selected: _selectedCategory == cat,
                        colorScheme: colorScheme,
                        onTap: () {
                          setState(
                            () => _selectedCategory =
                                _selectedCategory == cat ? null : cat,
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
    final hasContent = !_isLoading && _popularFeeds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.suggestedFeeds),
        leading: const BackButton(),
        bottom: hasContent
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Divider(
                      height: 1,
                      color: colorScheme.onSurface.withValues(alpha: 0.1),
                    ),
                    _SearchBar(controller: _searchController),
                  ],
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          if (hasContent)
            _ActiveFilterBar(
              selectedCategory: _selectedCategory,
              totalCount: _displayedFeeds.length,
              onTap: _openCategorySheet,
              colorScheme: colorScheme,
              l10n: l10n,
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _hasError
                ? const _ErrorState()
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
                        itemBuilder: (context, index) => _SuggestedFeedTile(
                          feed: feeds[index],
                          onSubscribe: _subscribeToFeed,
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

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: l10n.searchFeeds,
          hintStyle: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.45),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onPressed: () => controller.clear(),
                  )
                : const SizedBox.shrink(),
          ),
          filled: true,
          fillColor: colorScheme.onSurface.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Sticky bar showing the active category filter with a tap to open the picker.
class _ActiveFilterBar extends StatelessWidget {
  final String? selectedCategory;
  final int totalCount;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final AppLocalizations l10n;

  const _ActiveFilterBar({
    required this.selectedCategory,
    required this.totalCount,
    required this.onTap,
    required this.colorScheme,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final label = selectedCategory ?? l10n.all;
    final isFiltered = selectedCategory != null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 16,
              color: isFiltered
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                key: ValueKey(label),
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isFiltered ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isFiltered
                    ? colorScheme.primaryContainer
                    : colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$totalCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isFiltered
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Categories',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip used inside the category bottom sheet.
class _SheetChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _SheetChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.onPrimary.withValues(alpha: 0.25)
                    : colorScheme.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single suggested feed tile.
class _SuggestedFeedTile extends StatelessWidget {
  final Map<String, String> feed;
  final Future<void> Function(BuildContext, String, String, String) onSubscribe;

  const _SuggestedFeedTile({required this.feed, required this.onSubscribe});

  static String _domain(String urlStr) {
    final uri = Uri.tryParse(urlStr);
    if (uri == null) return urlStr;
    String host = uri.host;
    if (host.contains('google.com') && uri.queryParameters.containsKey('q')) {
      try {
        host = Uri.parse(uri.queryParameters['q']!).host;
      } catch (_) {}
    }
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final url = feed['url']!;
    final name = feed['name']!;
    final category = feed['category']!;
    final domain = _domain(url);

    final isSubscribed = context
        .watch<SubscriptionProvider>()
        .subscriptions
        .any((s) => s.url == url);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isSubscribed
              ? null
              : () => onSubscribe(context, name, url, category),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CachedNetworkImage(
                      imageUrl:
                          'https://www.google.com/s2/favicons?domain=$domain&sz=128',
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          _FaviconFallback(colorScheme: colorScheme),
                      errorWidget: (_, _, _) =>
                          _FaviconFallback(colorScheme: colorScheme),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              domain,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                isSubscribed
                    ? _SubscribedBadge(
                        label: l10n.subscribed,
                        colorScheme: colorScheme,
                      )
                    : _SubscribeButton(
                        label: l10n.addSource,
                        colorScheme: colorScheme,
                        onTap: () => onSubscribe(context, name, url, category),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaviconFallback extends StatelessWidget {
  final ColorScheme colorScheme;
  const _FaviconFallback({required this.colorScheme});

  @override
  Widget build(BuildContext context) => Container(
    color: colorScheme.primaryContainer,
    child: Icon(
      Icons.rss_feed_rounded,
      color: colorScheme.onPrimaryContainer,
      size: 20,
    ),
  );
}

class _SubscribeButton extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _SubscribeButton({
    required this.label,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _SubscribedBadge extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const _SubscribedBadge({required this.label, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 14, color: colorScheme.secondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.errorLoadingSuggestedFeeds,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
