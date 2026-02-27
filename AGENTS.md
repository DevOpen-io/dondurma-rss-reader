# Ice Cream Reader
## Project Overview
Ice Cream Reader is a modern, responsive RSS/Atom feed reader mobile application built with Flutter. It focuses on a clean UI (utilizing Catppuccin themes) and provides caching for offline reading, a background synchronization mechanism, and robust feed parsing.

## Architecture & State Management
The application uses the `provider` package for state management, which has been broken down into several distinct providers to maintain performance and readability:
- **`FeedProvider`**: Handles fetching, searching, and filtering of feeds (unread/read state). Connects to background cache timers.
- **`SubscriptionProvider`**: Manages the user's RSS feed sources and their categories.
- **`BookmarkProvider`**: Keeps track of items the user has saved for later.
- **`SettingsProvider`**: Manages global application settings like Theme (Dark/System), Offline Cache Limit, and Auto-Refresh background intervals.

Dependencies between providers are managed in `main.dart` using `MultiProvider` and `ChangeNotifierProxyProvider`.

## Local Persistence
Data persistence is handled by **Hive** (`hive_ce` / `hive_ce_flutter`).
- Settings, local read states, and offline cached feeds are stored in a Hive box named `'settings'`.
- Bookmarks and subscription data are persisted across app sessions via their dedicated providers.

## Core Services
- **`FeedService`**: Found in `lib/services/feed_service.dart`. Uses the `http` package, mimicking browser User-Agent headers to bypass restrictive Cloudflare 403 challenges from popular XML endpoints.
- **Parsing**: Uses `dart_rss` to parse both RSS and Atom structures. Custom logic and the `html` library are used to aggressively decode stray HTML entities (like `&#8216;`) and extract thumbnail images from feed item `content` or `description`.

## Common Workflow & Gotchas
- **Adding newly fetched data**: Ensure feeds map back to the universal `FeedItem` model cleanly.
- **Background Sync**: Depends on `syncBackground` boolean and `cacheIntervalSeconds`. Runs automatically as long as the app is open depending on the settings.
- **Missing or invalid data cache**: When altering cached structure rules (like removing "0" from interval settings dropdowns), always incorporate a fallback/default state in the load logic to prevent `DropdownMenuItem` assertion crashes.
