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
- [ ] **Pagination / Infinite Scroll**: The `todayItems` and `yesterdayItems` getters are mocked with simple limits (`_itemRenderLimit`). A more robust pagination mechanism could be added.
- [ ] **Custom Category Management**: Allow users to add/delete/rename feed categories inside a dedicated "Manage Folders" screen.
- [ ] **In-App Browser**: Opening articles currently pushes them out; could implement an integrated `webview_flutter` modal to read source articles without leaving the app.
- [ ] **Internationalization (i18n)**: Prepare strings and implement `flutter_localizations`. The Language setting is currently an inactive dropdown.
- [ ] **Testing**: Write comprehensive unit tests for the providers and widget tests for the UI components.
