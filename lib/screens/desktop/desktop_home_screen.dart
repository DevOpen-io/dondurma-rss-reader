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
import '../../widgets/refresh_completion_listener.dart';
import '../explore_feeds_page.dart';
import '../home_screen.dart';
import '../settings_screen.dart';
import 'desktop_article_list.dart';
import 'desktop_reader_pane.dart';
import 'desktop_sidebar.dart';

/// Width at which the desktop shell collapses to the existing mobile layout.
/// Below this a single-column navigation is more usable than three panes.
const double kDesktopNarrowBreakpoint = 860;

/// Width at which the feed/category explorer pins as its own column next to
/// the app rail. Below this the explorer stays reachable as a drawer from
/// the rail's Feeds button, keeping narrow windows uncluttered.
const double kDesktopExplorerBreakpoint = 1360;

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
    final Widget home;
    if (!PlatformCaps.isDesktop) {
      home = const HomeScreen();
    } else {
      final width = MediaQuery.sizeOf(context).width;
      home = width < kDesktopNarrowBreakpoint
          ? const HomeScreen()
          : const DesktopHomeScreen();
    }
    return RefreshCompletionListener(child: home);
  }
}

/// Desktop shell with a four-zone information architecture:
///
/// ```
/// [App rail] | [Feed explorer] | [Article list] | [Reader]
///  72px        280px             380px            flex
/// ```
///
/// The rail carries app-level destinations; the explorer carries the
/// feed/category tree. Below [kDesktopExplorerBreakpoint] the explorer
/// demotes to a drawer so the rail never merges menu and content.
class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  DesktopSection _section = DesktopSection.articles;
  String? _selectedArticleId;

  /// User-collapsed feed explorer — session-only, so a resize across the
  /// pin breakpoint can't strand it in the wrong state.
  bool _explorerCollapsed = false;

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
    final explorerPinned =
        width >= kDesktopExplorerBreakpoint && !_explorerCollapsed;
    final explorer = DesktopSidebar(
      section: _section,
      onSectionChanged: (s) => setState(() => _section = s),
      onAddFeed: _showAddFeed,
      onAddCategory: _showAddCategory,
    );
    final divider = VerticalDivider(
      width: 1,
      color: cs.outlineVariant.withValues(alpha: 0.35),
    );

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyR, control: !meta, meta: meta):
            () => unawaited(
              context.read<FeedProvider>().refreshAll(userInitiated: true),
            ),
        SingleActivator(LogicalKeyboardKey.keyF, control: !meta, meta: meta):
            _searchFocusNode.requestFocus,
        SingleActivator(LogicalKeyboardKey.keyN, control: !meta, meta: meta):
            _showAddFeed,
        SingleActivator(LogicalKeyboardKey.comma, control: !meta, meta: meta):
            _openSettings,
      },
      child: Scaffold(
        // When the explorer isn't pinned it lives in the scaffold drawer,
        // opened from the rail's Feeds button.
        drawer: explorerPinned ? null : Drawer(width: 300, child: explorer),
        body: Row(
          children: [
            // ── App-level navigation rail (always present) ─────────────
            SizedBox(
              width: 72,
              child: _AppRail(
                section: _section,
                onSectionChanged: (s) => setState(() => _section = s),
                onAddFeed: _showAddFeed,
                onOpenDiscover: _openDiscover,
                onOpenSettings: _openSettings,
                explorerInDrawer: !explorerPinned,
                explorerToggle: width >= kDesktopExplorerBreakpoint
                    ? () => setState(
                        () => _explorerCollapsed = !_explorerCollapsed,
                      )
                    : null,
              ),
            ),
            divider,

            // ── Feed/category explorer (content navigation) ────────────
            if (explorerPinned) ...[
              SizedBox(width: 280, child: explorer),
              divider,
            ],

            // ── Article list ───────────────────────────────────────────
            SizedBox(
              width: explorerPinned ? 380 : 360,
              child: DesktopArticleListPane(
                items: items,
                selectedId: selected?.id,
                onSelect: _selectArticle,
                searchFocusNode: _searchFocusNode,
                listFocusNode: _listFocusNode,
              ),
            ),
            divider,

            // ── Reader ─────────────────────────────────────────────────
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

/// Permanent app-level navigation: identity, primary destinations
/// (All News / Bookmarks / Feeds), then utility entries pinned to the
/// bottom. Content navigation (categories, feeds) lives in the explorer
/// pane/drawer — never merged into this rail.
class _AppRail extends StatelessWidget {
  final DesktopSection section;
  final ValueChanged<DesktopSection> onSectionChanged;
  final VoidCallback onAddFeed;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenSettings;

  /// Whether the feed explorer is demoted to a drawer (narrow windows or
  /// user-collapsed). When true the rail shows a Feeds button.
  final bool explorerInDrawer;

  /// When non-null (wide windows), the Feeds rail item toggles the pinned
  /// explorer instead of opening a drawer.
  final VoidCallback? explorerToggle;

  const _AppRail({
    required this.section,
    required this.onSectionChanged,
    required this.onAddFeed,
    required this.onOpenDiscover,
    required this.onOpenSettings,
    required this.explorerInDrawer,
    this.explorerToggle,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    // Destinations get icon + label; one-off actions and utilities stay
    // icon-only with tooltips (activity-bar grammar: labeled = navigates,
    // bare icon = acts).
    Widget railItem(
      IconData icon,
      String label, {
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 500),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 62,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 19,
                      color: selected
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget railAction(
      IconData icon,
      String tooltip, {
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 40,
            child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return Material(
      // Darkest chrome — the rail visually recedes behind content panes.
      color: cs.surfaceContainerLowest,
      child: Column(
        children: [
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/logo.ico', width: 30, height: 30),
          ),
          const SizedBox(height: 14),

          // ── Primary destinations ────────────────────────────────────
          railItem(
            Icons.dynamic_feed_rounded,
            l10n.allNews,
            selected: section == DesktopSection.articles,
            onTap: () => onSectionChanged(DesktopSection.articles),
          ),
          railItem(
            Icons.bookmark_outline_rounded,
            l10n.bookmarksTab,
            selected: section == DesktopSection.bookmarks,
            onTap: () => onSectionChanged(DesktopSection.bookmarks),
          ),
          if (explorerInDrawer)
            railItem(
              Icons.view_sidebar_outlined,
              l10n.feedsTab,
              selected: false,
              onTap: explorerToggle ??
                  () => Scaffold.of(context).openDrawer(),
            ),
          const SizedBox(height: 8),
          railAction(
            Icons.add_rounded,
            l10n.semanticAddFeed,
            onTap: onAddFeed,
          ),

          const Spacer(),

          // ── Utilities ───────────────────────────────────────────────
          railAction(
            Icons.lightbulb_outline_rounded,
            l10n.suggestedFeeds,
            onTap: onOpenDiscover,
          ),
          const SizedBox(height: 4),
          railAction(
            Icons.settings_outlined,
            l10n.settingsTab,
            onTap: onOpenSettings,
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
