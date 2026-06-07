# Codebase Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **CRITICAL CONSTRAINT: DO NOT run any git commands.** No `git add`, `git commit`, `git status`, `git diff`, or any other git operation. All changes land as uncommitted edits. This is a hard project rule.

**Goal:** Split bloated screen files into focused widget files, fix a listener memory-leak pattern in `article_screen.dart`, scope broad `context.watch()` calls in `HomeScreen` and `AppDrawer`, and add `const` constructors throughout.

**Architecture:** Each large file's private `_Widget` classes are extracted into `lib/widgets/<domain>/` files. The screens then import and use these extracted widgets unchanged. No behavior is changed — pure structural refactor + lifecycle fix + provider scope fix.

**Tech Stack:** Flutter 3.x, Provider, Dart MCP server for analysis

---

## File Map

**Files to create:**
- `lib/widgets/article/article_content_skeleton.dart` — `_ArticleContentSkeleton`
- `lib/widgets/article/article_image_carousel.dart` — `_ImageCarousel` (StatefulWidget, owns PageController)
- `lib/widgets/article/article_reading_mode_toggle.dart` — `_ReadingModeToggle` + `_ModeOption`
- `lib/widgets/article/article_circle_buttons.dart` — `_CircleBackButton` + `_CircleActionButton`
- `lib/widgets/home/add_folder_dialog.dart` — `_AddFolderDialog` (StatefulWidget, owns TextEditingController)
- `lib/widgets/home/feed_list_skeleton.dart` — `_FeedListSkeleton`
- `lib/widgets/home/home_bottom_nav.dart` — `_NavBarItem`
- `lib/widgets/home/home_pagination_footer.dart` — `_PaginationFooter`
- `lib/widgets/home/home_search_history_panel.dart` — `_SearchHistoryPanel`
- `lib/widgets/settings/settings_widgets.dart` — `_SectionTitle`, `_SettingsCard`, `_TileDivider`, `_SwitchTile`, `_DropdownTile`, `_ActionTile`, `_QuietHoursTile`, `_TimePill`, `_SettingsIcon`
- `lib/widgets/folders/folder_dialogs.dart` — `_EditCategoryDialog`, `_EditSubscriptionDialog`, `_CategoryAction` enum
- `lib/widgets/folders/feed_action_sheet.dart` — `_FeedActionSheet`, `_ActionTile` (folders-specific)

**Files to modify:**
- `lib/screens/article_screen.dart` — remove extracted private widgets; fix `_ArticlePageState` listener lifecycle (store provider ref, remove try/catch)
- `lib/screens/home_screen.dart` — remove extracted private widgets; scope `FeedProvider` rebuilds with `Consumer`
- `lib/screens/settings_screen.dart` — remove extracted private widgets; import from `lib/widgets/settings/settings_widgets.dart`
- `lib/screens/folders_screen.dart` — remove extracted private widgets; import from new widget files
- `lib/widgets/app_drawer.dart` — scope broad `context.watch<FeedProvider>()` + `context.watch<SubscriptionProvider>()` with `Consumer`/`context.select`

---

### Task 1: Extract article circle buttons + content skeleton

**Goal:** Move `_CircleBackButton`, `_CircleActionButton`, `_ArticleContentSkeleton` out of `article_screen.dart` (they are purely stateless and have no shared state).

**Files:**
- Create: `lib/widgets/article/article_circle_buttons.dart`
- Create: `lib/widgets/article/article_content_skeleton.dart`
- Modify: `lib/screens/article_screen.dart`

- [ ] **Step 1: Create `article_circle_buttons.dart`**

