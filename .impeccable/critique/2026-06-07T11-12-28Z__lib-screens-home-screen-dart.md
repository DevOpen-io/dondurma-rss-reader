---
target: lib/screens/home_screen.dart
total_score: 23
p0_count: 1
p1_count: 2
timestamp: 2026-06-07T11-12-28Z
slug: lib-screens-home-screen-dart
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Skeleton loading and offline banner are excellent; no last-refresh timestamp or per-feed error surface |
| 2 | Match System / Real World | 3 | Today/Yesterday/Older grouping is natural; "Subscribed Only" badge meaning is ambiguous |
| 3 | User Control and Freedom | 3 | Search dismissible, unread filter toggleable, pull-to-refresh; no undo mark-as-read |
| 4 | Consistency and Standards | 2 | FAB labels hardcoded English in an otherwise-localized app; date strings not localized; nav tab label inconsistency |
| 5 | Error Prevention | 2 | Folder name deduplication exists; no URL validation visible from home; no destructive-action confirmation |
| 6 | Recognition Rather Than Recall | 2 | Inactive nav tabs are icon-only; swipe gestures entirely undiscoverable |
| 7 | Flexibility and Efficiency | 2 | Swipe gestures serve power users; no bulk actions; no way to jump to unread-only from empty state |
| 8 | Aesthetic and Minimalist Design | 3 | Clean sectioned layout; 80×80 FAB is oversized; "Subscribed Only" badge visible even when no filter is active |
| 9 | Error Recovery | 2 | Offline banner is well-placed; no retry mechanism; feed-load failures not surfaced |
| 10 | Help and Documentation | 1 | No onboarding, no contextual guidance, empty state is passive with no CTA |
| **Total** | | **23/40** | **Acceptable — significant gaps to address** |

## Anti-Patterns Verdict

**LLM assessment**: The overall screen does not scream AI-generated — the layout, skeleton, and offline state handling show genuine craft. However, two banned patterns are present. The 3px left border accent on unread cards (`feed_list_item.dart:221`) is the absolute-ban "side-stripe border" pattern. It's used with semantic intent (marking unread), but the ban exists because the pattern reads as amateurish decoration regardless of intent — the fix is a background tint or a small leading dot (which already exists on line 389). The settings screen (not the target file but same product) uses UPPERCASE tracked eyebrow headers on every section — the other absolute ban.

**Deterministic scan**: `detect.mjs` returned 0 findings on the Dart files. This is expected — the detector parses HTML/CSS and cannot analyze Flutter widget trees. Assessment B is effectively manual for this stack. No false positives to report.

**Visual overlays**: Not applicable (Flutter app, not a browser surface).

## Overall Impression

A well-engineered RSS reader with strong fundamentals — the skeleton loading, swipe gestures, and accessibility semantics all show real attention to quality. The main opportunity is closing the gap between new users and the app's power: first-timers have no entry ramp (empty state is passive, swipe gestures are invisible, inactive tabs are unlabeled), and two banned patterns have slipped in. Fixing the contrast failures and localization bug are the most urgent items — they're regressions in an otherwise careful codebase.

## What's Working

**1. Skeleton loading is production-grade.** `_FeedListSkeleton` with `Skeletonizer` is used for both the initial load and pagination states, with matched shimmer dimensions. Most apps ship a spinner in the middle of a blank screen; this app ships a structural preview.

**2. Swipe gesture mechanics are polished.** The haptic feedback at threshold (`mediumImpact` at trigger, `selectionClick` on cancel), 250ms `easeOutCubic` snap-back, and `Selector2` optimization to avoid full list rebuilds are all deliberate, correct choices.

**3. Offline state handling is contextually appropriate.** The banner appears only when offline AND items exist — not on the empty state — using `colorScheme.errorContainer` correctly. It does not block the feed list.

## Priority Issues

