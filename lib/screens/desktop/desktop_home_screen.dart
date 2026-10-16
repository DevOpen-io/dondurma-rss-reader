import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_item.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/feed_provider.dart';
import '../../services/feed_date_groups.dart';
import '../../utils/motion.dart';
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

  /// Focus Read Mode: rail + explorer + list hide, reader takes the window.
  bool _focusMode = false;

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

  List<FeedItem> _currentItems(FeedDateGroups groups) {
    final feed = context.read<FeedProvider>();
    if (_section == DesktopSection.bookmarks) {
      final bookmarks = context.read<BookmarkProvider>().bookmarkedItems;
      return [
        for (final item in bookmarks)
          item.copyWith(isRead: feed.isRead(item.id)),
      ];
    }
    return [...groups.today, ...groups.yesterday, ...groups.older];
  }

  void _selectArticle(FeedItem item) {
    setState(() => _selectedArticleId = item.id);
    if (!item.isRead) {
      unawaited(context.read<FeedProvider>().markAsRead(item.id));
    }
  }

  FeedItem? _resolveSelected(FeedDateGroups groups) {
    final id = _selectedArticleId;
    if (id == null) return null;
    final items = _currentItems(groups);
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

  /// Escape layering: Focus Mode exits first, a focused search field is
  /// dismissed next, then the dashboard swallows the key (no destructive
  /// action at the root). Pushed routes handle their own Escape pop.
  void _onEscape() {
    if (_focusMode) {
      setState(() => _focusMode = false);
      return;
    }
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      return;
    }
  }

  void _toggleFocusMode() {
    final groups = context.read<FeedProvider>().dateGroups;
    if (!_focusMode && _resolveSelected(groups) == null) return;
    setState(() => _focusMode = !_focusMode);
  }

  void _navigate(int delta) {
    final items = _currentItems(context.read<FeedProvider>().dateGroups);
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const _EscapePopScope(child: ExploreFeedsPage()),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EscapePopScope(
          child: Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context).settingsTab),
            ),
            body: const SettingsScreen(),
          ),
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

    // Narrow rebuild triggers: the date-groups instance is replaced only on
    // real data changes (filter/read/fetch), so status-only notifications
    // like isLoading toggles don't rebuild the whole shell or re-copy the
    // item list. Bookmarks mutate in place, so keep the full watch there.
    final groups = context.select<FeedProvider, FeedDateGroups>(
      (p) => p.dateGroups,
    );
    context.watch<BookmarkProvider>();

    final items = _currentItems(groups);
    final selected = _resolveSelected(groups);
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
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      },
      child: Scaffold(
        // When the explorer isn't pinned it lives in the scaffold drawer,
        // opened from the rail's Feeds button.
        drawer: explorerPinned ? null : Drawer(width: 300, child: explorer),
        body: Row(
          children: [
            // ── App-level navigation rail (always present) ─────────────
            // Focus Read Mode hides the side panes behind a width animation
            // — the reader stays mounted the whole time.
            _PaneSlot(
              width: _focusMode ? 0 : 72,
              naturalWidth: 72,
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
            if (!_focusMode) divider,

            // ── Feed/category explorer (content navigation) ────────────
            // Collapses to width 0 instead of unmounting: ExpansionTile
            // state, scroll position and the nav tree survive the toggle.
            _PaneSlot(
              width: _focusMode || !explorerPinned ? 0 : 280,
              naturalWidth: 280,
              child: explorer,
            ),
            if (!_focusMode && explorerPinned) divider,

            // ── Article list ───────────────────────────────────────────
            _PaneSlot(
              width: _focusMode ? 0 : (explorerPinned ? 380 : 360),
              naturalWidth: explorerPinned ? 380 : 360,
              child: DesktopArticleListPane(
                items: items,
                selectedId: selected?.id,
                onSelect: _selectArticle,
                searchFocusNode: _searchFocusNode,
                listFocusNode: _listFocusNode,
              ),
            ),
            if (!_focusMode) divider,

            // ── Reader ─────────────────────────────────────────────────
            Expanded(
              child: DesktopReaderPane(
                item: selected,
                currentIndex: selectedIndex < 0 ? 0 : selectedIndex,
                totalCount: items.length,
                focusMode: _focusMode,
                onToggleFocusMode: _toggleFocusMode,
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
                    duration: motionDuration(
                      context,
                      const Duration(milliseconds: 150),
                    ),
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
          // Feeds = the RSS workspace itself (explorer + list + reader).
          // It does not reset feed/category scope — All Articles lives at
          // the top of the explorer for the global timeline.
          railItem(
            Icons.rss_feed_rounded,
            l10n.feedsTab,
            selected: section == DesktopSection.articles,
            onTap: () {
              // Restore the workspace; fall back to the global timeline
              // when the remembered feed no longer exists.
              final feed = context.read<FeedProvider>();
              final sel = feed.selectedFeedUrl;
              if (sel != null &&
                  !(feed.subscriptionProvider?.subscriptions.any(
                        (s) => s.url == sel,
                      ) ??
                      false)) {
                feed.selectCategory(null);
              }
              onSectionChanged(DesktopSection.articles);
              if (explorerInDrawer) {
                (explorerToggle ??
                    () => Scaffold.of(context).openDrawer())();
              }
            },
          ),
          railItem(
            Icons.bookmark_outline_rounded,
            l10n.bookmarksTab,
            selected: section == DesktopSection.bookmarks,
            onTap: () => onSectionChanged(DesktopSection.bookmarks),
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

/// Fixed-width pane slot that animates between collapsed (0) and its target
/// width instead of mounting/unmounting — child state (scroll positions,
/// ExpansionTile state, focus nodes) survives Focus Read Mode toggles.
///
/// Honors reduced-motion: [motionDuration] collapses the animation to zero
/// when the OS asks for it.
class _PaneSlot extends StatelessWidget {
  final double width;

  /// The child's real width — it always lays out at this size and the slot
  /// clips it while animating, so collapsing never reflows the content.
  final double naturalWidth;
  final Widget child;

  const _PaneSlot({
    required this.width,
    required this.naturalWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: motionDuration(context, const Duration(milliseconds: 240)),
      curve: Curves.easeOutCubic,
      width: width,
      // ClipRect, not Container.clipBehavior — a clipping Container without
      // a decoration asserts in debug and crashes on `decoration!` in
      // profile/release.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          child: SizedBox(
            width: naturalWidth,
            height: double.infinity,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Escape-to-pop for pushed secondary screens (Settings, Discover).
///
/// Desktop-only wrapper: dialogs, menus and dropdowns already dismiss on
/// Escape through their modal barrier, so this only wraps full routes that
/// otherwise have no keyboard back affordance. `Focus(autofocus)` keeps the
/// shortcut live even when the page hasn't claimed primary focus yet.
class _EscapePopScope extends StatelessWidget {
  final Widget child;

  const _EscapePopScope({required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
