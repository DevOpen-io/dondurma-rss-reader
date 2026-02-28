import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';

/// Dialog that displays a curated list of suggested RSS feeds, fetched from
/// a remote JSON endpoint.
///
/// Users can filter by category and subscribe to feeds with a single tap.
class ExploreFeedsDialog extends StatefulWidget {
  const ExploreFeedsDialog({super.key});

  @override
  State<ExploreFeedsDialog> createState() => _ExploreFeedsDialogState();
}

class _ExploreFeedsDialogState extends State<ExploreFeedsDialog> {
  List<Map<String, String>> _popularFeeds = [];
  bool _isLoading = true;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  Future<void> _loadFeeds() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://gitlab.com/alhaKK/ice_cream_rss_reader/-/raw/main/remote_data/suggested_feeds.json?ref_type=heads',
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.suggestedFeeds,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
            // Category filter chips
            if (!_isLoading && _popularFeeds.isNotEmpty) ...[
              _CategoryChipBar(
                feeds: _popularFeeds,
                selectedCategory: _selectedCategory,
                onCategorySelected: (cat) {
                  setState(() => _selectedCategory = cat);
                },
              ),
              Divider(
                height: 1,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ],
            // Feed list
            Flexible(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Builder(
                      builder: (context) {
                        final displayedFeeds = _selectedCategory == null
                            ? _popularFeeds
                            : _popularFeeds
                                  .where(
                                    (f) => f['category'] == _selectedCategory,
                                  )
                                  .toList();

                        if (displayedFeeds.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Center(
                              child: Text(l10n.noFeedsInThisCategory),
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          itemCount: displayedFeeds.length,
                          itemBuilder: (context, index) {
                            return _SuggestedFeedTile(
                              feed: displayedFeeds[index],
                              onSubscribe: _showConfirmationDialog,
                            );
                          },
                        );
                      },
                    ),
            ),
            // Disclaimer
            Padding(
              padding: const EdgeInsets.only(
                bottom: 16.0,
                left: 16.0,
                right: 16.0,
                top: 4.0,
              ),
              child: Text(
                l10n.suggestedFeedsWarning,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmationDialog(
    BuildContext parentContext,
    String name,
    String url,
    String category,
  ) {
    final l10n = AppLocalizations.of(parentContext);
    showDialog(
      context: parentContext,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(l10n.addSubscription),
          content: Text(l10n.addSubscriptionConfirm(name)),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                final scaffoldMessenger = ScaffoldMessenger.of(parentContext);
                parentContext
                    .read<SubscriptionProvider>()
                    .addFeed(url, name, category)
                    .then((_) {
                      if (parentContext.mounted) {
                        parentContext.read<FeedProvider>().refreshAll();
                      }
                    });
                context.pop(); // Close confirm dialog
                parentContext.pop(); // Close explore dialog

                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.addedSubscription(name)),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text(l10n.addSource),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Extracted sub-widgets
// ---------------------------------------------------------------------------

/// Horizontal scrollable row of category filter chips.
class _CategoryChipBar extends StatelessWidget {
  final List<Map<String, String>> feeds;
  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;

  const _CategoryChipBar({
    required this.feeds,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final categories = feeds.map((f) => f['category']!).toSet().toList()
      ..sort();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text(l10n.all),
                labelStyle: TextStyle(
                  color: selectedCategory == null
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                selected: selectedCategory == null,
                backgroundColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                selectedColor: colorScheme.primary,
                checkmarkColor: colorScheme.onPrimary,
                showCheckmark: selectedCategory == null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide.none,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                onSelected: (_) => onCategorySelected(null),
              ),
            ),
            ...categories.map((category) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(category),
                  labelStyle: TextStyle(
                    color: selectedCategory == category
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  selected: selectedCategory == category,
                  backgroundColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  selectedColor: colorScheme.primary,
                  checkmarkColor: colorScheme.onPrimary,
                  showCheckmark: selectedCategory == category,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide.none,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  onSelected: (selected) {
                    onCategorySelected(selected ? category : null);
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// A single suggested feed tile with favicon, name, category badge, and
/// subscribe action.
class _SuggestedFeedTile extends StatelessWidget {
  final Map<String, String> feed;
  final void Function(BuildContext, String, String, String) onSubscribe;

  const _SuggestedFeedTile({required this.feed, required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final feedUrlStr = feed['url']!;
    final subscriptionProvider = context.watch<SubscriptionProvider>();
    final bool isSubscribed = subscriptionProvider.subscriptions.any(
      (s) => s.url == feedUrlStr,
    );
    final Uri feedUri = Uri.parse(feedUrlStr);
    String domain = feedUri.host;

    // Extract actual domain from Google redirect URLs
    if (domain.contains('google.com') &&
        feedUri.queryParameters.containsKey('q')) {
      try {
        final actualUrl = feedUri.queryParameters['q']!;
        domain = Uri.parse(actualUrl).host;
      } catch (_) {
        // Fallback to google.com if parsing fails
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: colorScheme.surfaceContainerHighest,
            width: 1,
          ),
        ),
        tileColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        splashColor: colorScheme.primary.withValues(alpha: 0.1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: ClipOval(
          child: Container(
            width: 40,
            height: 40,
            color: Colors.transparent,
            child: CachedNetworkImage(
              imageUrl:
                  'https://www.google.com/s2/favicons?domain=$domain&sz=128',
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: colorScheme.primaryContainer,
                child: Icon(
                  Icons.rss_feed,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: colorScheme.primaryContainer,
                child: Icon(
                  Icons.rss_feed,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          feed['name']!,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  feed['category']!,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: Icon(
          isSubscribed ? Icons.check_circle : Icons.add_circle_outline,
          color: isSubscribed ? colorScheme.secondary : colorScheme.primary,
        ),
        onTap: isSubscribed
            ? null
            : () {
                onSubscribe(
                  context,
                  feed['name']!,
                  feed['url']!,
                  feed['category']!,
                );
              },
      ),
    );
  }
}
