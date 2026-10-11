# Product Status and Backlog

Source comparison: 2026-10-11. Checked items describe implementation in the repository, not store approval or device verification. Source code wins when this file drifts.

[Product guide](guide.md) · [Technical roadmap](roadmap.md) · [Documentation index](../README.md)

## Implemented in the repository

- [x] RSS/Atom isolate parsing, browser headers, ETag/Last-Modified, HTTP 304
- [x] Five providers; three Hive CE boxes; legacy migration
- [x] Refresh coalescing, five-request concurrency, resume refresh, 50-item pagination
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
- [x] Shared feed/extraction host pacing, persisted feed/host cooldowns, bounded Retry-After handling (preparation wiring limits are documented in the architecture guide)

## Backlog

- [ ] Broader provider, service, navigation, platform integration tests
- [ ] TTS with lifecycle-safe controls
- [ ] Privacy-preserving reading statistics
- [ ] Configurable retention and low-data controls beyond the existing automatic unmetered media preparation
- [ ] Bookmark tags/export, reading queue/archive
- [ ] Read-later integrations
- [ ] Feed pinning/order/bulk actions/health status
- [ ] Notification actions, badges, feed sounds
- [ ] Advanced/saved search and match highlighting
- [ ] Compact list, thumbnail/accent controls, navigation shortcuts
- [ ] Detailed per-feed sync log and storage usage

## Delivery rules

- Update status with implementation.
- Persisted fields need backward-compatible defaults.
- Add EN/TR/ES ARB entries; never edit generated localization Dart.
- Test narrow and wide layouts for UI changes.
- Preserve no-tracking/account/advertising promise.
