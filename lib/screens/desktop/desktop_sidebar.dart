import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/feed_subscription.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/motion.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/folders/explorer_tree.dart';
import '../../widgets/folders/folder_actions.dart';
import '../../widgets/saved_searches.dart';

/// Content-navigation column of the desktop layout: the category+feed
/// tree with add affordances. App-level destinations (All News, Bookmarks,
/// Discover, Settings) live in the rail — this pane is feed explorer only.
/// Selection writes through to [FeedProvider]'s existing category/feed
/// filters — no second filter engine.
class DesktopSidebar extends StatefulWidget {
  /// Currently selected library section.
  final DesktopSection section;

  /// Articles vs bookmarks section switch.
  final ValueChanged<DesktopSection> onSectionChanged;

  /// Add-feed and add-category affordances.
  final VoidCallback onAddFeed;
  final VoidCallback onAddCategory;

  const DesktopSidebar({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.onAddFeed,
    required this.onAddCategory,
  });

  @override
  State<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<DesktopSidebar> {
  /// Owns the nav ListView's position — the Scrollbar above must share this
  /// controller or it falls back to an unattached PrimaryScrollController.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      // One step lighter than the rail — reads as content chrome rather
      // than app chrome.
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          // ── Explorer header: title + add affordances ──────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.feedsTab,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 20),
                  tooltip: l10n.semanticAddFeed,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onAddFeed,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.create_new_folder_outlined,
                    size: 19,
                  ),
                  tooltip: l10n.addFolder,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onAddCategory,
                ),
              ],
            ),
          ),

          // ── Categories header + fixed global destination + tree ──────
          // All Articles is pinned above the scrollable category/feed list
          // so it stays reachable no matter how deep the tree scrolls.
          Expanded(
            child: Consumer2<FeedProvider, SubscriptionProvider>(
              builder: (context, feed, subs, _) {
                final categories = subs.categoriesOrdered;
                final nonUncategorized = categories
                    .where((c) => c != 'Uncategorized')
                    .toList();
                final hasUncategorized = categories.contains('Uncategorized');
                final byCategory = feedsByCategory(subs.subscriptions);

                final inArticles = widget.section == DesktopSection.articles;
                final globalSelected =
                    inArticles &&
                    feed.selectedCategory == null &&
                    feed.selectedFeedUrl == null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(l10n.categories),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                      child: _AllArticlesTile(
                        title: l10n.allArticles,
                        count: feed.unreadCount(),
                        selected: globalSelected,
                        onTap: () {
                          feed.selectCategory(null);
                          widget.onSectionChanged(DesktopSection.articles);
                        },
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                          children: [
                            for (final category in nonUncategorized)
                              _CategoryNode(
                                key: ValueKey('cat-$category'),
                                title: category,
                                category: category,
                                feedSources: byCategory[category] ?? const [],
                                feed: feed,
                                subs: subs,
                                active: inArticles,
                                onSelect: () => widget.onSectionChanged(
                                  DesktopSection.articles,
                                ),
                              ),
                            if (hasUncategorized)
                              _CategoryNode(
                                key: const ValueKey('cat-uncategorized'),
                                title: l10n.randomBlogs,
                                category: 'Uncategorized',
                                feedSources:
                                    byCategory['Uncategorized'] ?? const [],
                                feed: feed,
                                subs: subs,
                                active: inArticles,
                                isUncategorized: true,
                                onSelect: () => widget.onSectionChanged(
                                  DesktopSection.articles,
                                ),
                              ),
                            SavedSearchList(
                              header: (_, title) => _SectionLabel(title),
                              onOpen: (query) {
                                widget.onSectionChanged(
                                  DesktopSection.articles,
                                );
                                feed.setSearchQuery(query);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum DesktopSection { articles, bookmarks }

/// Fixed global destination at the top of the Categories explorer.
///
/// Visually distinct from `_CategoryNode`: a flat nav row (icon + label +
/// counter) rather than an expandable tree node, so a user category with
/// the same name can never be confused with the built-in global view.
class _AllArticlesTile extends StatelessWidget {
  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _AllArticlesTile({
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: cs.onSurface.withValues(alpha: 0.05),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.dynamic_feed_rounded,
                  size: 17,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: tt.bodyMedium?.copyWith(
                      color: selected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.8),
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: tt.labelSmall?.copyWith(
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// Expandable category node listing its feeds — mirrors the mobile drawer's
/// semantics (select category vs select feed) without the drawer chrome.
///
/// Two emphasis levels: `isSelected` (the category itself is the active
/// scope — full primary treatment) and `isAncestor` (a feed inside it is
/// selected — thin left accent + brighter label, no selection fill).
class _CategoryNode extends StatefulWidget {
  final String title;
  final String category;
  final List<FeedSubscription> feedSources;
  final FeedProvider feed;
  final SubscriptionProvider subs;
  final bool active;
  final bool isUncategorized;
  final VoidCallback onSelect;

  const _CategoryNode({
    super.key,
    required this.title,
    required this.category,
    required this.feedSources,
    required this.feed,
    required this.subs,
    required this.active,
    required this.onSelect,
    this.isUncategorized = false,
  });

  @override
  State<_CategoryNode> createState() => _CategoryNodeState();
}

class _CategoryNodeState extends State<_CategoryNode> {
  /// Programmatic expand for ancestor reveal without touching the user's
  /// manual collapse/expand choices.
  final ExpansibleController _expansion = ExpansibleController();

  bool _wasAncestor = false;

  bool get _isSelected =>
      widget.active &&
      widget.feed.selectedCategory == widget.category &&
      widget.feed.selectedFeedUrl == null;

  bool get _isAncestor =>
      widget.active &&
      widget.feed.selectedFeedParentCategory == widget.category;

  @override
  void didUpdateWidget(covariant _CategoryNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reveal the selected feed when its parent became ancestor — never
    // collapse a category the user opened or close a stale ancestor.
    final ancestor = _isAncestor;
    if (ancestor && !_wasAncestor && !_expansion.isExpanded) {
      _expansion.expand();
    }
    _wasAncestor = ancestor;
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final category = widget.category;
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = _isSelected;
    final isAncestor = _isAncestor;
    final emphasis = CategoryEmphasis.of(
      selected: isSelected,
      ancestor: isAncestor,
    );
    final count = feed.unreadCount(category: category);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Semantics(
          selected: isSelected,
          hint: isAncestor ? l10n.semanticAncestorCategory : null,
          child: Stack(
            children: [
              ExpansionTile(
                controller: _expansion,
                expansionAnimationStyle: AnimationStyle(
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 200),
                  ),
                  curve: Curves.easeOutCubic,
                ),
                initiallyExpanded: feed.selectedCategory == category,
                tilePadding: const EdgeInsets.only(left: 12, right: 8),
                childrenPadding: const EdgeInsets.only(left: 8, bottom: 4),
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: emphasis.fill(cs, selectedAlpha: 0.3),
                collapsedBackgroundColor: emphasis.fill(cs, selectedAlpha: 0.5),
                iconColor: cs.onSurfaceVariant,
                collapsedIconColor: cs.onSurfaceVariant.withValues(alpha: 0.6),
                leading: CategoryIcon(
                  category: category,
                  size: 17,
                  color: emphasis.tint(cs, selectedColor: cs.primary),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          feed.selectCategory(category);
                          widget.onSelect();
                        },
                        child: Text(
                          widget.title,
                          style: tt.bodyMedium?.copyWith(
                            color: emphasis.labelColor(cs),
                            fontWeight: emphasis.labelWeight,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: tt.labelSmall?.copyWith(
                          color: emphasis.tint(cs, selectedColor: cs.primary),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (!widget.isUncategorized)
                      Semantics(
                        label: l10n.semanticCategoryOptions,
                        button: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => showCategoryActions(
                            context,
                            widget.category,
                            widget.feedSources.length,
                          ),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(
                              Icons.more_horiz,
                              size: 16,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                children: [
                  for (final sub in widget.feedSources)
                    ExplorerFeedTile(
                      sub: sub,
                      feed: feed,
                      dense: true,
                      onTap: () {
                        feed.selectFeed(sub.url);
                        widget.onSelect();
                      },
                      onShowActions: () => showFeedActions(context, sub),
                    ),
                ],
              ),
              // Ancestor accent: a slim bar at the node's left edge — the
              // "contains selected feed" cue that never reads as selection.
              if (isAncestor)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: IgnorePointer(
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: CategoryEmphasis.accent(cs),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
