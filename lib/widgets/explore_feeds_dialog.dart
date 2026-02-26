import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import '../providers/feed_provider.dart';

class ExploreFeedsDialog extends StatelessWidget {
  const ExploreFeedsDialog({super.key});

  static const List<Map<String, String>> _popularFeeds = [
    // Technology
    {
      'name': 'TechCrunch',
      'url': 'https://techcrunch.com/feed/',
      'category': 'Technology',
    },
    {
      'name': 'The Verge',
      'url': 'https://www.theverge.com/rss/index.xml',
      'category': 'Technology',
    },
    {
      'name': 'Wired',
      'url': 'https://www.wired.com/feed/rss',
      'category': 'Technology',
    },
    {
      'name': 'Engadget',
      'url': 'https://www.engadget.com/rss.xml',
      'category': 'Technology',
    },
    // News
    {
      'name': 'BBC News',
      'url': 'http://feeds.bbci.co.uk/news/world/rss.xml',
      'category': 'World News',
    },
    {
      'name': 'NYT World News',
      'url': 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
      'category': 'World News',
    },
    // Programming / Dev
    {
      'name': 'Hacker News',
      'url': 'https://hnrss.org/frontpage',
      'category': 'Programming',
    },
    {
      'name': 'Flutter Blog',
      'url': 'https://medium.com/feed/flutter',
      'category': 'Programming',
    },
    {
      'name': 'Dart Blog',
      'url': 'https://medium.com/feed/dartlang',
      'category': 'Programming',
    },
    // Design
    {
      'name': 'Smashing Magazine',
      'url': 'https://www.smashingmagazine.com/feed/',
      'category': 'Design',
    },
    {
      'name': 'CSS-Tricks',
      'url': 'https://css-tricks.com/feed/',
      'category': 'Design',
    },
    // Gaming
    {
      'name': 'Polygon',
      'url': 'https://www.polygon.com/rss/index.xml',
      'category': 'Gaming',
    },
    {
      'name': 'IGN',
      'url': 'https://feeds.ign.com/ign/news',
      'category': 'Gaming',
    },
    {'name': 'Kotaku', 'url': 'https://kotaku.com/rss', 'category': 'Gaming'},
    // Sports
    {
      'name': 'ESPN Top News',
      'url': 'https://www.espn.com/espn/rss/news',
      'category': 'Sports',
    },
    {
      'name': 'Bleacher Report',
      'url': 'https://bleacherreport.com/articles/feed',
      'category': 'Sports',
    },
    // Science
    {
      'name': 'NASA Breaking News',
      'url': 'https://www.nasa.gov/rss/dyn/breaking_news.rss',
      'category': 'Science',
    },
    {
      'name': 'Science Daily',
      'url': 'https://www.sciencedaily.com/rss/all.xml',
      'category': 'Science',
    },
    // Anime & Manga
    {
      'name': 'Anime News Network',
      'url': 'https://www.animenewsnetwork.com/news/rss.xml',
      'category': 'Anime',
    },
    {
      'name': 'Crunchyroll News',
      'url': 'https://cr-news-api-service.prd.crunchyrollsvc.com/v1/en-US/rss',
      'category': 'Anime',
    },
    {
      'name': 'MyAnimeList News',
      'url': 'https://myanimelist.net/rss/news.xml',
      'category': 'Anime',
    },
  ];

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
                    onPressed: () => Navigator.of(context).pop(),
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
              child: ListView.separated(
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
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    leading: ClipOval(
                      child: Container(
                        width: 40,
                        height: 40,
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: CachedNetworkImage(
                          imageUrl:
                              'https://www.google.com/s2/favicons?domain=${Uri.parse(feed['url']!).host}&sz=128',
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Icon(
                            Icons.rss_feed,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                          errorWidget: (context, url, error) => Icon(
                            Icons.rss_feed,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            size: 20,
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
                      Icons.add_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onTap: () {
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                parentContext.read<FeedProvider>().addFeed(url, name, category);
                Navigator.of(context).pop(); // Close confirm dialog
                Navigator.of(parentContext).pop(); // Close explore dialog

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
