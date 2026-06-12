import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
import '../services/image_cache_service.dart';
import '../providers/subscription_provider.dart';

class FeedListItem extends StatefulWidget {
  final FeedItem item;

  const FeedListItem({super.key, required this.item});

  @override
  State<FeedListItem> createState() => _FeedListItemState();
}

class _FeedListItemState extends State<FeedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<double>? _snapBackAnimation;
  double _dragExtent = 0.0;
  bool _actionTriggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_snapBackAnimation != null) {
          setState(() {
            _dragExtent = _snapBackAnimation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    final prev = _actionTriggered;
    final width = MediaQuery.of(context).size.width;
    final threshold = width * 0.25;
    setState(() {
      _dragExtent += details.primaryDelta!;
    });
    if (!prev && _dragExtent.abs() > threshold) {
      _actionTriggered = true;
      HapticFeedback.mediumImpact();
      setState(() {});
    } else if (prev && _dragExtent.abs() <= threshold) {
      _actionTriggered = false;
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_controller.isAnimating) return;
    final width = MediaQuery.of(context).size.width;
    final threshold = width * 0.25;
    final velocity = details.primaryVelocity ?? 0.0;

    if (_dragExtent > 0 && (_dragExtent > threshold || velocity > 1500)) {
      context.read<FeedProvider>().toggleReadStatus(widget.item.id);
    } else if (_dragExtent < 0 &&
        (_dragExtent < -threshold || velocity < -1500)) {
      context.read<BookmarkProvider>().toggleBookmark(widget.item);
    }

    _actionTriggered = false;
    _snapBackAnimation = Tween<double>(begin: _dragExtent, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final isSwipingRight = _dragExtent > 0;

    return Selector2<FeedProvider, BookmarkProvider,
        ({bool isCached, bool isBookmarked})>(
      selector: (context, feedProvider, bookmarkProvider) => (
        isCached: feedProvider.cachedItemIds.contains(widget.item.id),
        isBookmarked:
            bookmarkProvider.bookmarkedItemIds.contains(widget.item.id),
      ),
      builder: (context, state, child) {
        final bool isBookmarked = state.isBookmarked;
        final bool isCached = state.isCached;
        final bool isRead = widget.item.isRead;
        final l10n = AppLocalizations.of(context);

        return Semantics(
          label: l10n.semanticOpenArticle(widget.item.title),
          hint: isRead ? l10n.semanticArticleRead : l10n.semanticArticleUnread,
          button: false,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10.0),
            child: Stack(
              children: [
                if (_dragExtent != 0)
                  _SwipeBackground(
                    isSwipingRight: isSwipingRight,
                    isRead: isRead,
                    isBookmarked: isBookmarked,
                    actionTriggered: _actionTriggered,
                  ),
                GestureDetector(
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: Transform.translate(
                    offset: Offset(_dragExtent, 0),
                    child: _ArticleCard(
                      item: widget.item,
                      isRead: isRead,
                      isBookmarked: isBookmarked,
                      isCached: isCached,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Core card widget
// =============================================================================

class _ArticleCard extends StatelessWidget {
  final FeedItem item;
  final bool isRead;
  final bool isBookmarked;
  final bool isCached;

  const _ArticleCard({
    required this.item,
    required this.isRead,
    required this.isBookmarked,
    required this.isCached,
  });

  bool get _hasThumbnail =>
      item.imageUrl != null && item.imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: isRead
            ? surfaceColor
            : Color.alphaBlend(
                colorScheme.primary.withValues(alpha: 0.07),
                surfaceColor,
              ),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            final feedProvider = context.read<FeedProvider>();
            final allItems = feedProvider.filteredItems;
            final index = allItems.indexWhere((i) => i.id == item.id);
            context.push(
              '/article',
              extra: {
                'items': allItems,
                'initialIndex': index >= 0 ? index : 0,
              },
            );
            feedProvider.markAsRead(item.id);
          },
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FeedItemIcon(item: item, isRead: isRead),
                const SizedBox(width: 12),
                Expanded(
                  child: _FeedItemContent(item: item, isRead: isRead),
                ),
                if (_hasThumbnail) ...[
                  const SizedBox(width: 12),
                  _FeedItemThumbnail(
                    item: item,
                    isRead: isRead,
                    isBookmarked: isBookmarked,
                    isCached: isCached,
                  ),
                ] else ...[
                  const SizedBox(width: 4),
                  _FeedItemActions(
                    item: item,
                    isBookmarked: isBookmarked,
                    isCached: isCached,
                    isRead: isRead,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Swipe background — smooth icon scale via AnimatedScale
// =============================================================================

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
          borderRadius: BorderRadius.circular(18),
        ),
        alignment:
            isSwipingRight ? Alignment.centerLeft : Alignment.centerRight,
        padding: EdgeInsets.only(
          left: isSwipingRight ? 24.0 : 0,
          right: !isSwipingRight ? 24.0 : 0,
        ),
        child: AnimatedScale(
          scale: actionTriggered ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: Icon(
            isSwipingRight
                ? (isRead ? Icons.mark_email_unread : Icons.mark_email_read)
                : (isBookmarked ? Icons.bookmark_remove : Icons.bookmark_add),
            color: isSwipingRight
                ? colorScheme.primary
                : colorScheme.secondary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Feed source icon — always category icon, left side
// =============================================================================

class _FeedItemIcon extends StatelessWidget {
  final FeedItem item;
  final bool isRead;

  const _FeedItemIcon({required this.item, required this.isRead});

  @override
  Widget build(BuildContext context) {
    final subscriptionProvider = context.watch<SubscriptionProvider>();
    final categoryIcon = subscriptionProvider.getCategoryIcon(item.category);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isRead
            ? item.iconBackgroundColor.withValues(alpha: 0.12)
            : item.iconBackgroundColor,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: Icon(
          categoryIcon,
          size: 20,
          color: isRead
              ? item.iconColor.withValues(alpha: 0.4)
              : item.iconColor,
        ),
      ),
    );
  }
}

// =============================================================================
// Thumbnail — right side, shown when imageUrl present
// =============================================================================

class _FeedItemThumbnail extends StatelessWidget {
  final FeedItem item;
  final bool isRead;
  final bool isBookmarked;
  final bool isCached;

  const _FeedItemThumbnail({
    required this.item,
    required this.isRead,
    required this.isBookmarked,
    required this.isCached,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Opacity(
            opacity: isRead ? 0.5 : 1.0,
            child: CachedNetworkImage(
              imageUrl: item.imageUrl!,
              cacheManager: ThumbnailCacheManager.instance,
              width: 72,
              height: 72,
              memCacheWidth: 150,
              maxWidthDiskCache: 150,
              maxHeightDiskCache: 150,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(
                width: 72,
                height: 72,
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_outlined,
                  size: 24,
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                ),
              ),
              placeholder: (_, _) => Container(
                width: 72,
                height: 72,
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => context.read<BookmarkProvider>().toggleBookmark(item),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                size: 14,
                color: isBookmarked
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        if (isCached)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(
                Icons.offline_pin,
                size: 12,
                color: colorScheme.secondary
                    .withValues(alpha: isRead ? 0.35 : 0.7),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Content column
// =============================================================================

class _FeedItemContent extends StatelessWidget {
  final FeedItem item;
  final bool isRead;

  const _FeedItemContent({required this.item, required this.isRead});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!isRead)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Text(
                item.siteName,
                style: TextStyle(
                  color: isRead
                      ? colorScheme.onSurface.withValues(alpha: 0.6)
                      : colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDate(item),
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          item.title.trim(),
          style: TextStyle(
            color: isRead
                ? colorScheme.onSurface.withValues(alpha: 0.65)
                : colorScheme.onSurface,
            fontSize: 15,
            fontWeight: isRead ? FontWeight.w400 : FontWeight.w700,
            height: 1.3,
            letterSpacing: -0.1,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          item.description,
          style: TextStyle(
            color: colorScheme.onSurface
                .withValues(alpha: isRead ? 0.55 : 0.65),
            fontSize: 13,
            height: 1.35,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _formatDate(FeedItem item) {
    if (item.pubDate == null) return item.timeAgo;
    final now = DateTime.now();
    final d = item.pubDate!;
    final diff = now.difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${d.month}/${d.day}';
  }
}

// =============================================================================
// Actions column — shown when no thumbnail
// =============================================================================

class _FeedItemActions extends StatelessWidget {
  final FeedItem item;
  final bool isBookmarked;
  final bool isCached;
  final bool isRead;

  const _FeedItemActions({
    required this.item,
    required this.isBookmarked,
    required this.isCached,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ActionIcon(
            onTap: () => context.read<BookmarkProvider>().toggleBookmark(item),
            icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            color: isBookmarked
                ? colorScheme.primary
                : colorScheme.onSurface
                    .withValues(alpha: isRead ? 0.25 : 0.4),
            size: 20,
            semanticLabel: isBookmarked
                ? AppLocalizations.of(context).semanticRemoveBookmark
                : AppLocalizations.of(context).semanticBookmark,
          ),
          if (isCached)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Semantics(
                label: AppLocalizations.of(context).semanticOfflineCached,
                child: Icon(
                  Icons.offline_pin,
                  color: colorScheme.secondary
                      .withValues(alpha: isRead ? 0.35 : 0.7),
                  size: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final double size;
  final String? semanticLabel;

  const _ActionIcon({
    required this.onTap,
    required this.icon,
    required this.color,
    required this.size,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(icon, color: color, size: size),
        ),
      ),
    );
  }
}
