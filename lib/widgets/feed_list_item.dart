import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../providers/bookmark_provider.dart';

class FeedListItem extends StatefulWidget {
  final FeedItem item;

  const FeedListItem({super.key, required this.item});

  @override
  State<FeedListItem> createState() => _FeedListItemState();
}

class _FeedListItemState extends State<FeedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragExtent = 0.0;
  bool _actionTriggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(_controller)
      ..addListener(() {
        setState(() {
          _dragExtent = _animation.value;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    setState(() {
      _dragExtent += details.primaryDelta!;
    });

    final width = MediaQuery.of(context).size.width;
    final threshold = width * 0.25;

    if (!_actionTriggered && _dragExtent.abs() > threshold) {
      _actionTriggered = true;
      HapticFeedback.mediumImpact();
    } else if (_actionTriggered && _dragExtent.abs() <= threshold) {
      _actionTriggered = false;
      HapticFeedback.selectionClick();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_controller.isAnimating) return;

    final width = MediaQuery.of(context).size.width;
    final threshold = width * 0.25;

    final velocity = details.primaryVelocity ?? 0.0;

    bool swipedRight = _dragExtent > threshold || velocity > 1500;
    bool swipedLeft = _dragExtent < -threshold || velocity < -1500;

    if (_dragExtent > 0 && swipedRight) {
      context.read<FeedProvider>().toggleReadStatus(widget.item.id);
    } else if (_dragExtent < 0 && swipedLeft) {
      context.read<BookmarkProvider>().toggleBookmark(widget.item);
    }

    _actionTriggered = false;

    _animation = Tween<double>(
      begin: _dragExtent,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isSwipingRight = _dragExtent > 0;
    final isSwipingLeft = _dragExtent < 0;

    return Selector2<FeedProvider, BookmarkProvider, bool>(
      selector: (context, provider, bookmarkProvider) =>
          provider.cachedItemIds.contains(widget.item.id) ||
          bookmarkProvider.bookmarkedItemIds.contains(widget.item.id),
      builder: (context, isCached, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: Stack(
            children: [
              // Background layer
              if (_dragExtent != 0)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSwipingRight
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1)
                          : Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: isSwipingRight
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    padding: EdgeInsets.only(
                      left: isSwipingRight ? 24.0 : 0,
                      right: isSwipingLeft ? 24.0 : 0,
                    ),
                    child: Icon(
                      isSwipingRight
                          ? (widget.item.isRead
                                ? Icons.mark_email_unread
                                : Icons.mark_email_read)
                          : (widget.item.isBookmarked
                                ? Icons.bookmark_remove
                                : Icons.bookmark_add),
                      color: isSwipingRight
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                      size: 28 + (_actionTriggered ? 4.0 : 0.0),
                    ),
                  ),
                ),
              // Foreground layer
              GestureDetector(
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: Transform.translate(
                  offset: Offset(_dragExtent, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          context.read<FeedProvider>().markAsRead(
                            widget.item.id,
                          );
                          context.push('/article', extra: widget.item);
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
                                  color: widget.item.isRead
                                      ? widget.item.iconBackgroundColor
                                            .withValues(alpha: 0.1)
                                      : widget.item.iconBackgroundColor,
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.1),
                                    width: 0.5,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12.0),
                                  child: widget.item.imageUrl != null
                                      ? Opacity(
                                          opacity: widget.item.isRead
                                              ? 0.6
                                              : 1.0,
                                          child: CachedNetworkImage(
                                            imageUrl: widget.item.imageUrl!,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 144,
                                            errorWidget:
                                                (context, url, error) => Icon(
                                                  widget.item.siteIcon,
                                                  color: widget.item.isRead
                                                      ? widget.item.iconColor
                                                            .withValues(
                                                              alpha: 0.5,
                                                            )
                                                      : widget.item.iconColor,
                                                  size: 24,
                                                ),
                                          ),
                                        )
                                      : Center(
                                          child: Icon(
                                            widget.item.siteIcon,
                                            color: widget.item.isRead
                                                ? widget.item.iconColor
                                                      .withValues(alpha: 0.5)
                                                : widget.item.iconColor,
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.item.siteName,
                                            style: TextStyle(
                                              color: widget.item.isRead
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0.6)
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          widget.item.pubDate != null
                                              ? "${widget.item.pubDate!.month}/${widget.item.pubDate!.day}"
                                              : widget.item.timeAgo,
                                          style: TextStyle(
                                            color: widget.item.isRead
                                                ? Colors.grey.withValues(
                                                    alpha: 0.5,
                                                  )
                                                : Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Title
                                    Text(
                                      widget.item.title.trim(),
                                      style: TextStyle(
                                        color: widget.item.isRead
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.5)
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        fontSize: 16,
                                        fontWeight: widget.item.isRead
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
                                      widget.item.description,
                                      style: TextStyle(
                                        color: widget.item.isRead
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.4)
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.7),
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
                                      context
                                          .read<BookmarkProvider>()
                                          .toggleBookmark(widget.item);
                                    },
                                    icon: Icon(
                                      widget.item.isBookmarked
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
                                      color: widget.item.isBookmarked
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.grey.withValues(
                                              alpha: widget.item.isRead
                                                  ? 0.5
                                                  : 1.0,
                                            ),
                                      size: 22,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    alignment: Alignment.topRight,
                                  ),
                                  if (isCached)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 12.0,
                                        right: 2.0,
                                      ),
                                      child: Icon(
                                        Icons.offline_pin,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary
                                            .withValues(
                                              alpha: widget.item.isRead
                                                  ? 0.4
                                                  : 0.8,
                                            ),
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
