# Dondurma RSS Reader

## Project Overview
A modern Flutter RSS/Atom feed reader with Material 3 UI, Catppuccin themes, offline caching, background sync, local notifications, and full internationalization (English & Turkish).

## Architecture
- **State Management**: `provider` package with 5 providers
- **Persistence**: Hive CE (`hive_ce` / `hive_ce_flutter`) with 3 boxes
- **Routing**: GoRouter with declarative routes

## Providers
| Provider | Purpose |
|----------|---------|
| `FeedProvider` | Feed fetching, filtering, pagination, caching, notifications. Uses `ChangeNotifierProxyProvider3` to depend on other providers |
| `SubscriptionProvider` | Feed subscriptions, categories, custom categories with icons |
| `BookmarkProvider` | Saved articles with full JSON and ID set persistence |
| `SettingsProvider` | Theme, locale, cache, sync, notifications, display settings |
| `ArticlePageProvider` | Per-article scroll state, full-text extraction, reading progress |

## Models
- [`FeedItem`](lib/models/feed_item.dart) — Article/entry with JSON serialization, copyWith
- [`FeedSubscription`](lib/models/feed_subscription.dart) — Feed source with url, name, category, notifications, full-text, excluded keywords

## Hive Boxes
- **`'settings'`** — Theme, locale, cache limit, sync interval, notification settings, ad block, webview mode
- **`'feeds'`** — Subscriptions, custom categories, cached items, read IDs, category icons
- **`'bookmarks'`** — Bookmarked items (JSON + ID set)

## Core Services
- [`FeedService`](lib/services/feed_service.dart) — HTTP fetch with browser UA, RSS/Atom parsing via `dart_rss`
- [`FullTextExtractionService`](lib/services/full_text_extraction_service.dart) — Heuristic content extraction for excerpt-only feeds
- [`NotificationService`](lib/services/notification_service.dart) — Singleton wrapper for `flutter_local_notifications`, quiet hours, digest modes
- [`OpmlService`](lib/services/opml_service.dart) — OPML export/import via `xml` package

## Routes
- `/` → HomeScreen (bottom nav: Feeds/Folders/Bookmarks/Settings)
- `/article` → ArticleScreen (PageView with swipe navigation)
- `/debug` → DebugScreen (developer utilities)

## Key Dependencies
```
provider, hive_ce, hive_ce_flutter, http, dart_rss, html,
flutter_html, catppuccin_flutter, google_fonts (Outfit),
go_router, webview_flutter, adblocker_webview,
flutter_local_notifications, file_picker, share_plus,
xml, intl, flutter_localizations
```

## Key Features
- **Swipe Gestures**: Right = read/unread, Left = bookmark
- **Pagination**: Date-based sections (Today/Yesterday/Older), `_pageSize = 50`
- **In-App Browser**: WebView with ad blocking toggle
- **Theme**: 9 options (System/Light/Dark/4 Catppuccin/2 High Contrast)
- **Offline Banner**: Shows when viewing cached content
- **Background Sync**: Timer-based with configurable interval

## Important Patterns
- FeedProvider first load (`_hasLoadedOnce == false`) doesn't trigger notifications
- Categories from subscriptions + `_customCategories` merged in `categories` getter
- `NotificationService.isSupported` returns `false` on unsupported platforms
- Per-feed `excludedKeywords` for filtering unwanted articles
- Per-feed `fullTextEnabled` to extract full article content
- Browser mode: `'builtin'` | `'external'` | `'system'`

## Common Gotchas
- Always use fallback defaults in JSON deserialization for backward compatibility
- `_manageCacheTimer()` recreates timer on proxy provider updates
- Category icons stored separately in Hive, assigned on first load
- Generated localization files in `lib/l10n/app_localizations*.dart` — do not edit manually
