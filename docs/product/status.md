# Product Status and Backlog

Source comparison: 2026-10-26. Checked items describe implementation in the repository, not store approval or device verification. Source code wins when this file drifts.

[Product guide](guide.md) · [Technical roadmap](roadmap.md) · [Documentation index](../README.md)

## Implemented in the repository

- [x] RSS/Atom isolate parsing, browser headers, ETag/Last-Modified, HTTP 304
- [x] Five providers; three Hive CE boxes; legacy migration
- [x] Refresh coalescing, five-request concurrency, resume refresh, 50-item pagination
- [x] Incremental foreground refresh: successful sources appear in 100 ms batches without waiting for slow feeds; mobile/desktop lists retain the visible article position (2026-10-24)
- [x] Offline cache, read state, durable bookmarks, image caches
- [x] Folders, Material icons/order, feed management, OPML import/export
- [x] Search history; global/per-feed keyword filters
- [x] Tri-state per-feed plus global full-text extraction
- [x] Article swipe navigation, progress, reading time, image carousel
- [x] Browser modes, EasyList/AdGuard, DarkReader
- [x] Local notifications, quiet hours, digest selection, payload navigation
- [x] Foreground timer and Workmanager background sync
- [x] Home-widget data sync, Android widgets and deep-link handling; iOS widget source exists (native integration still needs verification)
- [x] Material 3 themes, responsive widths, skeletons, global toast
- [x] English, Turkish, Spanish; semantics; reduced-motion-aware toast
- [x] Debug utilities and focused automated test suite
- [x] Android/iOS signed build and store-submission workflow
- [x] Durable article records and shared media pool, separate from disposable image caches
- [x] Global newest-N temporary-cache membership; bookmark ownership survives cache eviction
- [x] Automatic unmetered preparation, explicit single-article preparation, retry scheduling
- [x] Ownership-aware cleanup, reset fences, and durable article-status UI
- [x] Shared feed/extraction/media host pacing, persisted feed/host cooldowns, bounded Retry-After handling
- [x] Lifecycle gate for multi-writer storage (native file lock; in-memory on web) with journaled, resumable factory reset (2026-10-26)
- [x] Per-source article identity: read state and saved copies keyed by feed + article ID; schema-1 archive migrated lazily, unproven copies quarantined in Settings > Legacy archive (2026-10-26)
- [x] Proven same article from another source reuses already-extracted content as its own copy (2026-10-26)
- [x] GitHub releases with signed APK, Windows installer, macOS DMG and Linux AppImage on every CI-green main push (2026-10-26)
- [x] Bundled OFL fonts (no runtime Google Fonts fetch) with app-font and article-typeface choices; one durable offline pipeline (legacy full-text prefetch removed) (2026-10-29)
- [x] Mark the current view read — everything or only articles older than a day/week, each with its count; same-link copies the view hides are marked too — from the feed tab overflow menu (which also holds Add feed) and the desktop list toolbar ([#1](https://github.com/DevOpen-io/dondurma-rss-reader/issues/1), 2026-10-29)
- [x] Full-screen article image viewer: tap an inline, gallery or cover image; pinch/wheel zoom, double-tap zoom/reset, back/Escape/close; an image inside a link offers that link ([#62](https://github.com/DevOpen-io/dondurma-rss-reader/issues/62), 2026-10-29)
- [x] Optional mark-as-read on scroll (Settings, off by default): article rows seen on screen and scrolled past the top edge are marked read in the phone and desktop lists ([#63](https://github.com/DevOpen-io/dondurma-rss-reader/issues/63), 2026-10-29)
- [x] Feed discovery: a site, YouTube channel/handle, subreddit, Mastodon or Bluesky address resolves to its feed (page alternates, then common paths); several feeds offer a choice ([#64](https://github.com/DevOpen-io/dondurma-rss-reader/issues/64), 2026-10-29)
- [x] Whole-app backup: one JSON file with feeds, folders, settings, bookmarks (article as saved, no images) and read marks; restore checks the file, then merges feeds/bookmarks/read marks and replaces settings ([#65](https://github.com/DevOpen-io/dondurma-rss-reader/issues/65), 2026-10-29)
- [x] Read aloud with the device speech engine (flutter_tts; Android, iOS, macOS, Windows in code — only Android exercised, the others unverified; hidden on Linux): button beside the reading-mode switch, floating pause/resume/stop bar; one reader for the app, stops on another article or leaving it ([#66](https://github.com/DevOpen-io/dondurma-rss-reader/issues/66), 2026-10-29)
- [x] Android share sheet: sharing a link to the app opens Add feed with it filled in (and feed discovery on save); a share before onboarding waits for the home screen. A UI-less ShareActivity brings the app up like the launcher, so a share never starts a second instance. iOS share extension not built ([#67](https://github.com/DevOpen-io/dondurma-rss-reader/issues/67), 2026-10-29)
- [x] Per-feed refresh interval (with the app / hourly / every 6 hours / daily) in the feed sheet: automatic foreground and background passes skip a feed until it is due, a pull to refresh fetches all; last fetch times persist per isolate like the cooldowns ([#68](https://github.com/DevOpen-io/dondurma-rss-reader/issues/68), 2026-10-29)
- [x] Filter rules: any keyword list takes `/regex/` patterns and a `title:` prefix (title only); per-feed "Only show matching" list; a global "Mark read automatically" list applied as articles arrive and when the list changes. Author matching is not possible (feeds' authors are not stored) ([#69](https://github.com/DevOpen-io/dondurma-rss-reader/issues/69), 2026-10-29)
- [x] Same article from several feeds: the row (always the first copy) is read only when every copy the view holds is; opening, marking or un-marking it applies to those copies; unread badges count such an article once (overall, per folder and per feed). Copies in another folder, and articles opened from elsewhere (bookmarks), keep their own state ([#70](https://github.com/DevOpen-io/dondurma-rss-reader/issues/70), 2026-10-29)
- [x] Bookmark tags (long-press a bookmark, right-click › Tags on desktop; filter chips above the bookmarks; tags under each phone row) and saved searches with their folder/feed and filters (⋮ › Save search while searching, desktop search field button; listed in the drawer and sidebar; long-press or right-click to rename or delete); both travel in backups ([#71](https://github.com/DevOpen-io/dondurma-rss-reader/issues/71), 2026-10-29)

## Backlog

- [ ] Broader provider, service, navigation, platform integration tests
- [ ] Privacy-preserving reading statistics
- [ ] Configurable retention and low-data controls beyond the existing automatic unmetered media preparation
- [ ] Bookmark export, reading queue/archive
- [ ] Read-later integrations
- [ ] Feed pinning/order/bulk actions/health status
- [ ] Notification actions, badges, feed sounds
- [ ] Advanced search and match highlighting
- [ ] Compact list, thumbnail/accent controls, navigation shortcuts
- [ ] Detailed per-feed sync log and storage usage

## Delivery rules

- Update status with implementation.
- Persisted fields need backward-compatible defaults.
- Add EN/TR/ES ARB entries; never edit generated localization Dart.
- Test narrow and wide layouts for UI changes.
- Preserve no-tracking/account/advertising promise.
