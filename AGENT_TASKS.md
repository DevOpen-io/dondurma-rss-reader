# Product Status and Backlog

Source snapshot: 2026-08-24. Source code wins when this file drifts.

## Shipped

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
- [x] Android/iOS latest-news and category widgets with deep links
- [x] Material 3 themes, responsive widths, skeletons, global toast
- [x] English, Turkish, Spanish; semantics; reduced-motion-aware toast
- [x] Debug utilities and focused automated test suite
- [x] Android release workflow

## Backlog

- [ ] Broader provider, service, navigation, platform integration tests
- [ ] TTS with lifecycle-safe controls
- [ ] Privacy-preserving reading statistics
- [ ] Media prefetch, retention controls, low-data mode
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
