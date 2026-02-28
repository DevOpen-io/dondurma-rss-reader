import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import '../models/feed_item.dart';
import '../providers/feed_provider.dart';
import '../providers/bookmark_provider.dart';

/// A single feed article card with swipe-to-read and swipe-to-bookmark gestures.
///
/// Uses [Selector2] to rebuild only when the bookmark or cache state of this
/// specific item changes — avoids full list rebuilds.
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

    return Selector2<
      FeedProvider,
      BookmarkProvider,
      ({bool isCached, bool isBookmarked})
    >(
      selector: (context, feedProvider, bookmarkProvider) => (
        isCached: feedProvider.cachedItemIds.contains(widget.item.id),
        isBookmarked: bookmarkProvider.bookmarkedItemIds.contains(
          widget.item.id,
        ),
      ),
      builder: (context, state, child) {
        final bool isBookmarked = state.isBookmarked;
        final bool isCached = state.isCached;

        return Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: Stack(
            children: [
              // Swipe background indicator
              if (_dragExtent != 0)
                _SwipeBackground(
                  isSwipingRight: isSwipingRight,
                  isRead: widget.item.isRead,
                  isBookmarked: isBookmarked,
                  actionTriggered: _actionTriggered,
                ),
              // Foreground card
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
                              _FeedItemIcon(item: widget.item),
                              const SizedBox(width: 16),
                              _FeedItemContent(item: widget.item),
                              const SizedBox(width: 8),
                              _FeedItemActions(
                                item: widget.item,
                                isBookmarked: isBookmarked,
                                isCached: isCached,
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

// ---------------------------------------------------------------------------
// Extracted private sub-widgets
// ---------------------------------------------------------------------------

/// The background layer shown behind the card during a horizontal swipe.
class _SwipeBackground extends StatelessWidget {
  final bool isSwipingRight;
  final bool isRead;
  final bool isBookmarked;
  final bool actionTriggered;

  const _SwipeBackground({
    required this.isSwipingRight,
    required this.isRead,
    required this.isBookmarked,
    required this.actionTriggered,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: isSwipingRight
              ? colorScheme.primary.withValues(alpha: 0.1)
              : colorScheme.secondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: isSwipingRight
            ? Alignment.centerLeft
            : Alignment.centerRight,
        padding: EdgeInsets.only(
          left: isSwipingRight ? 24.0 : 0,
          right: !isSwipingRight ? 24.0 : 0,
        ),
        child: Icon(
          isSwipingRight
              ? (isRead ? Icons.mark_email_unread : Icons.mark_email_read)
              : (isBookmarked ? Icons.bookmark_remove : Icons.bookmark_add),
          color: isSwipingRight ? colorScheme.primary : colorScheme.secondary,
          size: 28 + (actionTriggered ? 4.0 : 0.0),
        ),
      ),
    );
  }
}

/// The feed source icon / thumbnail on the left side of the card.
class _FeedItemIcon extends StatelessWidget {
  final FeedItem item;

  const _FeedItemIcon({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: item.isRead
            ? item.iconBackgroundColor.withValues(alpha: 0.1)
            : item.iconBackgroundColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: item.imageUrl != null
            ? Opacity(
                opacity: item.isRead ? 0.6 : 1.0,
                child: CachedNetworkImage(
                  imageUrl: item.imageUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 144,
                  errorWidget: (context, url, error) => Icon(
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
    );
  }
}

/// The text content column: site name, title, and description.
class _FeedItemContent extends StatelessWidget {
  final FeedItem item;

  const _FeedItemContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Site name + date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.siteName,
                  style: TextStyle(
                    color: item.isRead
                        ? colorScheme.primary.withValues(alpha: 0.6)
                        : colorScheme.primary,
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
                  ? colorScheme.onSurface.withValues(alpha: 0.5)
                  : colorScheme.onSurface,
              fontSize: 16,
              fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
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
                  ? colorScheme.onSurface.withValues(alpha: 0.4)
                  : colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The trailing bookmark button and offline indicator.
class _FeedItemActions extends StatelessWidget {
  final FeedItem item;
  final bool isBookmarked;
  final bool isCached;

  const _FeedItemActions({
    required this.item,
    required this.isBookmarked,
    required this.isCached,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          onPressed: () {
            context.read<BookmarkProvider>().toggleBookmark(item);
          },
          icon: Icon(
            isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            color: isBookmarked
                ? colorScheme.primary
                : Colors.grey.withValues(alpha: item.isRead ? 0.5 : 1.0),
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
              color: colorScheme.secondary.withValues(
                alpha: item.isRead ? 0.4 : 0.8,
              ),
              size: 16,
            ),
          ),
      ],
    );
  }
}
