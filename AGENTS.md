# Dondurma Rss Reader
## Project Overview
Dondurma Rss Reader is a modern, responsive RSS/Atom feed reader mobile application built with Flutter. It focuses on a clean UI (utilizing Catppuccin themes) and provides caching for offline reading, a background synchronization mechanism, and robust feed parsing.

## Architecture & State Management
The application uses the `provider` package for state management, which has been broken down into several distinct providers to maintain performance and readability:
- **`FeedProvider`**: Handles fetching, searching, and filtering of feeds (unread/read state). Connects to background cache timers.
- **`SubscriptionProvider`**: Manages the user's RSS feed sources and their categories. Supports standalone empty categories via `_customCategories` persisted in Hive.
- **`BookmarkProvider`**: Keeps track of items the user has saved for later.
- **`SettingsProvider`**: Manages global application settings like Theme (Dark/System), Offline Cache Limit, and Auto-Refresh background intervals.

Dependencies between providers are managed in `main.dart` using `MultiProvider` and `ChangeNotifierProxyProvider`.

## Local Persistence
Data persistence is handled by **Hive** (`hive_ce` / `hive_ce_flutter`).
- Settings, local read states, and offline cached feeds are stored in a Hive box named `'settings'`.
- Bookmarks and subscription data are persisted across app sessions via their dedicated providers.
- Custom (empty) categories are stored under the `'custom_categories'` key.

## Core Services
- **`FeedService`**: Found in `lib/services/feed_service.dart`. Uses the `http` package, mimicking browser User-Agent headers to bypass restrictive Cloudflare 403 challenges from popular XML endpoints.
- **Parsing**: Uses `dart_rss` to parse both RSS and Atom structures. Custom logic and the `html` library are used to aggressively decode stray HTML entities (like `&#8216;`) and extract thumbnail images from feed item `content` or `description`.
- **`OpmlService`**: Found in `lib/services/opml_service.dart`. Handles OPML export/import for feed subscriptions.

## Key Features
- **Custom Category Management**: Users can add/rename/delete feed folders from the Folders tab. Feeds can be moved between categories. Empty folders are supported via standalone custom categories.
- **In-App Browser**: Full-screen WebView for reading articles with back/forward/refresh/share controls.
- **Pagination / Infinite Scroll**: Date-based sections (Today / Yesterday / Older) with automatic infinite scroll.
- **OPML Export/Import**: Backup and restore feed subscriptions.
- **Internationalization**: English and Turkish, with locale persistence.
- **Offline Banner**: Notifies users when cached articles are displayed.

## Common Workflow & Gotchas
- **Adding newly fetched data**: Ensure feeds map back to the universal `FeedItem` model cleanly.
- **Background Sync**: Depends on `syncBackground` boolean and `cacheIntervalSeconds`. Runs automatically as long as the app is open depending on the settings.
- **Missing or invalid data cache**: When altering cached structure rules (like removing "0" from interval settings dropdowns), always incorporate a fallback/default state in the load logic to prevent `DropdownMenuItem` assertion crashes.
- **Category persistence**: Categories come from two sources — subscriptions and `_customCategories`. Both are merged in the `categories` getter.
