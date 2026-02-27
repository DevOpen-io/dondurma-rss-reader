import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import '../models/feed_item.dart';
import '../widgets/in_app_browser.dart';

class ArticleScreen extends StatelessWidget {
  final FeedItem item;

  const ArticleScreen({super.key, required this.item});

  /// Opens [url] in the in-app browser. Falls back to the external browser if
  /// the URL is invalid.
  void _openUrl(BuildContext context, String url, {String? title}) {
    String cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid URL format')));
      return;
    }

    openInAppBrowser(context, cleanUrl, title: title);
  }

  @override
  Widget build(BuildContext context) {
    final String dateStr = item.pubDate != null
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
                _openUrl(context, item.link, title: item.title);
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
            // Hero cover image
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
              CachedNetworkImage(
                imageUrl: item.imageUrl!,
                width: double.infinity,
                height: 250,
                fit: BoxFit.cover,
                memCacheWidth: 800,
                errorWidget: (context, url, error) {
                  return const SizedBox.shrink();
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

                  // Rich HTML content
                  Html(
                    data: item.content ?? item.description,
                    extensions: [
                      TagExtension(
                        tagsToExtend: {"img"},
                        builder: (extensionContext) {
                          final String? src =
                              extensionContext.attributes['src'];
                          if (src == null) return const SizedBox.shrink();
                          return CachedNetworkImage(
                            imageUrl: src,
                            memCacheWidth: 800,
                            fit: BoxFit.contain,
                            errorWidget: (context, url, error) =>
                                const SizedBox.shrink(),
                          );
                        },
                      ),
                    ],
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
                        _openUrl(context, url);
                      }
                    },
                  ),

                  const SizedBox(height: 48),

                  // "Read on Original Webpage" button — opens in-app browser
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (item.link.isNotEmpty) {
                          _openUrl(context, item.link, title: item.title);
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