**[P1] Left 3px border accent on unread cards — absolute ban**
- **What**: `feed_list_item.dart:221-228` applies `BorderSide(color: colorScheme.primary.withValues(alpha: 0.6), width: 3)` on the left edge of unread cards.
- **Why it matters**: Side-stripe borders >1px are an absolute ban — they read as decoration regardless of semantic intent. The unread state already has two other indicators: the blue dot at line 389 and bold title weight. The border is redundant and pattern-violating.
- **Fix**: Remove the `Border(left: BorderSide(...))` decoration entirely. The dot indicator + weight contrast communicate unread state without the banned pattern. If a third indicator is wanted, use a subtle background tint (`colorScheme.primary.withValues(alpha: 0.04)`) on the entire card.
- **Suggested command**: `$impeccable polish lib/widgets/feed_list_item.dart`

**[P1] Read-state text contrast fails WCAG AA**
- **What**: In `_FeedItemContent`, read items render description at `onSurface.withValues(alpha: 0.3)` (~#B3B3B3 on white = 1.9:1) and title at `onSurface.withValues(alpha: 0.45)` (~#8C8C8C on white = 3.4:1). Both fail the 4.5:1 body text requirement. Date text at 0.45 alpha fails too.
- **Why it matters**: Read articles are still content the user may want to scan. A contrast ratio of 1.9:1 is essentially invisible for users with low vision — and even for users with normal vision, it causes unnecessary eye strain.
- **Fix**: Floor read-state text at `onSurface.withValues(alpha: 0.55)` for descriptions (~#737373 on white = 4.6:1) and `onSurface.withValues(alpha: 0.65)` for titles. The visual distinction between read and unread should come from weight (already done: `FontWeight.w400` vs `w700`) and opacity of the icon, not from illegible text. Unread date text should be at minimum `alpha: 0.55`.
- **Suggested command**: `$impeccable audit lib/widgets/feed_list_item.dart`

**[P1] FAB labels not localized**
- **What**: `home_screen.dart:480` has `'Add Feed'` and line 482 has `'Add Folder'` as hardcoded English string literals. The rest of the screen uses `l10n.*` strings correctly.
- **Why it matters**: In a localized app, hardcoded strings in the primary action button break every non-English locale. `l10n.semanticAddFeed` (line 455) and `l10n.addFolder` (line 456) already exist — the labels are right there and unused.
- **Fix**: Replace `'Add Feed'` with `l10n.semanticAddFeed` and `'Add Folder'` with `l10n.addFolder` on lines 480 and 482.
- **Suggested command**: `$impeccable harden lib/screens/home_screen.dart`

**[P2] Inactive navigation tabs are icon-only**
- **What**: `_NavBarItem` at line 625 renders the label `Text` only inside `if (selected)`. Unselected tabs show only an icon.
- **Why it matters**: A first-time user looking at three unlabeled icons (a folder, a bookmark, a gear) cannot tell what each tab contains without tapping. Material 3 spec shows labels on all items or uses a pill indicator without labels — not "label only on active." This breaks recognition over recall for three of the four tabs at any given time.
- **Fix**: Always show the label, reducing its font size to 10 on unselected items (`color: unselectedColor, fontWeight: FontWeight.w500`) and 11 on selected. Or adopt the standard `NavigationBar` widget with `labelBehavior: NavigationDestinationLabelBehavior.alwaysShow`.
- **Suggested command**: `$impeccable layout lib/screens/home_screen.dart`

**[P2] "Subscribed Only" badge is always visible and only on Today**
- **What**: `home_screen.dart:127` always passes `trailingText: l10n.subscribedOnly` to the Today section header, regardless of filter state. The Yesterday and Older headers have no such badge.
- **Why it matters**: A user who has no filter active sees "SUBSCRIBED ONLY" — suggesting their feed is filtered when it isn't. A user who does have a filter active sees it only on Today, not on Yesterday or Older, implying the filter applies differently to different sections. Both interpretations are confusing.
- **Fix**: Either (a) remove the badge entirely and rely on the unread-filter toggle button in the AppBar to communicate filter state, or (b) show the badge on all section headers only when `provider.showUnreadOnly` is true.
- **Suggested command**: `$impeccable clarify lib/screens/home_screen.dart`

**[P2] Empty state has no actionable path forward**
- **What**: `home_screen.dart:184-190` shows "No feeds found" as a plain centered `Text` widget. The FAB exists but a new user may not recognize it as the action to take.
- **Why it matters**: The empty state is the most critical moment in the new-user journey. "No feeds found" is a dead end — it describes a state, not what to do. A user who installs the app and sees this message has no affordance pointing them to add a feed.
- **Fix**: Replace the static text with a structured empty state: illustration or icon, heading ("No feeds yet"), one-line explanation, and a prominent "Add your first feed" button that calls `_showAddFeedDialog()`. The FAB should still be present but the inline CTA removes ambiguity.
- **Suggested command**: `$impeccable onboard lib/screens/home_screen.dart`

## Persona Red Flags

**Sam (Accessibility-Dependent User)**
- Description text at alpha 0.3 on white is 1.9:1 — completely unusable under any visual impairment and inaccessible even at normal vision. This is a WCAG hard failure on a core content element.
- The bookmark icon in `_ActionIcon` uses only a `GestureDetector` with `Semantics(button: true)`, not an `InkWell`. The tap target is `Padding(all: 4)` + a 20px icon = 28×28pt total. WCAG 2.5.5 requires 44×44pt minimum. Sam's motor precision is limited and will miss this target frequently.
- Color is the only indicator of read vs unread state in the icon (full color vs alpha 0.4). Sam, using screen reader, would rely on the existing semantic hints — but a sighted user with color vision deficiency has no non-color cue.

**Jordan (Confused First-Timer)**
- Lands on the app, sees "No feeds found" — no explanation of what a feed is, no guidance to add one, no link to help.
- Looks at the bottom bar: four icons. Taps the folder icon because it looks like "files." Arrives at Folders. Looks at the bottom bar again: still four icons, one is selected. Still cannot name the other three without tapping each.
- Discovers the FAB labeled "Add Feed" — but this label is displayed in English regardless of Jordan's device locale. If Jordan's phone is in Turkish or Spanish, the button text is still English.
- Swipe-to-bookmark gesture: Jordan will never discover this. Not through accident, not through exploration, not through any hint in the UI.

**Casey (Distracted Mobile User)**
- The FAB is center-docked at the bottom. This is thumb-zone accessible — good. However at 80×80dp it is very large, and the border+shadow combination makes it visually heavy in the bottom bar.
- If Casey is interrupted mid-swipe, the snap-back animation runs correctly. State is preserved. This works.
- The AppBar search field requires tapping an icon to open, then typing. On a one-handed phone interaction, the top-right search icon is borderline reachable. Once in search, the history suggestions are displayed as a full panel below the AppBar — this pushes content down rather than overlaying, which is correct for one-handed use.

## Minor Observations

- `home_screen.dart:465` — inline Turkish comment (`// Çizgiyi belirginleştirmek için kalınlığı 2 yaptım`) in an otherwise English codebase. Fine for a personal project, but inconsistent.
- `_FeedItemIcon` uses both a `Border.all(color: onSurface.alpha(0.08), width: 0.5)` AND the item's background color. The 0.5px border at 8% opacity is decorative and invisible in most conditions. Remove it.
- `_formatDate` returns `'${d.month}/${d.day}'` for dates older than 7 days. This is M/D format, which is US-centric. Most locales expect D/M or use abbreviated month names.
- The `SizedBox(width: 8)` at `home_screen.dart:398` adds trailing padding after the AppBar actions area but before the edge. On iOS with safe area insets, this can cause the search/visibility icon to feel slightly off-center relative to the back gesture zone.
- Swipe background icon size jumps from 28 to 32 when `actionTriggered` — a single-frame size change that reads as a pop, not an animation. Animate this with an `AnimatedContainer` or interpolate the size with the drag extent.

## Questions to Consider

- "The unread dot, bold weight, and left border all signal the same state. Which two would you remove if you had to keep only one signal?"
- "If a first-time user's most important action in their first 30 seconds is adding a feed, what would the empty state look like if it were designed for that goal rather than as a fallback?"
- "The nav tab labels disappear when unselected. What was the intended behavior — are users expected to memorize which icon is which, or was the label hiding an accident?"
