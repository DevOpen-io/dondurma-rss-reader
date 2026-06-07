# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication Style

Use caveman skill. Terse responses. Drop filler, articles, hedging. Fragments OK. Technical terms exact. Code unchanged.

**Prefer MCP over raw terminal** for tooling — especially **Dart/Flutter**: use the configured Dart MCP server (analysis, fixes, project queries) before defaulting to CLI-only workflows when the MCP tool covers the task.

**Prefer TDD when practical:** write or adjust failing tests first for new behavior or bug fixes, then implement until green; skip only where a test would not add signal (e.g. pure UI snapshot churn) — default bias is test-first.

- use superpowers 
- **Subagent-driven development** for implementation plans with independent tasks — use `superpowers:subagent-driven-development` skill.
- **MCP over CLI** for Dart/Flutter tooling (analysis, fixes, project queries) when the MCP tool covers the task.
- dont use git commands.
- **UI/UX Excellence:** Exhibit impeccable skill in frontend design. Deliver modern, polished, and pixel-perfect layouts with exceptional attention to spacing, typography, and visual hierarchy.
- dont use git commands.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## Architecture

**State management**: 5 `ChangeNotifier` providers wired in `main.dart` via `MultiProvider`. `FeedProvider` depends on the other three via `ChangeNotifierProxyProvider3` — it receives `SubscriptionProvider`, `SettingsProvider`, and `BookmarkProvider` through its `update()` method.

**Persistence**: Hive CE with 3 boxes opened at startup:
- `'settings'` — theme, locale, sync interval, notification config, ad blocker, browser mode
- `'feeds'` — subscriptions, custom categories, cached feed items, read IDs, category icons
- `'bookmarks'` — bookmarked items (JSON + ID set)

A one-time migration in `_migrateHiveBoxes()` moves legacy keys from `'settings'` into the dedicated boxes.

**Routing**: GoRouter with 3 routes: `/` (HomeScreen with bottom nav), `/article` (ArticleScreen with PageView swipe), `/debug` (DebugScreen).

**Localization**: ARB files in `lib/l10n/` (`app_en.arb`, `app_tr.arb`). Generated files (`app_localizations*.dart`) are committed — do not edit them manually; run `flutter gen-l10n` after changing ARB files.

## Key Patterns

- `FeedProvider._hasLoadedOnce` gates notification dispatch — first load never triggers notifications.
- Categories = subscriptions' category fields + `_customCategories` set, merged in `SubscriptionProvider.categories` getter.
- `NotificationService` is a singleton; `isSupported` returns `false` on platforms without notification support.
- Per-feed `excludedKeywords` filtering happens inside `FeedProvider` before exposing items.
- Browser mode is a string: `'builtin'` | `'external'` | `'system'`.
- `_manageCacheTimer()` in `FeedProvider` recreates the background sync timer each time the proxy provider fires an update.
- Category icons are stored separately in Hive and assigned on first load from `SubscriptionProvider`.

## Gotchas

- Always provide fallback defaults in Hive/JSON deserialization — fields may be absent in older persisted data.
- The `lib/l10n/app_localizations*.dart` files are auto-generated; only edit `app_en.arb` and `app_tr.arb`.
- When adding a new Hive key to `'feeds'` or `'bookmarks'`, check whether it needs a migration path in `_migrateHiveBoxes()`.
- `FeedProvider` uses date-based pagination (`_pageSize = 50`); the page limit resets on every filter/category/search change.
- `NotificationService.requestPermission()` and `AdBlockerWebviewController.initialize()` run in the background after `runApp` — they are intentionally not awaited.


