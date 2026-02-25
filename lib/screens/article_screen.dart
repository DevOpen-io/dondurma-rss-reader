import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import '../models/feed_item.dart';

class ArticleScreen extends StatelessWidget {
  final FeedItem item;

  const ArticleScreen({super.key, required this.item});

  Future<void> _launchUrl(BuildContext context, String url) async {
    try {
      String cleanUrl = url.trim();
      if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
        cleanUrl = 'https://$cleanUrl';
      }

      final uri = Uri.tryParse(cleanUrl);
      if (uri == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invalid URL format')));
        }
        return;
      }

      final success = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!success && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $cleanUrl')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening link: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we have an image URL, we can display it at the top
    String dateStr = item.pubDate != null
        ? DateFormat('MMM d, yyyy  h:mm a').format(item.pubDate!.toLocal())
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(item.siteName, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () {
              if (item.link.isNotEmpty) {
                _launchUrl(context, item.link);
              }
            },
            tooltip: 'Open in Browser',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // If an image was extracted, display it here as a bleeding hero cover
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
              Image.network(
                item.imageUrl!,
                width: double.infinity,
                height: 250,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink(); // Hide if image fails to load
                },
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.category.toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.25,
                    ),
                  ),
                  if (dateStr.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Render rich HTML content directly
                  Html(
                    data: item.content ?? item.description,
                    style: {
                      "body": Style(
                        fontSize: FontSize(18.0),
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.85),
                        lineHeight: LineHeight(1.8),
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                      ),
                      "a": Style(
                        color: Theme.of(context).colorScheme.primary,
                        textDecoration: TextDecoration.none,
                      ),
                      "img": Style(
                        width: Width(MediaQuery.of(context).size.width - 40),
                        margin: Margins.only(top: 24, bottom: 24),
                      ),
                      "figure": Style(
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                      ),
                      "p": Style(margin: Margins.only(bottom: 16)),
                      "h1": Style(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      "h2": Style(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      "h3": Style(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      "h4": Style(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      "h5": Style(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      "h6": Style(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    },
                    onLinkTap: (url, attributes, element) {
                      if (url != null && url.isNotEmpty) {
                        _launchUrl(context, url);
                      }
                    },
                  ),

                  const SizedBox(height: 48),

                  // Read on Original Webpage button prominently at the end
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (item.link.isNotEmpty) {
                          _launchUrl(context, item.link);
                        }
                      },
                      icon: const Icon(Icons.public),
                      label: const Text('Read on Original Webpage'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
