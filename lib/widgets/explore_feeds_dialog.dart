import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import '../providers/feed_provider.dart';

class ExploreFeedsDialog extends StatefulWidget {
  const ExploreFeedsDialog({super.key});

  @override
  State<ExploreFeedsDialog> createState() => _ExploreFeedsDialogState();
}

class _ExploreFeedsDialogState extends State<ExploreFeedsDialog> {
  List<Map<String, String>> _popularFeeds = [];
  bool _isLoading = true;

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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Suggested Feeds',
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
            Flexible(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _popularFeeds.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (context, index) {
                        final feed = _popularFeeds[index];
                        final String feedUrlStr = feed['url']!;
                        final provider = context.watch<FeedProvider>();
                        final bool isSubscribed = provider.subscriptions.any(
                          (s) => s.url == feedUrlStr,
                        );
                        final Uri feedUri = Uri.parse(feedUrlStr);
                        String domain = feedUri.host;

                        // If it's a google search redirect, extract the actual URL from the 'q' parameter
                        if (domain.contains('google.com') &&
                            feedUri.queryParameters.containsKey('q')) {
                          try {
                            final actualUrl = feedUri.queryParameters['q']!;
                            domain = Uri.parse(actualUrl).host;
                          } catch (e) {
                            // fallback to google.com if parsing fails
                          }
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.rss_feed,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    size: 20,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.rss_feed,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    feed['category']!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Icon(
                            isSubscribed
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: isSubscribed
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.primary,
                          ),
                          onTap: isSubscribed
                              ? null
                              : () {
                                  _showConfirmationDialog(
                                    context,
                                    feed['name']!,
                                    feed['url']!,
                                    feed['category']!,
                                  );
                                },
                        );
                      },
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
    showDialog(
      context: parentContext,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Add Subscription'),
          content: Text('Do you want to add "$name" to your feed list?'),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                parentContext.read<FeedProvider>().addFeed(url, name, category);
                context.pop(); // Close confirm dialog
                parentContext.pop(); // Close explore dialog

                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text('Added $name to your subscriptions!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Add Source'),
            ),
          ],
        );
      },
    );
  }
}
