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
- [x] **OPML Export / Import**: Allow users to backup or restore their feed subscriptions via OPML files. Export shares an `.opml` file via the system share sheet; Import opens a file picker to load `.opml`/`.xml` files. Both nested (category folders) and flat OPML structures are supported. Duplicate feeds are skipped on import.
- [x] **Pagination / Infinite Scroll**: Replaced the fake 70/30 split with real date-based sections (Today / Yesterday / Older). `FeedProvider` now exposes `olderItems`, `isLoadingMore`, and `hasMoreItems`. The home screen uses a `NotificationListener` for automatic infinite scroll and a `_PaginationFooter` widget that shows a spinner while loading, a "Load more" fallback button, and a "You're all caught up" message when all items are rendered. The render limit resets to 50 on every filter/category/search change.
- [x] **Custom Category Management**: Users can add/delete/rename feed categories in the Folders tab. A FAB with a folder icon opens an "Add Folder" dialog with duplicate validation. Each feed has a move icon to reassign it to a different folder via a selection dialog. Empty folders are supported via a separate `_customCategories` set persisted in Hive. All strings are localized in English and Turkish.
- [x] **In-App Browser**: Implemented `InAppBrowser` widget (`lib/widgets/in_app_browser.dart`) using `webview_flutter`. Opens as a full-screen modal route with: a linear progress indicator while loading, dynamic page title in the AppBar, back/forward/refresh/share controls in a bottom bar, and an "Open in External Browser" button. The `ArticleScreen` "Open in Browser" AppBar button and "Read on Original Webpage" button both now open the in-app browser. In-content HTML links also open in the in-app browser.
- [x] **Internationalization (i18n)**: Implemented `flutter_localizations` with English and Turkish translations. Created ARB files (`app_en.arb`, `app_tr.arb`), configured `l10n.yaml`, wired up `MaterialApp` with localization delegates, added locale persistence to `SettingsProvider`, and made the Language dropdown functional. Users can now switch between English and Turkish.
- [x] **Notifications**: Implemented local OS notifications when the background sync finds new unread articles. Uses `flutter_local_notifications` package with Android 13+ (POST_NOTIFICATIONS) permission handling and iOS permission prompts. Notifications are triggered from `FeedProvider.refreshAll()` by diffing old vs new items and filtering by per-feed settings.
  - [x] **Per-Feed Controls**: Each feed has a notification bell toggle in the Folders screen. Feeds with notifications disabled are excluded from notification triggers via `notificationsEnabled` field on `FeedSubscription`.
  - [x] **Digest Mode**: Settings screen offers Instant / Daily Summary / Weekly Summary modes. Non-instant modes suppress real-time notifications.
  - [x] **Quiet Hours**: Settings screen provides start/end hour pickers (defaults 22:00–07:00). Notifications are suppressed during quiet hours including midnight-wrapping ranges.
- [x] **Font & Display Customization**: Enhance readability settings beyond basic themes.
  - [x] Allow font size adjustment (Small, Medium, Large, XL).
  - [x] Allow typeface selection (Serif, Sans-Serif, Mono).
  - [x] Allow line spacing adjustments in the Article View.
- [x] **Keyword Filtering (Rule-Based)**: Simple string matching to filter content (No AI).
  - [x] Exclude articles containing specific words (e.g., "spoiler", "ad").
  - [x] Apply filters per feed or globally.
- [x] **Full-Text Extraction**: Handle feeds that only provide excerpts.
  - [x] Implement heuristic scraping to fetch full content from the original URL if RSS body is truncated.
  - [x] Add toggle to enable/disable this feature per feed (to respect bandwidth).
- [x] **Search History**: Improve search usability.
  - [x] Save past search queries locally.
  - [x] Allow clearing search history in settings.
- [x] **Accessibility Improvements**: Ensure app is usable by everyone.
  - [x] Ensure all buttons have semantic labels for Screen Readers (VoiceOver/TalkBack).
  - [x] Add High Contrast Mode option in themes.
  - [x] Respect system "Reduced Motion" settings to disable animations.
- [x] **Developer Utilities**: Improve maintainability.
  - [x] Hidden debug screen (long press app version).
  - [x] Display Hive box sizes and background sync status.
  - [x] Show last sync duration metrics.
