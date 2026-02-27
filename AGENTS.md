# Dondurma RSS Reader

## Project Overview
Dondurma RSS Reader is a modern, responsive RSS/Atom feed reader mobile application built with Flutter. It focuses on a clean UI (utilizing Catppuccin themes, Google Fonts Outfit typeface, and Material 3) and provides caching for offline reading, a background synchronization mechanism, robust feed parsing, local notifications, and full internationalization (English & Turkish).

## Architecture & State Management
The application uses the `provider` package for state management, broken down into four distinct providers to maintain performance and readability:

- **`FeedProvider`**: Handles fetching, search, filtering (unread/read, category, per-feed), date-based sectioning (Today/Yesterday/Older), and paginated rendering. Manages background cache timers and triggers notification diffing on refresh. Depends on the other three providers via `ChangeNotifierProxyProvider3`.
- **`SubscriptionProvider`**: Manages the user's RSS feed sources and their categories. Supports standalone empty categories via `_customCategories` persisted in Hive. Provides add/remove/rename/move operations for feeds and categories, per-feed notification toggling, and bulk import.
- **`BookmarkProvider`**: Keeps track of items the user has saved for later. Persists both a full JSON representation of bookmarked `FeedItem`s and an ID set for backward compatibility.
- **`SettingsProvider`**: Manages global application settings including Theme selection (System/Light/Dark/4 Catppuccin flavors), Offline Cache Limit, Auto-Refresh background intervals, Locale persistence, and Notification settings (master toggle, digest mode, quiet hours).

Dependencies between providers are managed in `main.dart` using `MultiProvider` and `ChangeNotifierProxyProvider3`.

## Project Structure
```
lib/
├── main.dart                         # App entry: Hive init, notification init, MultiProvider, MaterialApp.router
├── l10n/                             # Internationalization
│   ├── app_en.arb                    # English strings (template)
│   ├── app_tr.arb                    # Turkish strings
│   ├── app_localizations.dart        # Generated localization delegate
│   ├── app_localizations_en.dart     # Generated English
│   └── app_localizations_tr.dart     # Generated Turkish
├── models/
│   ├── feed_item.dart                # FeedItem model with JSON serialization, copyWith, dummy data
│   └── feed_subscription.dart        # FeedSubscription model (url, name, category, notificationsEnabled)
├── providers/
│   ├── feed_provider.dart            # Core feed state, caching, pagination, notifications
│   ├── subscription_provider.dart    # Subscription CRUD, category management, OPML import
│   ├── bookmark_provider.dart        # Bookmark state with Hive persistence
│   └── settings_provider.dart        # Theme, locale, cache, sync, notification settings
├── screens/
│   ├── home_screen.dart              # Main screen with bottom nav (Home/Folders/Bookmarks/Settings)
│   ├── article_screen.dart           # Full article view with HTML rendering, in-app browser links
│   ├── folders_screen.dart           # Folder/category management with feed CRUD
│   ├── bookmarks_screen.dart         # Saved articles list
│   ├── settings_screen.dart          # All settings including notifications, theme, OPML, cache
│   └── subscriptions_screen.dart     # Flat feed list management (legacy, available via drawer)
├── services/
│   ├── feed_service.dart             # HTTP fetching with browser UA headers, RSS/Atom parsing
│   ├── notification_service.dart     # flutter_local_notifications singleton, quiet hours, digest modes
│   └── opml_service.dart             # OPML generation, parsing (regex-based), file export/import
├── theme/
│   └── app_theme.dart                # AppTheme enum, ThemeData builders (Light/Dark/4 Catppuccin)
├── router/
│   └── app_router.dart               # GoRouter with `/` (HomeScreen) and `/article` routes
└── widgets/
    ├── feed_list_item.dart           # Swipeable feed card with read/bookmark gestures
    ├── add_feed_dialog.dart          # Dialog for adding new feed subscriptions
    ├── explore_feeds_dialog.dart     # Remote suggested feeds browser with category filtering
    ├── app_drawer.dart               # Navigation drawer with expandable categories
    └── in_app_browser.dart           # WebView-based in-app browser with nav controls
```

### Other Notable Files
- `remote_data/suggested_feeds.json` — curated list of suggested feeds loaded by `ExploreFeedsDialog`
- `l10n.yaml` — localization generation config (`nullable-getter: false`)
- `analysis_options.yaml` — uses `package:flutter_lints/flutter.yaml`
- `.gitlab-ci.yml` — CI/CD template for Android APK builds
- `assets/data/` & `assets/logo.ico` — app assets

## Local Persistence
Data persistence is handled by **Hive** (`hive_ce` / `hive_ce_flutter`) using **three dedicated boxes** for clean separation. A one-time migration in `main.dart` moves data from the legacy single-box layout into the new boxes.

### `'settings'` box — App preferences
| Key | Type | Description |
|-----|------|-------------|
| `selectedTheme` | String | AppTheme enum name |
| `offlineCacheLimit` | int | Max items to persist for offline |
| `cacheIntervalSeconds` | int | Background sync interval |
| `syncBackground` | bool | Enable/disable auto-refresh |
| `locale` | String | Language code (`en` / `tr`) |
| `notificationsEnabled` | bool | Master notification toggle |
| `digestMode` | String | `instant` / `daily` / `weekly` |
| `quietHoursStart` | int | Hour (0-23) when quiet begins |
| `quietHoursEnd` | int | Hour (0-23) when quiet ends |
| `_boxesMigrated` | bool | Internal migration flag |

