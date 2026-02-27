# AI Agent Task List

This document is a persistent living record for AI coding agents to understand what features have been completed and what features are still pending or missing. Agents should update this file as they complete tasks.

## Completed Features
- [x] **Project Scaffolding**: Setup Flutter project and UI architecture.
- [x] **State Management Refactor**: Split the monolithic `FeedProvider` into `SettingsProvider`, `SubscriptionProvider`, `BookmarkProvider`, and a streamlined `FeedProvider`.
- [x] **Local Persistence**: Implemented Hive (`hive_ce`) for offline storage of bookmarks, subscriptions, app settings, and cached feed items.
- [x] **RSS/Atom Parsing**: Custom parsing and HTML decoding integrated. Includes edge cases like thumbnail extraction from `<content>` or `<media:thumbnail>` tags.
- [x] **Background Sync**: Polling timer implemented depending on `cacheIntervalSeconds` and `syncBackground` settings.
- [x] **Cloudflare Bypass**: Included specific browser emulation headers inside `FeedService` to successfully fetch from restricted endpoints like Anime Trending.
- [x] **Dark/Light Theme**: Theme switching tied to `SettingsProvider` and Hive persistence.
- [x] **GitLab CI/CD**: Added `.gitlab-ci.yml` template to automatically build Android `app-release.apk` on every push.

## Missing / Pending Features
- [x] **OPML Export / Import**: Allow users to backup or restore their feed subscriptions via OPML files. Export shares an `.opml` file via the system share sheet; Import opens a file picker to load `.opml`/`.xml` files. Both nested (category folders) and flat OPML structures are supported. Duplicate feeds are skipped on import.
- [ ] **Notifications**: Implement local OS notifications when the background sync finds new unread articles.
- [x] **Pagination / Infinite Scroll**: Replaced the fake 70/30 split with real date-based sections (Today / Yesterday / Older). `FeedProvider` now exposes `olderItems`, `isLoadingMore`, and `hasMoreItems`. The home screen uses a `NotificationListener` for automatic infinite scroll and a `_PaginationFooter` widget that shows a spinner while loading, a "Load more" fallback button, and a "You're all caught up" message when all items are rendered. The render limit resets to 50 on every filter/category/search change.
- [x] **Custom Category Management**: Users can add/delete/rename feed categories in the Folders tab. A FAB with a folder icon opens an "Add Folder" dialog with duplicate validation. Each feed has a move icon to reassign it to a different folder via a selection dialog. Empty folders are supported via a separate `_customCategories` set persisted in Hive. All strings are localized in English and Turkish.
- [x] **In-App Browser**: Implemented `InAppBrowser` widget (`lib/widgets/in_app_browser.dart`) using `webview_flutter`. Opens as a full-screen modal route with: a linear progress indicator while loading, dynamic page title in the AppBar, back/forward/refresh/share controls in a bottom bar, and an "Open in External Browser" button. The `ArticleScreen` "Open in Browser" AppBar button and "Read on Original Webpage" button both now open the in-app browser. In-content HTML links also open in the in-app browser.
- [x] **Internationalization (i18n)**: Implemented `flutter_localizations` with English and Turkish translations. Created ARB files (`app_en.arb`, `app_tr.arb`), configured `l10n.yaml`, wired up `MaterialApp` with localization delegates, added locale persistence to `SettingsProvider`, and made the Language dropdown functional. Users can now switch between English and Turkish.
- [ ] **Testing**: Write comprehensive unit tests for the providers and widget tests for the UI components.
