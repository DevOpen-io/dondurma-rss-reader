import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
import '../services/article_status.dart';
import '../services/image_cache_service.dart';
import '../utils/app_toast.dart';
import '../utils/motion.dart';
import '../utils/offline_status_labels.dart';
import '../utils/time_format.dart';

const int _articleNavigationWindowRadius = 25;

/// Cuts [text] to at most [maxChars] characters, ending with an ellipsis.
/// Keeps both the site name and the category visible in the meta row: without
/// per-segment limits a long site name pushes the category off screen.
String truncateLabel(String text, int maxChars) {
  // characters.count is grapheme-safe — substring could split an emoji or
  // combining sequence into a broken '�' at the cut boundary.
  if (text.characters.length <= maxChars) return text;
  return '${text.characters.take(maxChars - 1)}…';
}

/// Computes the article-screen slice around [item] inside [allItems].
///
/// When [item] is not part of [allItems] (e.g. a bookmark that is filtered
/// out of the feed list), the window falls back to just that item — opening
/// index 0 of an unrelated list would show the wrong article.
({List<FeedItem> items, int initialIndex}) articleNavigationWindow(
  List<FeedItem> allItems,
  FeedItem item,
) {
  final index = allItems.indexWhere(
    (i) => i.id == item.id && i.feedUrl == item.feedUrl,
  );
  if (index < 0) return (items: [item], initialIndex: 0);
  final start = (index - _articleNavigationWindowRadius).clamp(
    0,
    allItems.length,
  );
  final end = (index + _articleNavigationWindowRadius + 1).clamp(
    0,
    allItems.length,
  );
  return (items: allItems.sublist(start, end), initialIndex: index - start);
}

/// Bookmarking is immediate; unbookmarking asks for the same short explicit
/// confirmation no matter which path (swipe, semantics action, visible
/// control) triggered it. Cancelling leaves every record untouched.
Future<void> confirmBookmarkToggle(BuildContext context, FeedItem item) async {
  final bookmarks = context.read<BookmarkProvider>();
  if (!bookmarks.isBookmarked(item.id, feedUrl: item.feedUrl)) {
    bookmarks.toggleBookmark(item);
    return;
  }
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.removeBookmarkTitle),
      content: Text(l10n.removeBookmarkConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.remove),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  // The record may have been removed while the dialog was open; never apply
  // the action to a stale or different record.
  final provider = context.read<BookmarkProvider>();
  if (!provider.isBookmarked(item.id, feedUrl: item.feedUrl)) return;
  final ok = await provider.removeBookmark(item);
  if (!ok) {
    showAppToast(l10n.bookmarkRemoveFailed, type: AppToastType.error);
  }
}

class FeedListItem extends StatefulWidget {
  final FeedItem item;

  /// The collection this item is navigated within (e.g. the bookmarks list).
  /// Defaults to the feed's [FeedProvider.filteredItems].
  final List<FeedItem>? navigationItems;

  /// Flat list row split by a hairline instead of a rounded card
  /// (Settings › Article list).
  final bool flat;

  /// A long press on the row (bookmark tags, #71); [longPressHint] names it
  /// for screen readers.
  final VoidCallback? onLongPress;
  final String? longPressHint;

  /// Extra line under the text, inside the row (a bookmark's tags).
  final Widget? footer;

  const FeedListItem({
    super.key,
    required this.item,
    this.navigationItems,
    this.flat = false,
    this.onLongPress,
    this.longPressHint,
    this.footer,
  });

  @override
  State<FeedListItem> createState() => _FeedListItemState();
}

