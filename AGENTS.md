# Dondurma RSS Reader

## Project Overview
A modern Flutter RSS/Atom feed reader with Material 3 UI, FlexColorScheme theming, offline caching, foreground + Workmanager background sync, local notifications, home-screen widgets, and full internationalization (English, Turkish, Spanish).

## Architecture
- **State Management**: `provider` package with 5 providers; `FeedProvider` wired via `ChangeNotifierProxyProvider3`
- **Persistence**: Hive CE (`hive_ce` / `hive_ce_flutter`) with 3 boxes
- **Routing**: GoRouter with declarative routes + onboarding redirect
- **Background work**: `workmanager` for sync when app is closed; `home_widget` for home-screen widgets

## Providers
| Provider | Purpose |
|----------|---------|
| `FeedProvider` | Feed fetching, filtering, pagination, caching, notifications. Uses `ChangeNotifierProxyProvider3` to depend on Subscription/Settings/Bookmark providers |
| `SubscriptionProvider` | Feed subscriptions, categories, custom categories with icons |
| `BookmarkProvider` | Saved articles with full JSON and ID set persistence |
| `SettingsProvider` | Theme (flexScheme), locale, cache, sync, notifications, display settings |
| `ArticlePageProvider` | Per-article scroll state, full-text extraction, reading progress |

## Models
- [`FeedItem`](lib/models/feed_item.dart) — Article/entry with JSON serialization, copyWith
- [`FeedSubscription`](lib/models/feed_subscription.dart) — Feed source with url, name, category, notifications, full-text, excluded keywords

## Hive Boxes
- **`'settings'`** — theme, locale, cache/sync, notifications, reading, filters/search, browser, `autoFullText`, onboarding, migration flag
- **`'feeds'`** — subscriptions, custom categories, cached items, read IDs, category icons/order, `feedValidators`; `bgKnownItemIds` is legacy migration evidence only
- **`'bookmarks'`** — Bookmarked items (JSON + ID set)

## Core Services
- [`FeedService`](lib/services/feed_service.dart) — HTTP fetch with browser UA + keep-alive client, RSS/Atom parsing via `dart_rss`, HTTP 304 (etag/last-modified) support, isolate-based `parseFeedBody`
- [`FullTextExtractionService`](lib/services/full_text_extraction_service.dart) — Heuristic content extraction, runs in isolate, shared 20-entry FIFO cache
- [`NotificationService`](lib/services/notification_service.dart) — Singleton wrapper for `flutter_local_notifications`, quiet hours, digest modes, launch payload → article navigation
- [`OpmlService`](lib/services/opml_service.dart) — OPML export/import via `xml` package
- [`BackgroundFetchService`](lib/services/background_fetch_service.dart) — Workmanager dispatcher with `@pragma('vm:entry-point')` callback; `NetworkType.connected`, 15-min minimum period; baseline-diffed notifications
- [`WidgetUpdateService`](lib/services/widget_update_service.dart) — home_widget data sync (`widget_latest` key, category grouping), App Group `group.io.devopen.dondurma`, deep-link `homewidget://article?id=<id>`
- [`ImageCacheService`](lib/services/image_cache_service.dart) — Article and thumbnail cache managers

## Routes
- `/onboarding` → OnboardingScreen (redirect target until `hasSeenOnboarding`)
- `/` → HomeScreen (bottom nav: Feeds/Folders/Bookmarks/Settings)
- `/article` → ArticleScreen (PageView with swipe navigation; receives `items` + `initialIndex` via `state.extra`)
- `/debug` → DebugScreen (developer utilities, hidden behind long-press on app version)

## Key Dependencies
```
provider, hive_ce, hive_ce_flutter, http, dart_rss, html,
flutter_html, flex_color_scheme, google_fonts (Outfit),
go_router, webview_flutter, adblocker_webview,
flutter_local_notifications, workmanager, home_widget,
cached_network_image_ce, skeletonizer, share_plus, url_launcher,
file_selector, package_info_plus, xml, intl, flutter_localizations
```

## Key Features
- **Swipe Gestures**: Right = read/unread, Left = bookmark
- **Pagination**: Date-based sections (Today/Yesterday/Older), `_pageSize = 50`, resets on filter/category/search change
- **In-App Browser**: WebView with ad blocking toggle (EasyList + AdGuard) and optional DarkReader injection
- **Theme**: 10 FlexColorScheme schemes × 3 brightness modes (System/Light/Dark); toast motion respects system animation preference
- **Offline Banner**: Shows when viewing cached content
- **Background Sync**: Foreground timer (configurable interval) + Workmanager when app is closed
- **Full-Text Extraction**: Per-feed toggle, heuristic reader-mode scraper in isolate
- **Keyword Filtering**: Per-feed `excludedKeywords` + global excluded keywords, regex compiled once per filter pass
- **Search History**: MRU list capped at 10, stored in settings
- **Onboarding**: Multi-step flow with suggested feeds, background blobs animation
- **Feedback**: Global modal-aware toast; replace-not-queue timing and reduced-motion support

## Important Patterns
- `FeedProvider._hasLoadedOnce` gates notification dispatch — first load never triggers notifications
- `ObservedArticleStore` owns feed+subscription-epoch scoped, 14-day observation history outside Hive cache; exclusive lock-file creation serializes foreground/Workmanager claims
- Notification settings affect delivery after claim; suppressed articles never backfill
- `FeedProvider.refreshAll()` coalesces concurrent requests (`_refreshQueued`) and limits parallel HTTP to 5 (`_fetchConcurrency`, semaphore)
- `FeedProvider.filterInputsChanged` (pure static gate) invalidates the filter cache only when global/per-feed keywords or bookmark IDs actually change — unrelated upstream updates don't rebuild the feed list
- Categories = subscriptions' category fields + `_customCategories` set, merged in `SubscriptionProvider.categories` getter
- `NotificationService.isSupported` returns `false` on unsupported platforms
- Per-feed `excludedKeywords` / `fullTextEnabled` fields on `FeedSubscription`
- `FeedSubscription.fullTextEnabled` is tri-state; `null` follows global `autoFullText`
- Browser mode: `'builtin'` | `'external'` | `'system'`
- App root uses `context.select` on `flexScheme`/`themeMode`/`locale` so unrelated settings changes don't rebuild MaterialApp
- `sessionOnboardingBypassed` (router/onboarding_state.dart) short-circuits the onboarding redirect
- Localization derived from `supportedAppLanguages` (EN/TR/ES); add a language via ARB file + one entry there

## Common Gotchas
- Always use fallback defaults in JSON deserialization for backward compatibility
- `_migrateHiveBoxes()` in `main.dart` is a one-time migration from the legacy single `'settings'` box; check it when adding new `'feeds'`/`'bookmarks'` keys
- `_manageCacheTimer()` recreates timer on proxy provider updates
- Category icons stored separately in Hive, assigned on first load; legacy emoji icons mapped to Material icons
- Generated localization files in `lib/l10n/app_localizations*.dart` — do not edit manually
- Tests cover parsing, fetch mechanics, filters, resume policy, feed rows, toast, responsive widths; extend changed behavior
- `NotificationService.requestPermission()` and `AdBlockerWebviewController.initialize()` run unawaited after `runApp`
- `Assets/Logo.png` is launcher-icon source only and must NOT be bundled (asset list covers `assets/logo.ico`, `assets/js/`)
