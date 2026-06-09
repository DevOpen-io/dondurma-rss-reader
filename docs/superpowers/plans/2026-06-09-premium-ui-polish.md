# Premium UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the existing RSS reader UI to feel premium — richer theme system, nav bar pill indicator, improved feed cards with thumbnails, article reading comfort, and richer empty states.

**Architecture:** All changes are additive visual polish to existing widgets. No new providers, routes, or architectural changes. Five independent tasks covering theme, nav, feed list, article view, and empty states.

**Tech Stack:** Flutter, Material 3, FlexColorScheme, GoogleFonts (Outfit), CachedNetworkImage, Provider

---

### Task 1: Enhance AppThemeBuilder with component overrides

**Files:**
- Modify: `lib/theme/app_theme.dart`

- [ ] **Step 1: Replace app_theme.dart with enhanced version**

Replace the entire file content:

```dart
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemeBuilder {
  static final String _font = GoogleFonts.outfit().fontFamily!;

  static TextTheme _textTheme(Color color) =>
      GoogleFonts.outfitTextTheme().apply(bodyColor: color, displayColor: color).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: color),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: color),
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: color),
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: color),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: color),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: color),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20, color: color),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: color),
        titleSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: color),
        bodyLarge: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 16, color: color),
        bodyMedium: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 14, color: color),
        bodySmall: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 12, color: color),
        labelLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: color),
        labelMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12, color: color),
        labelSmall: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 11, color: color),
      );

  static ThemeData _applyOverrides(ThemeData base) {
    return base.copyWith(
      textTheme: _textTheme(base.colorScheme.onSurface),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: base.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: base.colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  static ThemeData light(FlexScheme scheme) =>
      _applyOverrides(FlexColorScheme.light(scheme: scheme, fontFamily: _font).toTheme);

  static ThemeData dark(FlexScheme scheme) =>
      _applyOverrides(FlexColorScheme.dark(scheme: scheme, fontFamily: _font).toTheme);
}
```

- [ ] **Step 2: Run analysis to verify no errors**

Run: `flutter analyze lib/theme/app_theme.dart`
Expected: No issues found.

- [ ] **Step 3: Run the app and verify theme applies**

Run: `flutter run`
Expected: App launches. AppBar has no scroll-under tint. SnackBars float with rounded corners. Typography feels more consistent across screens.

---

### Task 2: Bottom nav pill indicator

**Files:**
- Modify: `lib/widgets/home/home_bottom_nav.dart`

- [ ] **Step 1: Replace NavBarItem with animated pill version**

Replace the entire file content:

