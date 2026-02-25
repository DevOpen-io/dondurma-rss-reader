import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../screens/article_screen.dart';

class FeedListItem extends StatelessWidget {
  final FeedItem item;

  const FeedListItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    // We use context.watch instead of context.select here because Dart sets are not
    // deeply equatable by default, so context.select won't trigger a rebuild when
    // the elements within `cachedItemIds` change (e.g. via .clear()).
    final provider = context.watch<FeedProvider>();
    final isCached =
        provider.cachedItemIds.contains(item.id) ||
        provider.bookmarkedItems.any((b) => b.id == item.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.read<FeedProvider>().markAsRead(item.id);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ArticleScreen(item: item)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Container
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.isRead
                      ? item.iconBackgroundColor.withValues(alpha: 0.1)
                      : item.iconBackgroundColor,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: item.imageUrl != null
                      ? Opacity(
                          opacity: item.isRead ? 0.6 : 1.0,
                          child: Image.network(
                            item.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              item.siteIcon,
                              color: item.isRead
                                  ? item.iconColor.withValues(alpha: 0.5)
                                  : item.iconColor,
                              size: 24,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            item.siteIcon,
                            color: item.isRead
                                ? item.iconColor.withValues(alpha: 0.5)
                                : item.iconColor,
                            size: 24,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // Content Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row with Site Name and Time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.siteName,
                            style: TextStyle(
                              color: item.isRead
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withValues(alpha: 0.6)
                                  : Theme.of(context).colorScheme.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          item.pubDate != null
                              ? "${item.pubDate!.month}/${item.pubDate!.day}"
                              : item.timeAgo,
                          style: TextStyle(
                            color: item.isRead
                                ? Colors.grey.withValues(alpha: 0.5)
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Title
                    Text(
                      item.title.trim(),
                      style: TextStyle(
                        color: item.isRead
                            ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5)
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: item.isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Description
                    Text(
                      item.description,
                      style: TextStyle(
                        color: item.isRead
                            ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.4)
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 14,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Actions Column
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () {
                      context.read<FeedProvider>().toggleBookmark(item.id);
                    },
                    icon: Icon(
                      item.isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      color: item.isBookmarked
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withValues(
                              alpha: item.isRead ? 0.5 : 1.0,
                            ),
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    alignment: Alignment.topRight,
                  ),
                  if (isCached)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0, right: 2.0),
                      child: Icon(
                        Icons.offline_pin,
                        color: Theme.of(context).colorScheme.secondary
                            .withValues(alpha: item.isRead ? 0.4 : 0.8),
                        size: 16,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