- [x] **Reading Experience Improvements**: Improve comfort and flow while consuming content.
  - [x] Swipe left/right to navigate between articles.
  - [x] Add reading progress indicator in Article View.
  - [x] Show estimated reading time under article title.

## Missing / Pending Features
- [ ] **Testing**: Write comprehensive unit tests for the providers and widget tests for the UI components.
- [ ] **Text-to-Speech (TTS)**: Integrate native OS TTS engines to allow users to listen to articles.
  - [ ] Add play/pause/speed controls in the Article View.
  - [ ] Ensure TTS stops when leaving the article screen.
- [ ] **Reading Statistics**: Track user engagement without compromising privacy.
  - [ ] Track articles read per day/week.
  - [ ] Track time spent reading.
  - [ ] Display "Most Active Feeds" in a dedicated Stats screen.
- [ ] **Media Caching**: Enhance offline experience for images.
  - [ ] Preload and cache images from RSS feeds locally.
  - [ ] Option to disable images to save data in `SettingsProvider`.
- [ ] **Article Tagging**: Extend bookmarking functionality.
  - [ ] Allow users to add custom tags to bookmarked articles.
  - [ ] Filter bookmark view by tags.
- [ ] **External Integrations**: Share content to third-party read-later services.
  - [ ] Implement "Send to Pocket" API integration.
  - [ ] Implement "Send to Instapaper" API integration.
- [ ] **Home Screen Widgets**: Provide quick access from the OS home screen.
  - [ ] Create widget showing latest unread count.
  - [ ] Create widget showing latest article titles from specific feeds.

- [ ] **Feed Organization Enhancements**: Improve subscription management.
  - [ ] Pin favorite feeds to top of folder.
  - [ ] Manual drag-and-drop feed reordering.
  - [ ] Bulk feed actions (delete, move, toggle notifications).
  - [ ] Per-folder notification toggle.
  - [ ] Feed health indicator based on last sync result.

- [ ] **Performance & Data Controls**: Improve efficiency and offline behavior.
  - [ ] Smart cache cleanup with configurable retention period.
  - [ ] Manual "Clear Cache" button (without removing subscriptions).
  - [ ] Low Data Mode (disable images, reduce sync frequency, disable full-text extraction).
  - [ ] Tap-to-zoom image viewer in Article View.

- [ ] **Notification Improvements**: Expand interaction capabilities.
  - [ ] Add action buttons (Mark as Read / Open) to notifications.
  - [ ] App icon unread badge count (where supported).
  - [ ] Optional per-feed custom notification sounds.

- [ ] **Search & Discovery Enhancements**: Improve content filtering.
  - [ ] Advanced search filters (date range, specific feed, unread only, bookmarked only).
  - [ ] Saved searches with quick-access chips.
  - [ ] Highlight matched search terms inside articles.

- [ ] **Reading Management Enhancements**: Better control over saved content.
  - [ ] Reading Queue separate from bookmarks.
  - [ ] Archive system for read items.
  - [ ] Export bookmarks as JSON / Markdown / HTML.

- [ ] **UI Customization & Visual Improvements**: Improve perceived polish.
  - [ ] Compact mode for denser feed list layout.
  - [ ] Toggle to show/hide thumbnails in feed list.
  - [ ] Accent color customization.
  - [ ] Skeleton loaders instead of spinners (respect Reduced Motion).

- [ ] **Navigation Improvements**: Reduce friction in daily use.
  - [ ] Bottom navigation tab reordering.
  - [ ] Quick jump-to-top floating button.
  - [ ] Double-tap Home tab to refresh feeds.

- [ ] **Privacy & Transparency Enhancements**: Improve user trust.
  - [ ] Sync log screen showing last sync time and errors per feed.
  - [ ] Display local storage usage and cached article count.


---
## 📝 Notes for Agents
- When implementing **Notifications**, ensure proper permission handling for Android 13+ (POST_NOTIFICATIONS).
- For **Text-to-Speech**, use the `flutter_tts` package or native platform channels.
- For **Statistics**, store data in a separate Hive box to avoid bloating the main feed box.
- Always update this file when a task moves from Pending to Completed.