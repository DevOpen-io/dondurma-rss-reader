import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/feed_provider.dart';
import '../../utils/platform_caps.dart';
import '../../widgets/adaptive_dialog.dart';
import '../../widgets/add_feed_dialog.dart';
import '../../widgets/home/add_category_dialog.dart';
import '../explore_feeds_page.dart';
import '../home_screen.dart';
import '../settings_screen.dart';
import 'desktop_article_list.dart';
import 'desktop_reader_pane.dart';
import 'desktop_sidebar.dart';

/// Width at which the desktop shell collapses to the existing mobile layout.
/// Below this a single-column navigation is more usable than three panes.
const double kDesktopNarrowBreakpoint = 860;

/// Width below which the sidebar collapses to an icon rail instead of the
/// full category tree.
const double kDesktopRailBreakpoint = 1150;

/// Picks the mobile or desktop home experience.
///
/// Mobile hosts always use [HomeScreen]. On desktop, wide windows get the
/// three-pane layout while a very narrow window (or phone-sized embedder)
/// falls back to the mobile single-column navigation — preserving existing
/// behavior everywhere.
class AdaptiveHomeScreen extends StatelessWidget {
  const AdaptiveHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!PlatformCaps.isDesktop) return const HomeScreen();
    final width = MediaQuery.sizeOf(context).width;
    if (width < kDesktopNarrowBreakpoint) return const HomeScreen();
    return const DesktopHomeScreen();
  }
}