### `'feeds'` box — Subscriptions & cached articles
| Key | Type | Description |
|-----|------|-------------|
| `subscriptions` | JSON string | Feed subscription list |
| `custom_categories` | JSON string | Standalone empty category names |
| `cachedItemsJson` | JSON string | Offline-cached feed items |
| `readItemIds` | List<String> | Read article IDs |

### `'bookmarks'` box — Saved articles
| Key | Type | Description |
|-----|------|-------------|
| `bookmarkedItemsJson` | JSON string | Full bookmarked FeedItem data |
| `bookmarkedItemIds` | List<String> | Bookmark ID set (backward compat) |

## Core Services
- **`FeedService`** (`lib/services/feed_service.dart`): Uses the `http` package, emulating browser User-Agent headers to bypass Cloudflare 403 challenges. Attempts RSS parsing with `dart_rss` first, falls back to Atom. Custom HTML entity decoding and image extraction from `<content>`, `<description>`, `<enclosure>`, and `<media:thumbnail>` tags.
- **`NotificationService`** (`lib/services/notification_service.dart`): Singleton wrapping `flutter_local_notifications`. Supports Android, iOS, and macOS. Exposes `isSupported` getter for platform detection. Includes quiet hours logic with midnight-wrapping support.
- **`OpmlService`** (`lib/services/opml_service.dart`): Handles OPML export via `share_plus` and import via `file_picker`. Uses the `xml` package for proper XML generation (via `XmlBuilder`) and parsing (via `XmlDocument.parse`). Supports both nested (category folders) and flat OPML structures.

## Key Features
- **Custom Category Management**: Add/rename/delete folders from the Folders tab. Move individual feeds between categories. Empty folders supported via custom categories.
- **In-App Browser**: Full-screen WebView (Android/iOS/macOS) with progress indicator, back/forward/refresh/share controls, and external browser fallback for unsupported platforms.
- **Pagination / Infinite Scroll**: Date-based sections (Today/Yesterday/Older) with automatic scroll-based loading (`_pageSize = 50`). Render limit resets on filter changes.
- **OPML Export/Import**: Backup/restore feed subscriptions via system share sheet and file picker.
- **Internationalization**: English and Turkish with locale persistence. All UI strings use `AppLocalizations`.
- **Notifications**: Local OS notifications for new articles with per-feed toggles, digest mode (instant/daily/weekly), and quiet hours (midnight-wrapping).
- **Offline Banner**: Shows when users are viewing cached articles after all fetches fail.
- **Swipe Gestures**: Swipe right to toggle read/unread, swipe left to toggle bookmark — with haptic feedback and animation.
- **Theme System**: 7 theme options (System/Light/Dark + 4 Catppuccin flavors) using Material 3 and Google Fonts Outfit.
- **Explore Feeds**: Remote curated feed list with category badge filtering.

## Dependencies (pubspec.yaml)
| Package | Purpose |
|---------|---------|
| `provider` | State management |
| `hive_ce` / `hive_ce_flutter` | Local persistence |
| `http` | Network requests |
| `dart_rss` | RSS/Atom feed parsing |
| `html` | HTML parsing & entity decoding |
| `flutter_html` | Rich HTML rendering in article view |
| `cached_network_image_ce` | Image caching with placeholders |
| `catppuccin_flutter` | Catppuccin color palette theming |
| `google_fonts` | Outfit typeface |
| `go_router` | Declarative routing |
| `webview_flutter` | In-app browser |
| `flutter_local_notifications` | OS-level notifications |
| `file_picker` | OPML import file selection |
| `share_plus` | OPML export sharing |
| `path_provider` | Temp directory for OPML export |
| `url_launcher` | External browser fallback |
| `intl` | Date formatting & RFC 822 parsing |
| `xml` | OPML XML generation & parsing |
| `flutter_localizations` | Material/Cupertino i18n delegates |

## Common Workflow & Gotchas
- **Adding newly fetched data**: Ensure feeds map back to the universal `FeedItem` model cleanly. Both RSS and Atom parsers produce the same `FeedItem` structure.
- **Background Sync**: Depends on `syncBackground` boolean and `cacheIntervalSeconds`. Timer is recreated via `_manageCacheTimer()` on every proxy provider update. The first load (`_hasLoadedOnce == false`) does not trigger notifications.
- **Missing or invalid data cache**: When altering cached structure rules (like removing values from dropdown options), always incorporate a fallback/default state in the load logic to prevent assertion crashes. See `SettingsProvider._loadSettings()` for the `cacheIntervalSeconds` fallback pattern.
- **Category persistence**: Categories come from two sources — feed subscriptions and `_customCategories`. Both are merged in the `categories` getter.
- **Notification platform support**: `NotificationService.isSupported` returns `false` on desktop platforms where the plugin fails to initialize. Settings screen uses this to disable notification controls with a warning card.
- **Generated localization files**: `lib/l10n/app_localizations*.dart` are auto-generated from ARB files via `flutter gen-l10n`. Do not edit them manually. Configuration is in `l10n.yaml`.
- **Hive box migration**: On first launch after the box-split update, `_migrateHiveBoxes()` in `main.dart` automatically moves keys from the old `'settings'` box to `'feeds'` and `'bookmarks'`. The `'_boxesMigrated'` flag prevents re-runs.
