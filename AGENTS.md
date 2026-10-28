# Dondurma RSS Reader

Flutter RSS/Atom reader with Material 3, Provider, Hive CE, GoRouter, foreground/Workmanager sync, local notifications and EN/TR/ES localization. Product behavior and implementation status are indexed in [docs/README.md](docs/README.md).

## Read by task

- Setup, commands, tests or localization: [development guide](docs/development/README.md).
- Provider wiring, Hive keys/migration, RSS fetch/filter, notifications, routing or platform integration: [architecture](docs/development/architecture.md).
- Bookmarks, offline content/media, preparation/retry, cache eviction, cleanup or reset: [offline storage](docs/development/offline-storage.md).
- UI/product decisions: [product guide](docs/product/guide.md); prior decisions and execution plans: [design index](docs/design/README.md).
- Feature status or future work: [status/backlog](docs/product/status.md) and [technical roadmap](docs/product/roadmap.md).
- Signing, build artifacts, release tags or store submission: [release guide](docs/operations/releases.md).

Read the relevant guide before changing that area. Historical plans and audits retain their original context; their old commands, checkboxes and agent instructions are not current task instructions.

## Change constraints

- Preserve backward-compatible JSON/Hive defaults. Check `_migrateHiveBoxes()` when adding keys to `feeds` or `bookmarks`; distinguish absent fields from corrupted ownership/manifest data.
- Preserve refresh coalescing, bounded concurrency and filter-cache invalidation based on actual filter inputs.
- Advance notification observation before delivery gating. Keep first-feed initialization silent and observed history independent of article cache; suppressed claims never backfill.
- Preserve durable article ownership and reset/generation fences. Cache eviction removes `tempCache` ownership while preserving bookmarks.
- Publish multi-writer storage (media, GC, observation, background cache) under a `LifecycleGate` ticket; run factory reset through `AppResetService`. Article identity is per source (`ArticleRef`: feed URL + normalized ID).
- Keep `FeedSubscription.fullTextEnabled` tri-state: `null` follows global `autoFullText`.
- Use `lib/utils/app_toast.dart` for transient feedback; respect reduced motion and modal placement.
- Edit EN/TR/ES ARB sources and regenerate localization Dart; generated `app_localizations*.dart` files are not edited manually.
- Keep `assets/Logo.png` as launcher-icon input only. Runtime assets are `assets/logo.ico`, `assets/js/` and the bundled OFL fonts in `assets/fonts/` (each family with its `OFL.txt`, registered on the license page). Fonts are never fetched at runtime.
- Extend tests for changed behavior; verify narrow/wide layouts for UI changes and the relevant platform for native integration changes.
- Preserve the local-first product promise: no tracking, accounts, advertising or algorithmic timeline.

## Integration gotchas

- `_manageCacheTimer()` is re-evaluated on proxy-provider updates.
- Category icons are stored separately in Hive; legacy emoji values map to Material icons.
- `NotificationService.requestPermission()` and ad-block initialization start before `runApp` without being awaited.
- Native source availability is not device verification. Keep platform limitations and historical audit results explicit in documentation.