/// Three-pane desktop shell: navigation sidebar, article list, reader.
class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  DesktopSection _section = DesktopSection.articles;
  String? _selectedArticleId;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _listFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------------

  List<FeedItem> get _currentItems {
    final feed = context.read<FeedProvider>();
    if (_section == DesktopSection.bookmarks) {
      final bookmarks = context.read<BookmarkProvider>().bookmarkedItems;
      return [
        for (final item in bookmarks)
          item.copyWith(isRead: feed.isRead(item.id)),
      ];
    }
    return [
      ...feed.todayItems,
      ...feed.yesterdayItems,
      ...feed.olderItems,
    ];
  }

  void _selectArticle(FeedItem item) {
    setState(() => _selectedArticleId = item.id);
    if (!item.isRead) {
      unawaited(context.read<FeedProvider>().markAsRead(item.id));
    }
  }

  FeedItem? _resolveSelected() {
    final id = _selectedArticleId;
    if (id == null) return null;
    final items = _currentItems;
    for (final item in items) {
      if (item.id == id) return item;
    }
    // Article fell out of the current filter — keep showing it rather than
    // blanking the reader mid-read.
    final feed = context.read<FeedProvider>();
    for (final item in feed.items) {
      if (item.id == id) return item;
    }
    for (final item in context.read<BookmarkProvider>().bookmarkedItems) {
      if (item.id == id) {
        return item.copyWith(isRead: feed.isRead(item.id));
      }
    }
    return null;
  }

  void _navigate(int delta) {
    final items = _currentItems;
    if (items.isEmpty) return;
    final idx = _selectedArticleId == null
        ? -1
        : items.indexWhere((i) => i.id == _selectedArticleId);
    final next = (idx + delta).clamp(0, items.length - 1);
    if (idx == next && idx >= 0) return;
    _selectArticle(items[next < 0 ? 0 : next]);
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  void _showAddFeed() =>
      showAdaptiveSheet<void>(context, const AddFeedDialog());

  void _showAddCategory() =>
      showAdaptiveSheet<void>(context, const AddCategoryDialog());

  void _openDiscover() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExploreFeedsPage()));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(AppLocalizations.of(context).settingsTab)),
          body: const SettingsScreen(),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = PlatformCaps.useMetaShortcuts;

    // Rebuild on provider changes so list/selection stay in sync.
    context.watch<FeedProvider>();
    context.watch<BookmarkProvider>();

    final items = _currentItems;
    final selected = _resolveSelected();
    final selectedIndex = selected == null
        ? -1
        : items.indexWhere((i) => i.id == selected.id);

    final width = MediaQuery.sizeOf(context).width;
    final railMode = width < kDesktopRailBreakpoint;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyR, control: !meta, meta: meta):
            () => unawaited(context.read<FeedProvider>().refreshAll()),
        SingleActivator(LogicalKeyboardKey.keyF, control: !meta, meta: meta):
            _searchFocusNode.requestFocus,
        SingleActivator(LogicalKeyboardKey.keyN, control: !meta, meta: meta):
            _showAddFeed,
        SingleActivator(LogicalKeyboardKey.comma, control: !meta, meta: meta):
            _openSettings,
      },
      child: Scaffold(
        body: Row(
          children: [
            // ── Column 1: navigation ───────────────────────────────────
            SizedBox(
              width: railMode ? 72 : 264,
              child: railMode
                  ? _IconRail(
                      section: _section,
                      onSectionChanged: (s) =>
                          setState(() => _section = s),
                      onAddFeed: _showAddFeed,
                      onOpenDiscover: _openDiscover,
                      onOpenSettings: _openSettings,
                    )
                  : DesktopSidebar(
                      section: _section,
                      onSectionChanged: (s) =>
                          setState(() => _section = s),
                      onAddFeed: _showAddFeed,
                      onAddCategory: _showAddCategory,
                      onOpenDiscover: _openDiscover,
                      onOpenSettings: _openSettings,
                    ),
            ),
            VerticalDivider(
              width: 1,
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),

            // ── Column 2: article list ─────────────────────────────────
            SizedBox(
              width: railMode ? 320 : 380,
              child: DesktopArticleListPane(
                items: items,
                selectedId: selected?.id,
                onSelect: _selectArticle,
                searchFocusNode: _searchFocusNode,
                listFocusNode: _listFocusNode,
              ),
            ),
            VerticalDivider(
              width: 1,
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),

            // ── Column 3: reader ───────────────────────────────────────
            Expanded(
              child: DesktopReaderPane(
                item: selected,
                currentIndex: selectedIndex < 0 ? 0 : selectedIndex,
                totalCount: items.length,
                onPrevious: selectedIndex > 0 ? () => _navigate(-1) : null,
                onNext: selectedIndex >= 0 && selectedIndex < items.length - 1
                    ? () => _navigate(1)
                    : (items.isNotEmpty && selectedIndex < 0
                          ? () => _navigate(0)
                          : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon-only navigation used between the narrow and wide breakpoints.
class _IconRail extends StatelessWidget {
  final DesktopSection section;
  final ValueChanged<DesktopSection> onSectionChanged;
  final VoidCallback onAddFeed;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenSettings;

  const _IconRail({
    required this.section,
    required this.onSectionChanged,
    required this.onAddFeed,
    required this.onOpenDiscover,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    Widget railItem(IconData icon, String label,
        {required bool selected, required VoidCallback onTap}) {
      return Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? cs.primaryContainer.withValues(alpha: 0.6)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: 14),
          railItem(
            Icons.dynamic_feed_rounded,
            l10n.allNews,
            selected: section == DesktopSection.articles,
            onTap: () => onSectionChanged(DesktopSection.articles),
          ),
          const SizedBox(height: 6),
          railItem(
            Icons.bookmark_outline_rounded,
            l10n.bookmarksTab,
            selected: section == DesktopSection.bookmarks,
            onTap: () => onSectionChanged(DesktopSection.bookmarks),
          ),
          const SizedBox(height: 6),
          railItem(
            Icons.add_rounded,
            l10n.semanticAddFeed,
            selected: false,
            onTap: onAddFeed,
          ),
          const Spacer(),
          railItem(
            Icons.lightbulb_outline_rounded,
            l10n.suggestedFeeds,
            selected: false,
            onTap: onOpenDiscover,
          ),
          const SizedBox(height: 6),
          railItem(
            Icons.settings_outlined,
            l10n.settingsTab,
            selected: false,
            onTap: onOpenSettings,
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