class _FeedListItemState extends State<FeedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<double>? _snapBackAnimation;

  /// Horizontal swipe offset. Drag frames update only the translation and
  /// the swipe background — the card itself is built once per state change.
  final _drag = ValueNotifier<double>(0);
  bool _actionTriggered = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 250),
        )..addListener(() {
          if (_snapBackAnimation != null) {
            _drag.value = _snapBackAnimation!.value;
          }
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_controller.isAnimating) return;
    final prev = _actionTriggered;
    final width = context.size?.width ?? MediaQuery.sizeOf(context).width;
    final threshold = width * 0.25;
    final extent = _drag.value + details.primaryDelta!;
    if (!prev && extent.abs() > threshold) {
      _actionTriggered = true;
      HapticFeedback.mediumImpact();
    } else if (prev && extent.abs() <= threshold) {
      _actionTriggered = false;
      HapticFeedback.selectionClick();
    }
    _drag.value = extent;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_controller.isAnimating) return;
    final width = context.size?.width ?? MediaQuery.sizeOf(context).width;
    final threshold = width * 0.25;
    final velocity = details.primaryVelocity ?? 0.0;
    final extent = _drag.value;

    if (extent > 0 && (extent > threshold || velocity > 1500)) {
      unawaited(context.read<FeedProvider>().toggleReadStatus(widget.item));
    } else if (extent < 0 && (extent < -threshold || velocity < -1500)) {
      unawaited(confirmBookmarkToggle(context, widget.item));
    }

    _actionTriggered = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _drag.value = 0;
      return;
    }
    _snapBackAnimation = Tween<double>(
      begin: extent,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Selector2<
      FeedProvider,
      BookmarkProvider,
      ({
        bool isBookmarked,
        bool unmetered,
        ArticleStatus? status,
        bool statusLoaded,
      })
    >(
      selector: (context, feedProvider, bookmarkProvider) => (
        isBookmarked: bookmarkProvider.isBookmarked(
          widget.item.id,
          feedUrl: widget.item.feedUrl,
        ),
        unmetered: feedProvider.unmetered,
        status: feedProvider.articleStatus(widget.item),
        statusLoaded: feedProvider.articleStatusesLoaded,
      ),
      builder: (context, state, child) {
        final bool isBookmarked = state.isBookmarked;
        final ArticleStatus? status = state.status;
        final bool isRead = widget.item.isRead;
        final l10n = AppLocalizations.of(context);
        final String? scopeLabel = _statusLabel(
          l10n,
          status,
          isBookmarked,
          state.statusLoaded,
        );
        final String? waitLabel = _waitLabel(l10n, status, state.unmetered);
        final String statusSemantics = [
          scopeLabel,
          waitLabel,
        ].whereType<String>().join('. ');

        return Semantics(
          label: statusSemantics.isEmpty
              ? l10n.semanticOpenArticle(widget.item.title)
              : '${l10n.semanticOpenArticle(widget.item.title)}. $statusSemantics',
          hint: isRead ? l10n.semanticArticleRead : l10n.semanticArticleUnread,
          button: false,
          // Swipe gestures are invisible to screen readers; expose both swipe
          // actions as custom semantics actions so TalkBack users can reach
          // them from the card itself.
          customSemanticsActions: {
            CustomSemanticsAction(
              label: isRead
                  ? l10n.semanticMarkAsUnread
                  : l10n.semanticMarkAsRead,
            ): () => unawaited(
              context.read<FeedProvider>().toggleReadStatus(widget.item),
            ),
            CustomSemanticsAction(
              label: isBookmarked
                  ? l10n.semanticRemoveBookmark
                  : l10n.semanticBookmark,
            ): () =>
                unawaited(confirmBookmarkToggle(context, widget.item)),
          },
          child: Container(
            margin: EdgeInsets.only(bottom: widget.flat ? 0 : 10.0),
            child: ValueListenableBuilder<double>(
              valueListenable: _drag,
              child: _ArticleCard(
                item: widget.item,
                isRead: isRead,
                isBookmarked: isBookmarked,
                scopeLabel: scopeLabel,
                waitLabel: waitLabel,
                navigationItems: widget.navigationItems,
                flat: widget.flat,
                onLongPress: widget.onLongPress,
                longPressHint: widget.longPressHint,
                footer: widget.footer,
              ),
              builder: (context, extent, card) => Stack(
                children: [
                  if (extent != 0)
                    _SwipeBackground(
                      isSwipingRight: extent > 0,
                      isRead: isRead,
                      isBookmarked: isBookmarked,
                      actionTriggered: _actionTriggered,
                      flat: widget.flat,
                    ),
                  GestureDetector(
                    onHorizontalDragUpdate: _onHorizontalDragUpdate,
                    onHorizontalDragEnd: _onHorizontalDragEnd,
                    child: Transform.translate(
                      offset: Offset(extent, 0),
                      child: card,
                    ),
                  ),
                ],
              ),
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
  final String? scopeLabel;
  final String? waitLabel;
  final List<FeedItem>? navigationItems;
  final bool flat;
  final VoidCallback? onLongPress;
  final String? longPressHint;
  final Widget? footer;

  const _ArticleCard({
    required this.item,
    required this.isRead,
    required this.isBookmarked,
    required this.scopeLabel,
    required this.waitLabel,
    required this.flat,
    this.navigationItems,
    this.onLongPress,
    this.longPressHint,
    this.footer,
  });

  bool get _hasThumbnail => item.imageUrl != null && item.imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(flat ? 0 : 18);

    final row = Material(
      color: flat ? Colors.transparent : colorScheme.surfaceContainerLow,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onLongPress: onLongPress,
        onTap: () {
          final feedProvider = context.read<FeedProvider>();
          final window = articleNavigationWindow(
            navigationItems ?? feedProvider.filteredItems,
            item,
          );
          context.push(
            '/article',
            extra: {'items': window.items, 'initialIndex': window.initialIndex},
          );
          Future<void>.delayed(const Duration(milliseconds: 400), () {
            if (context.mounted) unawaited(feedProvider.markAsRead(item));
          });
        },
        child: Padding(
          padding: flat
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
              : const EdgeInsets.all(14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeedItemContent(
                      item: item,
                      isRead: isRead,
                      scopeLabel: scopeLabel,
                      waitLabel: waitLabel,
                    ),
                    if (footer case final footer?) ...[
                      const SizedBox(height: 6),
                      footer,
                    ],
                  ],
                ),
              ),
              if (_hasThumbnail) ...[
                const SizedBox(width: 12),
                _FeedItemThumbnail(
                  item: item,
                  isRead: isRead,
                  isBookmarked: isBookmarked,
                ),
              ] else ...[
                const SizedBox(width: 4),
                _FeedItemActions(
                  item: item,
                  isBookmarked: isBookmarked,
                  isRead: isRead,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final described = longPressHint == null
        ? row
        : Semantics(onLongPressHint: longPressHint, child: row);
    if (!flat) return described;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        described,
        Divider(
          height: 1,
          thickness: 0.5,
          indent: 16,
          endIndent: 16,
          color: colorScheme.outlineVariant,
        ),
      ],
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
  final bool flat;

  const _SwipeBackground({
    required this.isSwipingRight,
    required this.isRead,
    required this.isBookmarked,
    required this.actionTriggered,
    required this.flat,
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
          borderRadius: BorderRadius.circular(flat ? 0 : 18),
        ),
        alignment: isSwipingRight
            ? Alignment.centerLeft
            : Alignment.centerRight,
        padding: EdgeInsets.only(
          left: isSwipingRight ? 24.0 : 0,
          right: !isSwipingRight ? 24.0 : 0,
        ),
        child: AnimatedScale(
          scale: actionTriggered ? 1.2 : 1.0,
          duration: motionDuration(context, const Duration(milliseconds: 150)),
          curve: Curves.easeOutBack,
          child: Icon(
            isSwipingRight
                ? (isRead ? Icons.mark_email_unread : Icons.mark_email_read)
                : (isBookmarked ? Icons.bookmark_remove : Icons.bookmark_add),
            color: isSwipingRight ? colorScheme.primary : colorScheme.secondary,
            size: 28,
          ),
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

  const _FeedItemThumbnail({
    required this.item,
    required this.isRead,
    required this.isBookmarked,
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
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ),
            ),
          ),
        ),
        // Offsets compensate the 12px hit-area padding so the 24px chip stays
        // visually at bottom/right 4 while the tap target grows to 48x48.
        Positioned(
          bottom: -8,
          right: -8,
          child: Semantics(
            label: isBookmarked
                ? AppLocalizations.of(context).semanticRemoveBookmark
                : AppLocalizations.of(context).semanticBookmark,
            button: true,
            child: GestureDetector(
              onTap: () => unawaited(confirmBookmarkToggle(context, item)),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(12),
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
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Status labels (#41)
// =============================================================================

/// Short scope label for a row. A bookmarked item whose status map has
/// settled with no durable record reads "could not save", never "ready";
/// while the map is still loading the row shows nothing rather than
/// flashing a false failure (#41 honesty).
String? _statusLabel(
  AppLocalizations l10n,
  ArticleStatus? status,
  bool isBookmarked,
  bool statusLoaded,
) {
  if (status == null) {
    return isBookmarked && statusLoaded ? l10n.articleStatusCouldNotSave : null;
  }
  return offlineScopeLabel(l10n, status, noneLabel: null);
}

/// Optional second reason line — why preparation is still incomplete.
String? _waitLabel(
  AppLocalizations l10n,
  ArticleStatus? status,
  bool unmetered,
) {
  if (status == null) return null;
  final wait = status.waitFor(
    unmeteredNow: unmetered,
    now: DateTime.now().toUtc(),
  );
  return offlineWaitLabel(l10n, status, wait);
}

// =============================================================================
// Content column
// =============================================================================

class _FeedItemContent extends StatelessWidget {
  final FeedItem item;
  final bool isRead;
  final String? scopeLabel;
  final String? waitLabel;

  const _FeedItemContent({
    required this.item,
    required this.isRead,
    required this.scopeLabel,
    required this.waitLabel,
  });

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Two separately-ellipsized segments: a single Text.rich
                  // could clip the category away entirely ('Site… · …').
                  // Below ~170 logical px of meta width the category chip
                  // hides outright — a lone '…' beside the site name is
                  // worse than showing nothing.
                  final hideCategory = constraints.maxWidth < 170;
                  return Row(
                    children: [
                      Flexible(
                        child: Text(
                          truncateLabel(item.siteName, 20),
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!hideCategory && item.category != 'Uncategorized')
                        Flexible(
                          child: Text(
                            ' · ${truncateLabel(item.category, 14)}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              relativeTimeLabel(item.pubDate, AppLocalizations.of(context)),
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
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
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.35,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // Scope line first, wait reason second (#41) — a quiet text label,
        // not an icon-only hint.
        if (scopeLabel != null || waitLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [?scopeLabel, ?waitLabel].join(' · '),
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Actions column — shown when no thumbnail
// =============================================================================

class _FeedItemActions extends StatelessWidget {
  final FeedItem item;
  final bool isBookmarked;
  final bool isRead;

  const _FeedItemActions({
    required this.item,
    required this.isBookmarked,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ActionIcon(
            onTap: () => unawaited(confirmBookmarkToggle(context, item)),
            icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            color: isBookmarked
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            size: 20,
            semanticLabel: isBookmarked
                ? AppLocalizations.of(context).semanticRemoveBookmark
                : AppLocalizations.of(context).semanticBookmark,
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
          // 20px icon + 14px padding = 48x48 minimum touch target.
          padding: const EdgeInsets.all(14.0),
          child: Icon(icon, color: color, size: size),
        ),
      ),
    );
  }
}
