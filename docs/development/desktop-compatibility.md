# Desktop compatibility report

Scope: extending Dondurma RSS Reader to Windows 10/11, Linux (GNOME/KDE/Cinnamon),
and macOS (Intel + Apple Silicon) on the `feature/multiplatform-desktop` branch.

## Dependency audit

| Package | Android/iOS | Windows | Linux | macOS | Action |
|---|---|---|---|---|---|
| `workmanager` 0.9.0+3 | yes | no | no | partial (iOS only semantics) | gated behind `PlatformCaps.supportsBackgroundScheduler` |
| `home_widget` 0.9.3 | yes | no | no | no | gated behind `PlatformCaps.supportsHomeWidget` |
| `adblocker_webview` 2.3.0 | yes | no | no | no | gated behind `PlatformCaps.supportsAdBlockWebView` |
| `webview_flutter` | yes | no | no | yes (11.0+) | macOS keeps in-app WebView; Windows/Linux fall back to external browser |
| `flutter_local_notifications` 21 | yes | yes | yes | yes | per-platform initialization settings added |
| `file_selector` | yes | yes | yes | yes | unchanged; OPML export uses `getSaveLocation` on desktop |
| `share_plus` | yes | yes | yes | yes | share sheet kept where supported; copy-link fallback on desktop |
| `url_launcher` | yes | yes | yes | yes | unchanged; external browser fallback |
| `connectivity_plus` | yes | yes | yes | yes | unchanged |
| `path_provider` / `hive_ce_flutter` | yes | yes | yes | yes | unchanged |
| `cached_network_image_ce` | yes | yes | yes | yes | unchanged (pure Dart + path_provider) |
| `window_manager` 0.5.x | n/a | yes | yes | yes | added; desktop-only init in `main()` |

## Blockers found and resolved

1. **Unconditional plugin init in `main()`** — `Workmanager`, `HomeWidget`, and
   `AdBlockerWebview` were initialized for every platform, which throws
   `MissingPluginException` on desktop. Now gated through
   `lib/utils/platform_caps.dart`.
2. **Notification init settings** — Linux/Windows initialization settings were
   missing; added in `notification_service.dart` for the federated v21 plugin.
3. **OPML export depended on share sheet** — desktop now uses a native
   `getSaveLocation` save dialog; mobile share flow unchanged
   (`lib/services/opml_service.dart`, `lib/utils/share_actions.dart`).
4. **No desktop layout** — added adaptive four-zone shell
   (`lib/screens/desktop/`): a permanent app-level navigation rail, a
   feed/category explorer pane, the article list, and the embedded reader.
   Below `kDesktopNarrowBreakpoint` (860 logical px) the existing mobile
   `HomeScreen` renders unchanged; below `kDesktopExplorerBreakpoint`
   (1360) the explorer demotes to a drawer opened from the rail's Feeds
   button, keeping app navigation and content navigation visibly separate.
5. **No window management** — `DesktopWindowService` wraps `window_manager` for
   title/min-size/startup options; never invoked on mobile.
6. **`syncBackground` toggle meaningless on desktop** — hidden when
   `PlatformCaps.supportsBackgroundScheduler` is false.
7. **macOS sandboxed file access** — added
   `com.apple.security.files.user-selected.read-write` to Debug and Release
   entitlements so OPML import/export works under the app sandbox.
8. **Placeholder branding** — Windows `Runner.rc`, window title, and
   `BINARY_NAME`; Linux `my_application.cc` title and `BINARY_NAME`
   (`dondurma`); macOS `AppInfo.xcconfig` (`PRODUCT_NAME = Dondurma RSS Reader`,
   bundle id `io.devopen.dondurma`) all now carry product identity.
9. **macOS deployment target 10.15** — raised to 11.0, required by
   `webview_flutter_wkwebview`.

## Desktop UX delivered

- Four-zone adaptive layout (app rail / feed explorer / list / reader).
  The rail carries app destinations; the explorer carries the feed tree;
  below 1360 px the explorer demotes to a drawer.
- Reader pane toolbar owns prev/next, position, open-in-browser and share;
  the embedded `ArticlePage` suppresses its app-bar chrome (hero image
  stays, unpinned) so no double toolbar stacks above the article.
- Article content column caps at 840 px — comfortably centered inside the
  flex-width reader pane rather than stretching edge to edge.
- `ArticlePage` exposed with an `embedded` mode so the mobile PageView reader
  and the desktop pane share the exact same article UI.
- Keyboard shortcuts: Ctrl/Cmd+R refresh, Ctrl/Cmd+F search focus,
  Ctrl/Cmd+N add feed, Ctrl/Cmd+, settings; arrow keys + Enter navigate and
  read articles in the list.
- Mouse: hover states, right-click context menus (mark read/unread, bookmark,
  open externally, copy link), tooltips.
- Discover and Settings open as pushed routes (they own Scaffold/AppBar) rather
  than being embedded.

## Known limitations (honest)

- **No background fetch after process exit on desktop.** Workmanager is
  Android/iOS-only; desktop refreshes while running via the existing refresh
  coordinator. No OS scheduler integration is implemented.
- **No home widgets or system tray on desktop.** Tray was deferred — reliable
  cross-platform tray behavior is not part of this release.
- **No embedded WebView on Windows/Linux.** The in-app reader is unaffected
  (it renders extracted content, not WebView); "open in browser" uses the OS
  default browser. No ad-blocking on desktop since the WebView layer does not
  exist there.
- **Notification tap deep-link on Linux/Windows** depends on federated plugin
  support for `onDidReceiveNotificationResponse`; verified at compile time,
  device-level verification pending.
- **Windows/macOS native builds not verified on this host** (Linux). CI matrix
  in `.github/workflows/desktop-build.yml` provides the reproducible path;
  `.github/workflows/github-apk-release.yml` packages the Windows installer,
  macOS DMG and Linux AppImage for GitHub releases. Windows/macOS packages are
  not code-signed or notarized.

## Verification status

| Check | Result |
|---|---|
| `flutter pub get --enforce-lockfile` | pass |
| `flutter analyze` | clean (0 issues) |
| `flutter test` | 464 tests pass |
| `test/desktop_layout_test.dart` | 5 new tests, pass |
| `flutter build linux --release` | see verification notes |
| `flutter build windows --release` | not run on this host — CI only |
| `flutter build macos --release` | not run on this host — CI only |

## Manual desktop smoke-test checklist

1. Launch the app; window opens centered with sensible default size.
2. Resize below 860 px → mobile single-column layout appears; resize back.
3. Between 860–1360 px → the feed explorer collapses to a drawer; the
   rail's Feeds button opens it. Above 1360 px it pins inline.
4. Add a feed via Ctrl+N or the sidebar button; confirm fetch populates list.
5. Select an article with mouse and with ↑/↓ + Enter; reader pane updates.
6. Right-click a list row → context menu actions work.
7. Ctrl+R refreshes; Ctrl+F focuses search; Ctrl+, opens Settings.
8. Bookmark an article; switch to Bookmarks section; entry present.
9. Settings → OPML export → native save dialog appears; import round-trips.
10. Toggle dark/light/system theme; check contrast and focus indicators.
11. With network off, cached/bookmarked articles still open.
12. "Open in browser" on Windows/Linux launches the OS default browser.
