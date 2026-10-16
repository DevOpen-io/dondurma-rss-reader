import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../providers/article_page_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/share_actions.dart';
import '../../widgets/in_app_browser.dart';
import '../article_screen.dart';

/// Right column of the desktop layout: the selected article rendered by the
/// same [ArticlePage] used by the mobile reader, plus previous/next
/// navigation driven by the middle column's order.
class DesktopReaderPane extends StatefulWidget {
  /// Currently selected article; null shows the empty state.
  final FeedItem? item;

  /// Position inside the current list (0-based) and total count.
  final int currentIndex;
  final int totalCount;

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const DesktopReaderPane({
    super.key,
    required this.item,
    required this.currentIndex,
    required this.totalCount,
    this.onPrevious,
    this.onNext,
  });

  @override
  State<DesktopReaderPane> createState() => _DesktopReaderPaneState();
}

class _DesktopReaderPaneState extends State<DesktopReaderPane> {
  /// Shared by the visible Scrollbar and the article's CustomScrollView —
  /// the reason this pane is stateful.
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant DesktopReaderPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selecting a different article resets the reading position.
    if (oldWidget.item?.id != widget.item?.id &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openLink(BuildContext context, FeedItem item) {
    var url = item.link.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final settings = context.read<SettingsProvider>();
    openInAppBrowser(
      context,
      url,
      title: item.title,
      adBlockEnabled: settings.adBlockEnabled,
      browserMode: settings.browserMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final current = widget.item;
    if (current == null) {
      return Material(
        color: cs.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.article_outlined,
                size: 56,
                color: cs.onSurface.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.selectArticleToRead,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: cs.surface,
      child: Column(
        children: [
          // ── Navigation toolbar ───────────────────────────────────────
          SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  tooltip: l10n.previousArticle,
                  onPressed: widget.onPrevious,
                  iconSize: 22,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  tooltip: l10n.nextArticle,
                  onPressed: widget.onNext,
                  iconSize: 22,
                ),
                const Spacer(),
                if (widget.totalCount > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      l10n.articlePosition(
                        widget.currentIndex + 1,
                        widget.totalCount,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // Open/share live here in the pane toolbar — the embedded
                // ArticlePage suppresses its app-bar actions so the two
                // toolbars never stack.
                IconButton(
                  icon: const Icon(Icons.launch_rounded, size: 20),
                  tooltip: l10n.openInBrowser,
                  onPressed: current.link.isNotEmpty
                      ? () => _openLink(context, current)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 20),
                  tooltip: l10n.shareArticle,
                  onPressed: current.link.isNotEmpty
                      ? () => shareArticleLink(context, current)
                      : null,
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
          // ── Article body ─────────────────────────────────────────────
          Expanded(
            // Keyed by article id so switching items builds a fresh
            // ArticlePageProvider + scroll state instead of reusing stale
            // page state.
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ChangeNotifierProvider(
                key: ValueKey('reader-${current.id}'),
                create: (_) => ArticlePageProvider(item: current),
                child: ArticlePage(
                  item: current,
                  currentIndex: widget.currentIndex,
                  totalCount: widget.totalCount,
                  isActive: true,
                  embedded: true,
                  scrollController: _scrollController,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
