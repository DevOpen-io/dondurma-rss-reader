import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../models/refresh_progress.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/image_cache_service.dart';
import '../../utils/motion.dart';
import '../../utils/share_actions.dart';
import '../../utils/time_format.dart';
import '../../widgets/feed_list_item.dart' show confirmBookmarkToggle;
import '../../widgets/anchored_feed_list.dart';
import '../../widgets/home/feed_list_skeleton.dart';
import '../../widgets/home/home_pagination_footer.dart';
import '../../widgets/home/filter_bottom_sheet.dart';
import 'package:intl/intl.dart';

/// Middle column of the desktop layout: search/filter/refresh toolbar plus
/// the virtualized article list.
///
/// Mouse + keyboard: hover states, right-click context menu, ↑/↓ to move
/// the selection (which drives the reader pane), Enter to mark-read.
class DesktopArticleListPane extends StatefulWidget {
  /// Articles to render — already filtered/decorated by the provider.
  final List<FeedItem> items;

  /// Currently selected article id (reader pane mirror).
  final String? selectedId;
  final String? selectedFeedUrl;

  /// Called when the user selects an article (tap or arrow keys).
  final ValueChanged<FeedItem> onSelect;

  /// Search field focus node — owned by the shell so Ctrl/Cmd+F can target it.
  final FocusNode searchFocusNode;

  /// List focus node for arrow navigation — owned by the shell.
  final FocusNode listFocusNode;

  const DesktopArticleListPane({
    super.key,
    required this.items,
    required this.selectedId,
    this.selectedFeedUrl,
    required this.onSelect,
    required this.searchFocusNode,
    required this.listFocusNode,
  });

  @override
  State<DesktopArticleListPane> createState() => DesktopArticleListPaneState();
}

class DesktopArticleListPaneState extends State<DesktopArticleListPane> {
  final TextEditingController _searchController = TextEditingController();
  final _scrollController = AnchoredScrollController();

  // Source + GUID + occurrence identities remain stable across insertions,
  // without sharing GlobalObjectKeys with another mounted pane.
  final Map<Object, GlobalKey> _tileKeys = {};
  List<Object> _rowIds = const [];

  @override
  void initState() {
    super.initState();
    _searchController.text = context.read<FeedProvider>().searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) =>
      _tileKeys.putIfAbsent(_rowIds[index], GlobalKey.new);

