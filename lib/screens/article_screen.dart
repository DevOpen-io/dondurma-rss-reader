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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.category.toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.3,
              ),
            ),
            if (dateStr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                dateStr,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),

            // If an image was extracted, display it here prominently as cover
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink(); // Hide if image fails to load
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Render rich HTML content directly
            Html(
              data: item.content ?? item.description,
              style: {
                "body": Style(
                  fontSize: FontSize(16.0),
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.8),
                  lineHeight: LineHeight(1.6),
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                ),
                "a": Style(
                  color: Theme.of(context).colorScheme.primary,
                  textDecoration: TextDecoration.none,
                ),
                "img": Style(
                  width: Width(MediaQuery.of(context).size.width - 32),
                  margin: Margins.only(top: 16, bottom: 16),
                ),
                "figure": Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                ),
                "p": Style(margin: Margins.only(bottom: 16)),
                "h1": Style(color: Theme.of(context).colorScheme.onSurface),
                "h2": Style(color: Theme.of(context).colorScheme.onSurface),
                "h3": Style(color: Theme.of(context).colorScheme.onSurface),
                "h4": Style(color: Theme.of(context).colorScheme.onSurface),
                "h5": Style(color: Theme.of(context).colorScheme.onSurface),
                "h6": Style(color: Theme.of(context).colorScheme.onSurface),
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
                  foregroundColor: Colors.white,
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
    );
  }
}
