import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/image_cache_service.dart';
import '../../utils/share_actions.dart';
import '../../utils/time_format.dart';
import '../../widgets/feed_list_item.dart' show confirmBookmarkToggle;
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
    required this.onSelect,
    required this.searchFocusNode,
    required this.listFocusNode,
  });

  @override
  State<DesktopArticleListPane> createState() => DesktopArticleListPaneState();
}

class DesktopArticleListPaneState extends State<DesktopArticleListPane> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Per-row keys used only for Scrollable.ensureVisible. They are keyed by
  /// *index*, not item id: feed items share `guid ?? link` identities, so two
  /// different articles can legitimately carry the same id — an id-keyed map
  /// duplicates GlobalKeys across siblings (the "Multiple widgets used the
  /// same GlobalKey" spam).
  final Map<int, GlobalObjectKey> _tileKeys = {};

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

  GlobalObjectKey _keyFor(int index) =>
      _tileKeys.putIfAbsent(index, () => GlobalObjectKey(index));

  void _selectIndex(int index) {
    if (index < 0 || index >= widget.items.length) return;
    final item = widget.items[index];
    widget.onSelect(item);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tileKeys[index]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 120),
          alignment: 0.5,
        );
      }
    });
  }

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final items = widget.items;
    if (items.isEmpty) return KeyEventResult.ignored;

    final currentIndex = widget.selectedId == null
        ? -1
        : items.indexWhere((i) => i.id == widget.selectedId);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectIndex(currentIndex < 0 ? 0 : (currentIndex + 1).clamp(0, items.length - 1));
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
                IconButton(
                  icon: provider.isSyncing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                  tooltip: l10n.refresh,
                  onPressed: provider.isSyncing
                      ? null
                      : () => provider.refreshAll(),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),

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
                    Icon(
                      Icons.wifi_off,
                      size: 15,
                      color: cs.onErrorContainer,
                    ),
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
                        child: ListView.builder(
                        controller: _scrollController,
                        scrollCacheExtent: const ScrollCacheExtent.pixels(400),
                        itemCount:
                            widget.items.length +
                            1, // +1 pagination footer
                        itemBuilder: (context, index) {
                          if (index == widget.items.length) {
                            return HomePaginationFooter(provider: provider);
                          }
                          final item = widget.items[index];
                          return _DesktopArticleTile(
                            key: _keyFor(index),
                            item: item,
                            selected: item.id == widget.selectedId,
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
      (b) => b.bookmarkedItemIds.contains(item.id),
    );
    final timeFormat = context.select<SettingsProvider, String>(
      (s) => s.timeFormat,
    );
    final dateStr = item.pubDate != null
        ? DateFormat(
            articleDatePattern(use24HourFormat(context, timeFormat)),
          ).format(item.pubDate!.toLocal())
        : '';

    return Material(
      key: key,
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
                              color: cs.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                        if (isBookmarked) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.bookmark,
                            size: 12,
                            color: cs.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: isRead
                            ? FontWeight.w400
                            : FontWeight.w600,
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
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
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
          unawaited(
            context.read<FeedProvider>().toggleReadStatus(item.id),
          );
        case 'bookmark':
          unawaited(confirmBookmarkToggle(context, item));
        case 'open':
          launchUrl(
            Uri.parse(item.link),
            mode: LaunchMode.externalApplication,
          );
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