  void _selectIndex(int index) {
    if (index < 0 || index >= widget.items.length) return;
    final item = widget.items[index];
    final rowId = _rowIds[index];
    widget.onSelect(item);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _tileKeys[rowId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: motionDuration(ctx, const Duration(milliseconds: 120)),
          alignment: 0.5,
        );
      }
    });
  }

  bool _isSelected(FeedItem item) =>
      item.id == widget.selectedId &&
      (widget.selectedFeedUrl == null ||
          item.feedUrl == widget.selectedFeedUrl);

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final items = widget.items;
    if (items.isEmpty) return KeyEventResult.ignored;

    final currentIndex = widget.selectedId == null
        ? -1
        : items.indexWhere((i) => _isSelected(i));

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectIndex(
        currentIndex < 0 ? 0 : (currentIndex + 1).clamp(0, items.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectIndex(currentIndex <= 0 ? 0 : currentIndex - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && currentIndex >= 0) {
      final item = items[currentIndex];
      if (!item.isRead) {
        unawaited(context.read<FeedProvider>().markAsRead(item.id));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<FeedProvider>();
    _rowIds = articleRowIds(widget.items);
    final remaining = _rowIds.toSet();
    _tileKeys.removeWhere((id, _) => !remaining.contains(id));

    return Material(
      // Subtly darker than the reader surface so the three panes read as
      // distinct layers in both light and dark themes.
      color: cs.surfaceContainerLowest,
      child: Column(
        children: [
          // ── Toolbar: search + filter + refresh ────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: widget.searchFocusNode,
                    decoration: InputDecoration(
                      hintText: l10n.searchFeeds,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      suffixIcon: provider.searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: l10n.close,
                              onPressed: () {
                                _searchController.clear();
                                provider.setSearchQuery('');
                              },
                            )
                          : null,
                    ),
                    style: const TextStyle(fontSize: 13.5),
                    onChanged: provider.setSearchQuery,
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        context.read<SettingsProvider>().addSearchQuery(v);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Badge(
                    isLabelVisible: provider.hasActiveSheetFilter,
                    smallSize: 8,
                    child: Icon(
                      Icons.filter_list_rounded,
                      size: 20,
                      color: provider.hasActiveSheetFilter
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  tooltip: l10n.filterSheetTitle,
                  onPressed: () => FilterBottomSheet.show(context),
                ),
                // Progress lives in a dedicated ValueNotifier so per-feed
                // updates repaint this chip only — never the whole list.
                ValueListenableBuilder<RefreshProgress>(
                  valueListenable: provider.refreshProgress,
                  builder: (context, progress, _) {
                    if (progress.phase == RefreshPhase.refreshing) {
                      return Tooltip(
                        message: l10n.refreshingFeeds(
                          progress.completed,
                          progress.total,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                '${progress.completed} / ${progress.total}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final tooltip = switch (progress.phase) {
                      RefreshPhase.completedWithErrors =>
                        l10n.refreshSummaryFailed(
                          progress.completed,
                          progress.failed,
                        ),
                      RefreshPhase.completed => l10n.updatedJustNow,
                      RefreshPhase.offline => l10n.offlineBanner,
                      RefreshPhase.idle ||
                      RefreshPhase.failed ||
                      RefreshPhase.refreshing => l10n.refresh,
                    };
                    // Failures surface once in the completion toast — the
                    // button always returns to the plain idle icon.
                    return IconButton(
                      icon: Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: tooltip,
                      onPressed: () => provider.refreshAll(userInitiated: true),
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),

          // ── Offline banner ───────────────────────────────────────────
          if (provider.isOffline && provider.items.isNotEmpty)
            Material(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, size: 15, color: cs.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.offlineBanner,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── List ─────────────────────────────────────────────────────
          Expanded(
            child: provider.isLoading && widget.items.isEmpty
                ? const FeedListSkeleton()
                : widget.items.isEmpty
                ? _EmptyListState(provider: provider)
                : Focus(
                    focusNode: widget.listFocusNode,
                    onKeyEvent: _onListKey,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (scrollInfo) {
                        if (!provider.isLoadingMore &&
                            provider.hasMoreItems &&
                            scrollInfo.metrics.pixels >=
                                scrollInfo.metrics.maxScrollExtent - 300) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            provider.loadMoreItems();
                          });
                        }
                        return false;
                      },
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: AnchoredFeedList(
                          controller: _scrollController,
                          cacheExtent: 400,
                          rowIds: [..._rowIds, 'pagination-footer'],
                          isArticle: (index) => index < widget.items.length,
                          itemBuilder: (context, index) {
                            if (index == widget.items.length) {
                              return HomePaginationFooter(provider: provider);
                            }
                            final item = widget.items[index];
                            return _DesktopArticleTile(
                              key: _keyFor(index),
                              item: item,
                              selected: _isSelected(item),
                              onTap: () => widget.onSelect(item),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyListState extends StatelessWidget {
  final FeedProvider provider;
  const _EmptyListState({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 44,
              color: cs.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            Text(
              provider.selectedCategory != null
                  ? l10n.noFeedsInCategory(provider.selectedCategory!)
                  : l10n.noFeedsMatchFilter,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 13.5,
              ),
            ),
            if (provider.hasActiveSheetFilter ||
                provider.searchQuery.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  provider.setSearchQuery('');
                  if (provider.hasActiveSheetFilter) {
                    provider.clearSheetFilter();
                  }
                },
                child: Text(l10n.clearFilters),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact article row optimized for a mid-width desktop column: unread dot,
/// source + relative time, two-line title, thumbnail, bookmark affordance.
class _DesktopArticleTile extends StatelessWidget {
  final FeedItem item;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopArticleTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isRead = item.isRead;
    final isBookmarked = context.select<BookmarkProvider, bool>(
      (b) => b.isBookmarked(item.id, feedUrl: item.feedUrl),
    );
    final timeFormat = context.select<SettingsProvider, String>(
      (s) => s.timeFormat,
    );
    final dateStr = item.pubDate != null
        ? DateFormat(
            articleDatePattern(use24HourFormat(context, timeFormat)),
          ).format(item.pubDate!.toLocal())
        : '';

    // NOTE: never forward `key` into the returned tree — the widget already
    // owns it via its constructor; passing it to Material reserves the same
    // GlobalKey twice ("Multiple widgets used the same GlobalKey").
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.4)
          : Colors.transparent,
      child: InkWell(
        hoverColor: cs.onSurface.withValues(alpha: 0.04),
        onTap: onTap,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details, l10n, isRead, isBookmarked),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unread indicator
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRead ? Colors.transparent : cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.siteName,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (dateStr.isNotEmpty) ...[
                          Text(
                            ' · $dateStr',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                        if (isBookmarked) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.bookmark, size: 12, color: cs.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                        color: isRead
                            ? cs.onSurface.withValues(alpha: 0.6)
                            : cs.onSurface,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Opacity(
                    opacity: isRead ? 0.55 : 1.0,
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      cacheManager: ThumbnailCacheManager.instance,
                      width: 52,
                      height: 52,
                      memCacheWidth: 120,
                      maxWidthDiskCache: 120,
                      maxHeightDiskCache: 120,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                      placeholder: (_, _) => Container(
                        width: 52,
                        height: 52,
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    AppLocalizations l10n,
    bool isRead,
    bool isBookmarked,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'read',
          child: _menuRow(
            context,
            isRead ? Icons.mark_email_unread : Icons.mark_email_read,
            isRead ? l10n.semanticMarkAsUnread : l10n.semanticMarkAsRead,
          ),
        ),
        PopupMenuItem(
          value: 'bookmark',
          child: _menuRow(
            context,
            isBookmarked ? Icons.bookmark_remove : Icons.bookmark_add,
            isBookmarked ? l10n.semanticRemoveBookmark : l10n.semanticBookmark,
          ),
        ),
        if (item.link.isNotEmpty)
          PopupMenuItem(
            value: 'open',
            child: _menuRow(
              context,
              Icons.open_in_new_rounded,
              l10n.openInExternalBrowser,
            ),
          ),
        if (item.link.isNotEmpty)
          PopupMenuItem(
            value: 'copy',
            child: _menuRow(context, Icons.copy_rounded, l10n.shareArticle),
          ),
      ],
    ).then((action) {
      if (action == null || !context.mounted) return;
      switch (action) {
        case 'read':
          unawaited(context.read<FeedProvider>().toggleReadStatus(item.id));
        case 'bookmark':
          unawaited(confirmBookmarkToggle(context, item));
        case 'open':
          launchUrl(Uri.parse(item.link), mode: LaunchMode.externalApplication);
        case 'copy':
          shareArticleLink(context, item);
      }
    });
  }

  Widget _menuRow(BuildContext context, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