```dart
// lib/widgets/article/article_circle_buttons.dart
import 'package:flutter/material.dart';

class CircleBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  const CircleBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isActive;

  const CircleActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isActive ? colorScheme.primary : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: isActive
              ? colorScheme.primary.withValues(alpha: 0.2)
              : colorScheme.surface.withValues(alpha: 0.7),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create `article_content_skeleton.dart`**

```dart
// lib/widgets/article/article_content_skeleton.dart
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class ArticleContentSkeleton extends StatelessWidget {
  const ArticleContentSkeleton({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Skeletonizer(
          effect: ShimmerEffect(
            baseColor: colorScheme.onSurface.withValues(alpha: 0.08),
            highlightColor: colorScheme.onSurface.withValues(alpha: 0.15),
            duration: const Duration(milliseconds: 1500),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Bone.multiText(lines: 4, fontSize: 16),
              const SizedBox(height: 20),
              Bone.multiText(lines: 3, fontSize: 16),
              const SizedBox(height: 20),
              Bone(
                height: 180,
                width: double.infinity,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(height: 20),
              Bone.multiText(lines: 5, fontSize: 16),
              const SizedBox(height: 20),
              Bone.multiText(lines: 3, fontSize: 16),
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              label!,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 3: Update `article_screen.dart` imports and replace usages**

At the top of `lib/screens/article_screen.dart`, add:
```dart
import '../widgets/article/article_circle_buttons.dart';
import '../widgets/article/article_content_skeleton.dart';
```

Replace every usage of the old private widget names:
- `_CircleBackButton(` → `CircleBackButton(`
- `_CircleActionButton(` → `CircleActionButton(`
- `_ArticleContentSkeleton(` → `ArticleContentSkeleton(`

Then delete the private class definitions from `article_screen.dart`. Find each class by name and delete the entire class body:
- Delete the entire `_CircleBackButton` class (locate by `class _CircleBackButton`)
- Delete the entire `_CircleActionButton` class (locate by `class _CircleActionButton`)
- Delete the entire `_ArticleContentSkeleton` class (locate by `class _ArticleContentSkeleton`)

- [ ] **Step 4: Run Dart analysis**

Use MCP tool: `mcp__dart-mcp-server__analyze_files` on `lib/screens/article_screen.dart`

Expected: 0 errors.

- [ ] **Step 5: Verify app compiles**

Run: `flutter analyze lib/`

Expected: No new errors.

---

### Task 2: Extract `_ImageCarousel` + `_ReadingModeToggle`

**Goal:** Move the two remaining multi-widget groups out of `article_screen.dart`. Both are self-contained visual components.

**Files:**
- Create: `lib/widgets/article/article_image_carousel.dart`
- Create: `lib/widgets/article/article_reading_mode_toggle.dart`
- Modify: `lib/screens/article_screen.dart`

- [ ] **Step 1: Create `article_image_carousel.dart`**

```dart
// lib/widgets/article/article_image_carousel.dart
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

class ArticleImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  const ArticleImageCarousel({super.key, required this.imageUrls});

  @override
  State<ArticleImageCarousel> createState() => _ArticleImageCarouselState();
}

class _ArticleImageCarouselState extends State<ArticleImageCarousel> {
  int _currentPage = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageCount = widget.imageUrls.length;
    final screenWidth = MediaQuery.of(context).size.width - 40;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        children: [
          SizedBox(
            height: screenWidth * 0.65,
            child: PageView.builder(
              controller: _pageController,
              itemCount: imageCount,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrls[index],
                    memCacheWidth: 800,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorWidget: (context, url, error) => Container(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined, size: 40),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...List.generate(imageCount, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
              const SizedBox(width: 8),
              Text(
                '${_currentPage + 1} / $imageCount',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create `article_reading_mode_toggle.dart`**

```dart
// lib/widgets/article/article_reading_mode_toggle.dart
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class ArticleReadingModeToggle extends StatelessWidget {
  final bool isFullText;
  final bool isLoading;
  final VoidCallback onToggle;
  final ColorScheme colorScheme;
  final AppLocalizations l10n;

  const ArticleReadingModeToggle({
    super.key,
    required this.isFullText,
    required this.isLoading,
    required this.onToggle,
    required this.colorScheme,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 5),
              Text(
                l10n.readingModeLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ModeOption(
                  label: l10n.modeShort,
                  icon: Icons.short_text_rounded,
                  isSelected: !isFullText,
                  isLoading: false,
                  onTap: isFullText && !isLoading ? onToggle : null,
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeOption(
                  label: isLoading ? l10n.fullTextLoading : l10n.modeFull,
                  icon: isLoading ? null : Icons.auto_stories_rounded,
                  isSelected: isFullText,
                  isLoading: isLoading,
                  onTap: !isFullText && !isLoading ? onToggle : null,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;

  const _ModeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else if (icon != null)
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                if (!isLoading) const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Update `article_screen.dart` imports and usages**

Add imports:
```dart
import '../widgets/article/article_image_carousel.dart';
import '../widgets/article/article_reading_mode_toggle.dart';
```

Replace in `_ArticlePage.build()`:
- `_ImageCarousel(imageUrls: urls)` → `ArticleImageCarousel(imageUrls: urls)`
- `_ReadingModeToggle(` → `ArticleReadingModeToggle(`

Delete from `article_screen.dart` — locate each class by name and delete the entire class body:
- Delete `_ImageCarousel` StatefulWidget and its `_ImageCarouselState` inner class (locate by `class _ImageCarousel`)
- Delete `_ReadingModeToggle` StatelessWidget (locate by `class _ReadingModeToggle`)
- Delete `_ModeOption` StatelessWidget (locate by `class _ModeOption`)

- [ ] **Step 4: Run Dart analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` on `lib/screens/article_screen.dart`

Expected: 0 errors.

---

### Task 3: Fix `_ArticlePageState` listener lifecycle

**Goal:** Eliminate the fragile `try/catch` around `context.read<ArticlePageProvider>()` in `dispose()`. Store the provider reference as a field so `dispose()` doesn't need to call `context.read`.

**Files:**
- Modify: `lib/screens/article_screen.dart` (class `_ArticlePageState`)

- [ ] **Step 1: Add provider field and fix initState**

In `_ArticlePageState`, add a field:
```dart
ArticlePageProvider? _articlePageProvider;
```

Change `initState` from:
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      final provider = context.read<ArticlePageProvider>();
      provider.setContentReady();
      provider.addListener(_onProviderChanged);
      provider.checkAutoFullText(context.read<SubscriptionProvider>());
    }
  });
}
```

To:
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _articlePageProvider = context.read<ArticlePageProvider>();
    _articlePageProvider!.setContentReady();
    _articlePageProvider!.addListener(_onProviderChanged);
    _articlePageProvider!.checkAutoFullText(context.read<SubscriptionProvider>());
  });
}
```

- [ ] **Step 2: Fix dispose to use the stored reference**

Change `dispose` from:
```dart
@override
void dispose() {
  try {
    context.read<ArticlePageProvider>().removeListener(_onProviderChanged);
  } catch (_) {
    // Provider already disposed — nothing to clean up.
  }
  super.dispose();
}
```

To:
```dart
@override
void dispose() {
  _articlePageProvider?.removeListener(_onProviderChanged);
  super.dispose();
}
```

- [ ] **Step 3: Run Dart analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` on `lib/screens/article_screen.dart`

Expected: 0 errors.

- [ ] **Step 4: Runtime smoke test (article listener)**

Launch the app (`flutter run`). Navigate to an article. Then swipe to the next article and back. Verify:
- Each article's content loads (listener fires correctly)
- Swiping does NOT crash (no "context.read called after dispose" exceptions)
- The reading mode toggle works (full-text / short mode)

This confirms the stored-reference pattern didn't break the listener setup/teardown cycle.

---

### Task 4: Extract home screen sub-widgets

**Goal:** Move `_NavBarItem`, `_SearchHistoryPanel`, `_PaginationFooter`, `_FeedListSkeleton`, and `_AddFolderDialog` out of `home_screen.dart`. These are self-contained and large enough to merit their own files.

**Files:**
- Create: `lib/widgets/home/home_bottom_nav.dart`
- Create: `lib/widgets/home/home_search_history_panel.dart`
- Create: `lib/widgets/home/home_pagination_footer.dart`
- Create: `lib/widgets/home/feed_list_skeleton.dart`
- Create: `lib/widgets/home/add_folder_dialog.dart`
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Create `home_bottom_nav.dart`**

```dart
// lib/widgets/home/home_bottom_nav.dart
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
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: selected ? 11 : 10,
                  color: color,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
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

- [ ] **Step 2: Create `home_search_history_panel.dart`**

```dart
// lib/widgets/home/home_search_history_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

class HomeSearchHistoryPanel extends StatelessWidget {
  const HomeSearchHistoryPanel({
    super.key,
    required this.searchController,
    required this.onQuerySelected,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQuerySelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsProvider = context.watch<SettingsProvider>();
    final history = settingsProvider.searchHistory;

    if (history.isEmpty) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: searchController,
      builder: (context, _) {
        final currentText = searchController.text.toLowerCase().trim();
        final filtered = currentText.isEmpty
            ? history
            : history
                  .where(
                    (q) =>
                        q.toLowerCase().contains(currentText) &&
                        q.toLowerCase() != currentText,
                  )
                  .toList();

        if (filtered.isEmpty) return const SizedBox.shrink();

        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  l10n.recentSearches,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              ...filtered.map(
                (query) => InkWell(
                  onTap: () => onQuerySelected(query),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            query,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            context.read<SettingsProvider>().removeSearchQuery(query);
                          },
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 3: Create `home_pagination_footer.dart`**

```dart
// lib/widgets/home/home_pagination_footer.dart
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/feed_provider.dart';
import 'feed_list_skeleton.dart';

class HomePaginationFooter extends StatelessWidget {
  const HomePaginationFooter({super.key, required this.provider});

  final FeedProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (provider.items.isEmpty) return const SizedBox.shrink();

    if (provider.isLoadingMore) {
      return const FeedListSkeleton(itemCount: 2, showHeader: false);
    }

    if (provider.hasMoreItems) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: TextButton.icon(
            onPressed: provider.loadMoreItems,
            icon: const Icon(Icons.expand_more),
            label: Text(l10n.loadMore),
          ),
        ),
      );
    }

    if (provider.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Text(
            l10n.allCaughtUp,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
```

- [ ] **Step 4: Create `feed_list_skeleton.dart`**

```dart
// lib/widgets/home/feed_list_skeleton.dart
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class FeedListSkeleton extends StatelessWidget {
  const FeedListSkeleton({super.key, this.itemCount = 6, this.showHeader = true});

  final int itemCount;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      effect: ShimmerEffect(
        baseColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
        highlightColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
        duration: const Duration(milliseconds: 1500),
      ),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount + (showHeader ? 1 : 0),
        itemBuilder: (context, index) {
          if (showHeader && index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Bone.text(words: 1, fontSize: 12),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.square(size: 44, borderRadius: BorderRadius.circular(12)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Bone.text(words: 2, fontSize: 12)),
                            const SizedBox(width: 8),
                            Bone.text(words: 1, fontSize: 11),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Bone.multiText(lines: 2, fontSize: 15),
                        const SizedBox(height: 4),
                        Bone.text(words: 5, fontSize: 13),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Bone.icon(size: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Create `add_folder_dialog.dart`**

```dart
// lib/widgets/home/add_folder_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/subscription_provider.dart';

class AddFolderDialog extends StatefulWidget {
  const AddFolderDialog({super.key});

  @override
  State<AddFolderDialog> createState() => _AddFolderDialogState();
}

class _AddFolderDialogState extends State<AddFolderDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _serverError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _serverError = null;
    });
    final name = _nameController.text.trim();
    final success = await context.read<SubscriptionProvider>().addCategory(name);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isLoading = false;
        _serverError = AppLocalizations.of(context).folderAlreadyExists;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return Form(
      key: _formKey,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.create_new_folder_outlined, color: cs.onPrimaryContainer, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.addFolder, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(l10n.newFolderName, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextFormField(
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  hintText: 'Tech, Sports, Finance…',
                  prefixIcon: Icon(Icons.folder_outlined, color: cs.onSurfaceVariant, size: 20),
                  errorText: _serverError,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary, width: 2)),
                  errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.error, width: 1.5)),
                  focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.error, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l10n.pleaseEnterFolderName;
                  return null;
                },
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    child: Text(l10n.cancel),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                        : const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: Text(l10n.save),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Update `home_screen.dart` imports and usages**

Replace the top imports block to add:
```dart
import '../widgets/home/home_bottom_nav.dart';
import '../widgets/home/home_search_history_panel.dart';
import '../widgets/home/home_pagination_footer.dart';
import '../widgets/home/feed_list_skeleton.dart';
import '../widgets/home/add_folder_dialog.dart';
```

Replace usages:
- `_NavBarItem(` → `NavBarItem(`
- `_SearchHistoryPanel(` → `HomeSearchHistoryPanel(`
- `_PaginationFooter(` → `HomePaginationFooter(`
- `_FeedListSkeleton(` → `FeedListSkeleton(`
- `const _AddFolderDialog()` → `const AddFolderDialog()`

Delete from `home_screen.dart`:
- `_NavBarItem` class
- `_SearchHistoryPanel` class
- `_PaginationFooter` class
- `_FeedListSkeleton` class
- `_AddFolderDialog` StatefulWidget + `_AddFolderDialogState` class

- [ ] **Step 7: Run Dart analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` on `lib/screens/home_screen.dart`

Expected: 0 errors.

---

### Task 5: Extract settings screen tile widgets

**Goal:** Move the 9 reusable tile helper widgets from `settings_screen.dart` into `lib/widgets/settings/settings_widgets.dart`. This reduces `settings_screen.dart` by ~400 lines.

**Files:**
- Create: `lib/widgets/settings/settings_widgets.dart`
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Create `settings_widgets.dart`**

The file should contain — **copy these classes verbatim from `settings_screen.dart`**:
- `_SectionTitle` → rename to `SettingsSectionTitle`
- `_SettingsCard` → rename to `SettingsCard`
- `_TileDivider` → rename to `SettingsTileDivider`
- `_SwitchTile` → rename to `SettingsSwitchTile`
- `_DropdownTile<T>` → rename to `SettingsDropdownTile<T>`
- `_ActionTile` → rename to `SettingsActionTile`
- `_QuietHoursTile` → rename to `SettingsQuietHoursTile`
- `_TimePill` → rename to `SettingsTimePill`
- `_SettingsIcon` → rename to `SettingsIcon`

File header:
```dart
// lib/widgets/settings/settings_widgets.dart
import 'package:flutter/material.dart';
```

Copy each class body exactly from `settings_screen.dart`, only changing the class names as listed above. Internal cross-references: `_SettingsIcon` used inside `_SwitchTile`, `_DropdownTile`, `_ActionTile`, `_QuietHoursTile` — update those to `SettingsIcon`. `_TimePill` used inside `_QuietHoursTile` — update to `SettingsTimePill`.

- [ ] **Step 2: Update `settings_screen.dart`**

Add import at top:
```dart
import '../widgets/settings/settings_widgets.dart';
```

Remove the `const _kSchemes = [...]` list — it stays in `settings_screen.dart`.

Replace all usages in `settings_screen.dart`:
- `_SectionTitle(` → `SettingsSectionTitle(`
- `_SettingsCard(` → `SettingsCard(`
- `const _TileDivider()` → `const SettingsTileDivider()`
- `_SwitchTile(` → `SettingsSwitchTile(`
- `_DropdownTile<` → `SettingsDropdownTile<`
- `_ActionTile(` → `SettingsActionTile(`
- `_QuietHoursTile(` → `SettingsQuietHoursTile(`

Delete from `settings_screen.dart` the 9 private class definitions.

- [ ] **Step 3: Run Dart analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` on `lib/screens/settings_screen.dart` and `lib/widgets/settings/settings_widgets.dart`

Expected: 0 errors.

---

### Task 6: Extract folders screen dialogs and action sheet

**Goal:** Move `_EditCategoryDialog`, `_EditSubscriptionDialog` (each with multiple controllers) and `_FeedActionSheet` + `_ActionTile` out of `folders_screen.dart`.

**Files:**
- Create: `lib/widgets/folders/folder_dialogs.dart`
- Create: `lib/widgets/folders/feed_action_sheet.dart`
- Modify: `lib/screens/folders_screen.dart`

- [ ] **Step 1: Create `folder_dialogs.dart`**

```dart
// lib/widgets/folders/folder_dialogs.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/feed_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/keyword_input_dialog.dart';
import '../../models/feed_subscription.dart';
```

Then copy verbatim from `folders_screen.dart`:
- `_EditCategoryDialog` StatefulWidget → rename to `EditCategoryDialog`
- `_EditCategoryDialogState` → rename to `_EditCategoryDialogState` (keep private, stays in same file)
- `_EditSubscriptionDialog` StatefulWidget → rename to `EditSubscriptionDialog`
- `_EditSubscriptionDialogState` → rename to `_EditSubscriptionDialogState`

Update all `context.pop()` and `Navigator` calls — they remain unchanged.

- [ ] **Step 2: Create `feed_action_sheet.dart`**

```dart
// lib/widgets/folders/feed_action_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/subscription_provider.dart';
```

Copy verbatim from `folders_screen.dart`:
- `_FeedActionSheet` StatelessWidget → rename to `FeedActionSheet`
- `_ActionTile` (the one inside `_FeedActionSheet`) → rename to `FolderActionTile` (avoids naming conflict with `SettingsActionTile`)

Update `_FeedActionSheet.build()` internal references to `_ActionTile(` → `FolderActionTile(`.

- [ ] **Step 3: Update `folders_screen.dart` imports and usages**

Add imports:
```dart
import '../widgets/folders/folder_dialogs.dart';
import '../widgets/folders/feed_action_sheet.dart';
```

Replace usages:
- `_EditCategoryDialog(` → `EditCategoryDialog(`
- `_EditSubscriptionDialog(` → `EditSubscriptionDialog(`
- `_FeedActionSheet(` → `FeedActionSheet(`

Delete from `folders_screen.dart`:
- `_EditCategoryDialog` + `_EditCategoryDialogState`
- `_EditSubscriptionDialog` + `_EditSubscriptionDialogState`
- `_FeedActionSheet` class
- The `_ActionTile` class (only the one used by `_FeedActionSheet`)

- [ ] **Step 4: Run Dart analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` on `lib/screens/folders_screen.dart`

Expected: 0 errors.

---

### Task 7: Scope `FeedProvider` and `SubscriptionProvider` rebuilds

**Goal:** Two files call broad `context.watch()` at the top of `build()`, causing full widget-tree rebuilds on every provider event:

1. `HomeScreen.build()` calls `context.watch<FeedProvider>()` — rebuilds entire `Scaffold` (AppBar, BottomNav, Drawer)
2. `AppDrawer.build()` calls `context.watch<FeedProvider>()` + `context.watch<SubscriptionProvider>()` — rebuilds entire drawer on every feed update

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/widgets/app_drawer.dart`

**Context for HomeScreen:** `_HomeScreenState.build()` currently starts with:
```dart
final provider = context.watch<FeedProvider>();
final todayItems = provider.todayItems;
...
```
This rebuilds the entire `Scaffold` including AppBar and BottomNav on every `FeedProvider.notifyListeners()` call.

The AppBar only needs `provider.selectedCategory` and `provider.showUnreadOnly`. The body needs the full provider. The BottomNav does not need the provider at all.

**Context for AppDrawer:** Open `lib/widgets/app_drawer.dart` and read the `build()` method. Identify which parts of the drawer actually change when `FeedProvider` notifies (typically: unread count badge, active category highlight). Scope those parts using `Consumer<FeedProvider>` wrappers rather than watching at the top of `build()`.

- [ ] **Step 1: Restructure `HomeScreen.build()` to use Consumer for the body and Selector for the AppBar**

Replace the `build()` method of `_HomeScreenState`. The `context.watch<FeedProvider>()` call must be removed from the top level. Instead:

For the AppBar title and unread filter button, use `context.select`:
```dart
final appBarTitle = context.select<FeedProvider, String>((p) {
  switch (_selectedIndex) {
    case 1: return l10n.foldersTab;
    case 2: return l10n.bookmarksTab;
    case 3: return l10n.settingsTab;
    default: return p.selectedCategory ?? l10n.myFeeds;
  }
});
final showUnreadOnly = context.select<FeedProvider, bool>((p) => p.showUnreadOnly);
```

For the body, wrap `_buildHomeBody(...)` in a `Consumer<FeedProvider>`:
```dart
body: _selectedIndex == 0
    ? Consumer<FeedProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              if (_isSearching)
                HomeSearchHistoryPanel(
                  searchController: _searchController,
                  onQuerySelected: (query) { ... },
                ),
              Expanded(
                child: _buildHomeBody(
                  context,
                  provider,
                  provider.todayItems,
                  provider.yesterdayItems,
                  provider.olderItems,
                ),
              ),
            ],
          );
        },
      )
    : _selectedIndex == 1
    ? const FoldersScreen()
    : _selectedIndex == 2
    ? const BookmarksScreen()
    : const SettingsScreen(),
```

The `provider` reference used in AppBar actions (for `toggleShowUnreadOnly()`) should use `context.read<FeedProvider>()` since they are callbacks.

- [ ] **Step 2: Scope `AppDrawer` provider watches**

Read `lib/widgets/app_drawer.dart` fully. Remove the top-level `context.watch<FeedProvider>()` and `context.watch<SubscriptionProvider>()` calls. Wrap only the sections that actually need to rebuild in `Consumer` widgets (or use `context.select` for scalar values like unread count). The static parts of the drawer (title, nav links that don't change) must NOT be inside a Consumer.

- [ ] **Step 3: Run Dart analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` on `lib/screens/home_screen.dart` and `lib/widgets/app_drawer.dart`

Expected: 0 errors.

- [ ] **Step 4: Runtime smoke test**

Launch the app (`flutter run`). Perform these manual checks — each must pass without crash or visual regression:
- Open the home screen; feed items load and display
- Open the side drawer; categories and unread counts display correctly
- Toggle the "unread only" filter; list updates
- Navigate to Folders, Bookmarks, Settings tabs and back — no rebuilds on load
- Tap a feed item to open an article — article screen opens correctly

These checks verify that the Consumer/Selector restructuring did not break any data flow.

- [ ] **Step 5: Run full project analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` (no paths = full project)

Expected: 0 errors across all files.

---

### Task 8: Add `const` constructors throughout new and modified widget files

**Goal:** Add `const` constructors to all StatelessWidgets and StatefulWidgets whose constructors qualify (no non-const default values, no final fields that prevent const). Flutter can skip rebuilding `const` widgets entirely, which is a direct performance win for all the extracted widgets.

**Files:**
- `lib/widgets/article/article_circle_buttons.dart`
- `lib/widgets/article/article_content_skeleton.dart`
- `lib/widgets/article/article_reading_mode_toggle.dart`
- `lib/widgets/home/home_bottom_nav.dart`
- `lib/widgets/home/home_search_history_panel.dart`
- `lib/widgets/home/home_pagination_footer.dart`
- `lib/widgets/home/feed_list_skeleton.dart`
- `lib/widgets/home/add_folder_dialog.dart`
- `lib/widgets/settings/settings_widgets.dart`
- `lib/widgets/folders/folder_dialogs.dart`
- `lib/widgets/folders/feed_action_sheet.dart`
- Any `_XyzState` parent `StatefulWidget` class whose constructor can be const

**Rules:**
- A constructor can be `const` if: all fields are `final`, no field has a non-const default value, and the class doesn't extend something that breaks const.
- `StatefulWidget` constructors can always be `const` (the `State` object is not part of the constructor).
- `StatelessWidget` constructors can be `const` unless a field's type isn't const-compatible.
- `_ModeOption` (private) inside `article_reading_mode_toggle.dart` cannot use `const` construction from outside its file — but its constructor should still be marked `const` for internal use.

- [ ] **Step 1: Add `const` to all qualifying constructors**

For each file listed above, open it and add `const` to every constructor that qualifies. Prefer `const` over non-const wherever possible. Example transformation:

```dart
// Before
class NavBarItem extends StatelessWidget {
  NavBarItem({super.key, required this.icon, ...});
  ...
}

// After
class NavBarItem extends StatelessWidget {
  const NavBarItem({super.key, required this.icon, ...});
  ...
}
```

Also update call sites where widgets are used without `const` in `article_screen.dart`, `home_screen.dart`, `settings_screen.dart`, `folders_screen.dart` — add `const` at each instantiation where all arguments are themselves const or literals.

- [ ] **Step 2: Run full Dart analysis**

Use MCP: `mcp__dart-mcp-server__analyze_files` (full project)

Expected: 0 errors. Dart analyzer will flag any `const` that is wrong.

- [ ] **Step 3: Verify line counts are as expected**

Run:
```bash
find lib -name "*.dart" | xargs wc -l | sort -rn | head -20
```

Expected reductions from original:
| File | Before | Target after |
|---|---|---|
| `settings_screen.dart` | 1221 | ~800 |
| `article_screen.dart` | 1136 | ~500 |
| `home_screen.dart` | 1107 | ~550 |
| `folders_screen.dart` | 882 | ~500 |