```dart
import 'package:flutter/material.dart';

class NavBarItem extends StatelessWidget {
  const NavBarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = selected ? primary : onSurface.withValues(alpha: 0.55);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10.5,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analysis**

Run: `flutter analyze lib/widgets/home/home_bottom_nav.dart`
Expected: No issues found.

- [ ] **Step 3: Run app and verify pill indicator**

Run: `flutter run`
Expected: Selected nav tab shows a soft colored pill behind its icon. Tapping a different tab animates the pill away and shows it on the new tab.

---

### Task 3: Feed list card improvements

**Files:**
- Modify: `lib/widgets/feed_list_item.dart`
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Rewrite feed_list_item.dart**

Replace the entire content of `lib/widgets/feed_list_item.dart`:

```dart
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/feed_item.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
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
              width: 72,
              height: 72,
              memCacheWidth: 216,
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
```

- [ ] **Step 2: Update section headers in home_screen.dart**

In `lib/screens/home_screen.dart`, replace the entire `_buildSectionHeader` method (find it by the `Widget _buildSectionHeader(String title` signature):

```dart
Widget _buildSectionHeader(String title, {String? trailingText}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: colorScheme.primary.withValues(alpha: 0.85),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        if (trailingText != null) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              trailingText,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 11.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
```

Also fix the hardcoded `Colors.grey` in the empty/filter state text. Find this exact block in `home_screen.dart`:
```dart
style: const TextStyle(color: Colors.grey),
```
Replace with:
```dart
style: TextStyle(
  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
  fontSize: 14,
),
```

- [ ] **Step 3: Run analysis**

Run: `flutter analyze lib/widgets/feed_list_item.dart lib/screens/home_screen.dart`
Expected: No issues found.

- [ ] **Step 4: Run app and verify**

Run: `flutter run`
Expected:
- Feed cards with images show a 72×72 rounded thumbnail on the right; bookmark icon overlays the thumbnail bottom-right corner.
- Cards without images show the bookmark column on the right as before.
- Unread cards have a slightly more visible primary tint (0.07 vs 0.035 previously).
- Swiping: the action icon smoothly scales up when swipe threshold is hit, scales back on release.
- Section headers (Today/Yesterday/Older) show a small primary-colored left accent bar.

---

### Task 4: Article reading view improvements

**Files:**
- Modify: `lib/screens/article_screen.dart`

- [ ] **Step 1: Remove full-text toggle from AppBar actions**

In `lib/screens/article_screen.dart`, find and delete this block inside the `actions:` list of `SliverAppBar` (it appears before the "Open in browser" button):

```dart
// Full-text toggle (icon only)
if (widget.item.link.isNotEmpty)
  CircleActionButton(
    icon: provider.fullTextActive
        ? Icons.auto_stories_rounded
        : Icons.short_text_rounded,
    isActive: provider.fullTextActive,
    onPressed: provider.isLoadingFullText
        ? null
        : provider.toggleFullText,
    tooltip: provider.fullTextActive
        ? l10n.fullTextExtraction
        : l10n.shortTextMode,
  ),
```

- [ ] **Step 2: Add max-width constraint around article body**

Use computed padding — no re-indentation needed.

**Edit A:** Add `import 'dart:math' as math;` at top of `lib/screens/article_screen.dart`. Find:
```dart
import '../widgets/article/article_reading_mode_toggle.dart';
```
Replace with:
```dart
import '../widgets/article/article_reading_mode_toggle.dart';
import 'dart:math' as math;
```

**Edit B:** Change the `SliverToBoxAdapter`'s padding to adapt on wide screens. Find:
```dart
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
```
Replace with:
```dart
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: math.max(
                        20.0,
                        (MediaQuery.of(context).size.width - 680) / 2,
                      ),
                    ),
```

- [ ] **Step 3: Remove the source info bar**

Find and delete this entire Container (the "Source info bar") in `lib/screens/article_screen.dart`:

```dart
                        // Source info bar (informational only)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.rss_feed_rounded,
                                size: 16,
                                color: colorScheme.primary.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.item.siteName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
```

- [ ] **Step 4: Make reading progress bar more prominent**

Find:
```dart
return LinearProgressIndicator(
  value: animatedProgress,
  minHeight: 2.5,
  backgroundColor: Colors.transparent,
  valueColor: AlwaysStoppedAnimation<Color>(
    colorScheme.primary.withValues(alpha: 0.7),
  ),
);
```
Replace with:
```dart
return LinearProgressIndicator(
  value: animatedProgress,
  minHeight: 3.0,
  backgroundColor: Colors.transparent,
  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
);
```

- [ ] **Step 5: Run analysis**

Run: `flutter analyze lib/screens/article_screen.dart`
Expected: No issues found.

- [ ] **Step 6: Run app and open an article to verify**

Run: `flutter run`
Expected:
- AppBar has only "Open in browser" and "Share" actions (no reading mode toggle in AppBar).
- Article source info bar removed — header is cleaner.
- Article content constrained to 680px max on wide screens; on phone it fills width normally.
- Reading progress bar is solid primary color, 3px height — clearly visible as you scroll.
- Inline reading mode toggle widget still present below article title area.

---

### Task 5: Rich empty states for Bookmarks and Folders

**Files:**
- Modify: `lib/screens/bookmarks_screen.dart`
- Modify: `lib/screens/folders_screen.dart`

- [ ] **Step 1: Replace bookmarks empty state**

In `lib/screens/bookmarks_screen.dart`, find the empty state block:
```dart
if (bookmarkedItems.isEmpty) {
  return Center(
    child: Text(
      l10n.noBookmarks,
      style: TextStyle(
        color: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    ),
  );
}
```

Replace with:
```dart
if (bookmarkedItems.isEmpty) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmark_border_rounded,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.15),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.noBookmarks,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Swipe left on any article to save it here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 2: Replace folders empty state**

In `lib/screens/folders_screen.dart`, find:
```dart
if (sortedCategoryNames.isEmpty) {
  return Center(
    child: Text(
      l10n.noFolders,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    ),
  );
}
```

Replace with:
```dart
if (sortedCategoryNames.isEmpty) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.15),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.noFolders,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a folder to organize your feeds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3: Run analysis**

Run: `flutter analyze lib/screens/bookmarks_screen.dart lib/screens/folders_screen.dart`
Expected: No issues found.

- [ ] **Step 4: Run app and verify empty states**

Run: `flutter run`
Expected:
- Empty Bookmarks tab: large faded bookmark icon (64px) + bold title + descriptive subtitle.
- Empty Folders tab: large faded folder icon (64px) + bold title + descriptive subtitle.
- Both screens feel intentional rather than forgotten.
