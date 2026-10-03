# iOS viability audit — offline reading

Resolves [issue #16](https://github.com/DevOpen-io/dondurma-rss-reader/issues/16).
Scope: what blocks iOS today for the offline-reading feature set (feed fetch, cache,
notifications, widgets, in-app browser). Source-verified against the repo and the
installed package sources/docs — not build-verified (`flutter build ios` needs macOS/Xcode;
this machine is Linux, per `ios/Flutter/Generated.xcconfig` `FLUTTER_ROOT=/home/alha/development/flutter`).

Verdict legend: **works** / **needs config** / **needs rework** / **not possible**.

## TL;DR

| Subsystem | Verdict | Effort |
|---|---|---|
| Build config | needs config | S |
| Storage (hive_ce, isolates, image cache) | works | — |
| In-app browser (webview_flutter + adblocker_webview) | works | — |
| Notifications (flutter_local_notifications) | needs config | S (1 AppDelegate line + verify) |
| OPML / misc plugins (share_plus, url_launcher, file_selector, package_info_plus) | works | — |
| Background sync (workmanager) | needs rework | M — plist + AppDelegate + accept OS-controlled cadence |
| Home-screen widgets (home_widget) | needs rework | M–L — Xcode widget target + App Group capability + Swift data-format/deep-link fixes |

Nothing is impossible. The only hard iOS limitation is background sync cadence:
iOS decides when BGAppRefreshTask runs (typically ~daily, driven by usage patterns),
never after the user force-quits, ~30 s budget. The "check every 15 min" model does
not exist on iOS for any app — that's platform reality, not a bug.

## 1. Build config — needs config

`ios/` exists and is a real generated Runner project (`ios/Runner.xcodeproj`,
`ios/Podfile`, `ios/Runner/Info.plist`, asset catalogs, `RunnerTests`).

Good:
- `PRODUCT_BUNDLE_IDENTIFIER = io.devopen.dondurma` (project.pbxproj:515,700,725) ✓
- `DEVELOPMENT_TEAM = 6NLKUNN3FH` already set (project.pbxproj:506,691,716)
- `CFBundleLocalizations` = en/tr/es matches supportedAppLanguages (Info.plist:9-14)
- `NSLocationWhenInUseUsageDescription` present for WKWebView geolocation (Info.plist:35-36)
- `UIBackgroundModes` = `fetch` present (Info.plist:64-67)
- Launcher icons generated (`flutter_launcher_icons: ios: true`, pubspec.yaml:127; `ios/Runner/Assets.xcassets/AppIcon.appiconset`)
- AppDelegate uses the current `FlutterImplicitEngineDelegate` + `SceneDelegate` (UIScene) pattern — matches what workmanager/flutter_local_notifications docs now assume.

Problems:
- `IPHONEOS_DEPLOYMENT_TARGET = 13.0` (project.pbxproj:490,622,673) vs `platform :ios, '15.5'` (Podfile:2) vs `s.ios.deployment_target = '14.0'` in `workmanager_apple-0.9.1+2/ios/workmanager_apple.podspec`. Runner target must be ≥14.0 (workmanager) — bump to 15.5 to match the Podfile. **Effort: trivial.**
- `BGTaskSchedulerPermittedIdentifiers` = `com.pravera.flutter_foreground_task.refresh` (Info.plist:60-63) — that's the `flutter_foreground_task` package's identifier, not ours. workmanager submits `BGAppRefreshTaskRequest(identifier: "rss_bg_fetch")` (our `uniqueName`, see lib/services/background_fetch_service.dart:17 + WorkmanagerPlugin.swift:195), so the plist must list `rss_bg_fetch`. Current value blocks BGTaskScheduler `submit()` (throws, caught+logged by the plugin → task silently never scheduled).
- No `.entitlements` files anywhere under `ios/` → no App Groups → widget data sharing dead (see §5).
- `ios/Podfile.lock` is stale: it lists only `workmanager_apple` + `google_mlkit_*` pods. `google_mlkit_translation` isn't even in pubspec.yaml (leftover from a removed feature), and none of the current iOS plugins (`path_provider_foundation`, `flutter_local_notifications`, `webview_flutter_wkwebview`, `home_widget`, `share_plus`, `url_launcher_ios`, `file_selector_ios`, `package_info_plus`) are in it. Regenerate with `pod install` on a Mac.
- `ios/DondurmaWidgets/` is an orphan: `DondurmaWidgets.swift` exists but the Xcode project contains only `Runner` + `RunnerTests` native targets (project.pbxproj:177-223). No widget extension target, no extension Info.plist, no entitlements — needs creation in Xcode.

## 2. Background sync (workmanager 0.9.0+3 → workmanager_apple 0.9.1+2) — needs rework

Current usage (`lib/main.dart:110-121`, `lib/services/background_fetch_service.dart`):
`Workmanager().initialize(callbackDispatcher)` + `registerPeriodicTask('rss_bg_fetch', 'rss_bg_fetch', frequency: 15min, constraints: NetworkType.connected, existingWorkPolicy: keep)`.

What iOS actually delivers (official capability matrix —
github.com/fluttercommunity/flutter_workmanager/blob/main/docs/index.mdx):

| Our usage | iOS reality |
|---|---|
| `registerPeriodicTask` | Maps to `BGAppRefreshTaskRequest`. Best-effort; iOS decides timing from app-usage patterns ("typically once per day" per quickstart.mdx warning), ≥15 min between launches, ~30 s runtime budget |
| `frequency: 15min` | Ignored on iOS — frequency hint is set natively via `WorkmanagerPlugin.registerPeriodicTask(withIdentifier:frequency:)` in AppDelegate |
| `constraints: NetworkType.connected` | Ignored — "iOS applies its own system-level constraints" |
| `existingWorkPolicy` | Android-only; ignored |
| `cancelByUniqueName` | Works (`BGTaskScheduler.cancel(taskRequestWithIdentifier:)`, WorkmanagerPlugin.swift:229-233) |
| Task after force-quit | **Never runs** — iOS does not execute BGTaskScheduler work after user-termination |
| `executeTask` task name | Receives the registered identifier `rss_bg_fetch`; our dispatcher ignores the name and always runs `runBgFetch()` ✓ |
| Plugins inside `callbackDispatcher` | Runs in a separate headless FlutterEngine (BackgroundWorker.swift:97-107). Our `runBgFetch()` calls `Hive.initFlutter()` (needs `path_provider_foundation`), `NotificationService.init()` (`flutter_local_notifications`), `WidgetUpdateService` (`home_widget`) — all require `WorkmanagerPlugin.setPluginRegistrantCallback` wired in AppDelegate, else `MissingPluginException` → silent no-op |

Config gaps to close (per quickstart.mdx Option C + WorkmanagerPlugin.swift):
1. `Info.plist` `BGTaskSchedulerPermittedIdentifiers` → `rss_bg_fetch` (identifier must exactly match Dart `uniqueName` or `BGTaskSchedulerErrorDomain Code 3` / submit failure).
2. `AppDelegate.swift`: `WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "rss_bg_fetch", frequency: 900)` — on our 0.9.x version the BGTaskScheduler *handler* is only registered by this call (Dart-side `registerPeriodicTask` only calls `submit()`; there is no auto-registration on launch in 0.9.1+2 — no `didFinishLaunchingWithOptions`/launch-handler re-registration in the plugin).
3. `AppDelegate.swift`: `WorkmanagerPlugin.setPluginRegistrantCallback { registry in GeneratedPluginRegistrant.register(with: registry) }` — required for Hive/notifications/home_widget inside the background isolate.
4. Bump Runner `IPHONEOS_DEPLOYMENT_TARGET` to ≥14.0 (podspec minimum).
5. UIScene caveat: newer workmanager docs (0.10.x) note UIScene apps must register launch handlers before launch finishes — our call in `application(_:didFinishLaunchingWithOptions:)` satisfies this; consider upgrading workmanager to 0.10.x which formalizes this via `registerLaunchHandlers()`.

Behavioral caveats to accept (no code fix exists):
- ~30 s budget per run — `runBgFetch()` fetches all feeds concurrently over one keep-alive client; usually fine, but large subscription lists could get killed mid-run. Partial writes are safe (cache merge is atomic per-box).
- Cadence is OS-chosen (~daily for a lightly-used app), not 15 min.
- Nothing runs after swipe-to-kill. Foreground timer sync still covers active use.

**Effort:** ~1 hour of plist/AppDelegate changes + a real-device verification cycle. Document the cadence reality for users.

## 3. Notifications (flutter_local_notifications 21.0.0) — needs config (small)

Plugin claims and delivers full iOS support via UNUserNotificationCenter (README §"iOS setup"; podspec `ios.deployment_target = '13.0'`). Resolved as an iOS plugin in `.flutter-plugins-dependencies` ✓.

Feature check against `lib/services/notification_service.dart`:
- `DarwinInitializationSettings(requestAlert/Badge/Sound: true)` — requests permission at init on iOS ✓; `IOSFlutterLocalNotificationsPlugin.requestPermissions` path exists ✓
- `show()` + `payload` + `DarwinNotificationDetails()` — works; foreground presentation defaults are all `true` in v21 (`defaultPresentAlert/Sound/Badge/Banner/List`), so instant notifications show even with the app open ✓
- `onDidReceiveNotificationResponse` → `_tapController` → router push — supported on iOS
- `getNotificationAppLaunchDetails` — supported on iOS (cold-launch tap navigation works)
- Quiet hours + digest gating — pure Dart (`_isInQuietHours`, `digestMode != 'instant'` early-returns), platform-agnostic ✓
- Local notifications need **no** entitlement/`aps-environment` — none present, correct.

Gap: the official iOS setup requires `UNUserNotificationCenter.current().delegate = self` in AppDelegate `didFinishLaunchingWithOptions` (README §"🔧 iOS setup"; the plugin never assigns the delegate itself — grep shows no `center.delegate` assignment in `FlutterLocalNotificationsPlugin.m`; the plugin's example AppDelegate sets it). Our `ios/Runner/AppDelegate.swift` lacks this line → `didReceiveNotificationResponse` won't be delivered while the app is running; notification taps may lose their payload routing. **Effort: 1 line + test.**

## 4. Storage (hive_ce 2.19.3 / hive_ce_flutter 2.3.4) — works

- `hive_ce` is pure Dart (no platforms/plugin section in its pubspec). `hive_ce_flutter` depends on `path_provider` only → `path_provider_foundation` iOS impl resolved → `Hive.initFlutter()` uses `getApplicationDocumentsDirectory()` on iOS ✓.
- `compute()` isolates used by `parseFeedBody` (feed_service.dart:164) and `extractArticleHtml` (full_text_extraction_service.dart:137) — Dart VM isolates, identical on iOS.
- `ObservedArticleStore` lock files use `dart:io` File I/O in the app sandbox — works on iOS.
- `image_cache_service.dart` uses `getTemporaryDirectory()` — supported.
- Background-isolate caveat: inside the workmanager BG engine, `Hive.initFlutter()` needs path_provider registered — covered by the §2 `setPluginRegistrantCallback` fix (same on Android, where it works via the plugin's own registrant wiring).

## 5. Home-screen widgets (home_widget 0.9.3) — needs rework (largest gap)

Dart side is iOS-ready (`lib/services/widget_update_service.dart`): `setAppGroupId('group.io.devopen.dondurma')`, `saveWidgetData` → `UserDefaults(suiteName:)` writes (HomeWidgetPlugin.swift:109-118), `updateWidget(iOSName:)` → `WidgetCenter.shared.reloadTimelines(ofKind:)` (HomeWidgetPlugin.swift:167-170). iOSName values match the Swift `kind` strings ✓.

Native side gaps:
1. **Widget extension not wired into Xcode.** `ios/DondurmaWidgets/DondurmaWidgets.swift` is a complete WidgetKit/SwiftUI implementation but the Xcode project has no widget target (project.pbxproj lists only Runner + RunnerTests), no extension `Info.plist`, no entitlements, no `appex` product. Must be created via Xcode: File > New > Target > Widget Extension (requires macOS), or the `home_widget_cli` generator path documented at github.com/ABausG/home_widget docs.
2. **App Groups capability missing on both targets** — required for `UserDefaults(suiteName: "group.io.devopen.dondurma")` to share data; without it `suiteName` returns nil → widget renders empty and `saveWidgetData` writes go nowhere shared. Needs a paid Apple Developer account to provision `group.io.devopen.dondurma` (home_widget iOS setup doc).
3. **Data-format mismatch in the Swift code.** Dart writes `widget_latest` (array — matches Swift `loadArticles(key:)` ✓) but for categories writes `widget_category_list` + `widget_category_data` (name list + category→articles map; widget_update_service.dart:62-69) while Swift reads a single `widget_category` object `{name, articles}` (DondurmaWidgets.swift:32-46). The iOS category widget will always show its empty state.
4. **No deep links.** iOS taps reach Dart only via `.widgetURL`/Link opening a URL containing a `homeWidget` query item (HomeWidgetPlugin.swift:462-465 forwards such URLs to `widgetClicked`/`initiallyLaunchedFromHomeWidget`). The Swift widget has no `.widgetURL` — tapping just opens the app; `homewidget://article?id=<id>` navigation won't fire. Fix = add `.widgetURL(URL(string:"homewidget://article?homeWidget&id=\(id)"))` on rows + satisfy the `homeWidget` query-param check.
5. `StaticConfiguration` → no per-widget category picker on iOS (Android has configuration). iOS16+/17 `AppIntentConfiguration` would be needed for parity — optional.

**Effort:** M–L. Half a day of Xcode wiring (extension target, App Groups, entitlements, signing) + small Swift fixes for the data format and widgetURL.

## 6. In-app browser (webview_flutter 4.13.1 → webview_flutter_wkwebview 3.23.7 + adblocker_webview 2.3.0) — works

- `webview_flutter_wkwebview` resolved as the iOS plugin (`.flutter-plugins-dependencies`); podspec min iOS 12/13 ✓. `in_app_browser.dart:17-23` already treats iOS as WebView-capable.
- `adblocker_webview` is **pure Dart** — no native plugin code (not in the iOS plugin list; pubspec `platforms:` entries are metadata). It wraps `webview_flutter` + `webview_flutter_wkwebview` and does blocking via `NavigationDelegate` + `runJavaScript` (lib/src/adblocker_webview.dart:141-219, explicit `Platform.isIOS` branch with `webkit`/`WKWebView`-specific handling). EasyList/AdGuard fetch+parse runs in Dart — identical on iOS.
- DarkReader injection (`in_app_browser.dart` ~line 367-403, `assets/js/darkreader.min.js`) is `runJavaScript` — works on WKWebView. `assets/js/` is already in the bundled asset list (pubspec.yaml:92-94).

## 7. Other plugins — works

- `share_plus` 12.0.1 — iOS impl resolved; OPML export uses the share sheet (opml_service.dart:148-157) ✓
- `file_selector_ios` 0.5.3+5 — `openFile` works (document picker); OPML import fine. (`getSaveLocation` is unsupported on iOS but unused — export goes through share_plus.)
- `url_launcher_ios`, `package_info_plus`, `flutter_html` (widgets), `go_router`, `google_fonts`, `intl`, `xml`, `dart_rss`, `http` — iOS fine.
- Platform gates in lib/ are minimal: only settings browser-mode fallback and the WebView-support check (both include iOS).

## Residual risks / honest unknowns

- **Never build-verified.** `flutter build ios` + `pod install` require macOS/Xcode. The pbxproj/Podfile may surface more issues on first real build (e.g., stale Podfile.lock will be regenerated; the orphan `DondurmaWidgets/` dir may confuse nothing since it's not in the target).
- `google_mlkit_*` in the stale Podfile.lock suggests a removed feature once added pods — confirm no dangling references on first `pod install`.
- workmanager iOS behaves worst-case ~daily refresh + nothing-after-force-quit. If daily sync is unacceptable, the realistic alternative is silent push (APNs) — a server component — i.e., **out of scope** for a client-only app; document the limitation instead.
- The `com.pravera.flutter_foreground_task.refresh` plist entry + `flutter_foreground_task`-style artifacts suggest the project once used that package; harmless but should be replaced with our own identifier.

## Effort summary

1. **Config-only (S):** deployment target bump, plist identifier fix, 3 AppDelegate lines (workmanager periodic registration, setPluginRegistrantCallback, UNUserNotificationCenter delegate), `pod install` regeneration.
2. **Needs macOS/Xcode (M–L):** widget extension target + App Groups + Swift fixes.
3. **Expectation-setting (0):** iOS background cadence is best-effort OS-controlled; document rather than fix.

## Sources

- Repo: `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/project.pbxproj`, `ios/Podfile`, `ios/Podfile.lock`, `ios/DondurmaWidgets/DondurmaWidgets.swift`, `ios/Runner/AppDelegate.swift`, `ios/Runner/SceneDelegate.swift`, `ios/Flutter/Generated.xcconfig`, `.flutter-plugins-dependencies`, `pubspec.yaml`, `pubspec.lock`, `lib/main.dart`, `lib/services/{background_fetch_service,notification_service,widget_update_service,feed_service,full_text_extraction_service,image_cache_service,opml_service,observed_article_store}.dart`, `lib/widgets/in_app_browser.dart`.
- workmanager: `~/.pub-cache/hosted/pub.dev/workmanager_apple-0.9.1+2/ios/Sources/workmanager_apple/{WorkmanagerPlugin,BackgroundWorker}.swift`, `workmanager_apple.podspec`; official docs https://github.com/fluttercommunity/flutter_workmanager/blob/main/docs/index.mdx (capability matrix) and .../docs/quickstart.mdx (iOS setup options, identifier-matching warning, background-fetch cadence note).
- flutter_local_notifications: `~/.pub-cache/hosted/pub.dev/flutter_local_notifications-21.0.0/README.md` (iOS setup: `UNUserNotificationCenter.current().delegate`), `ios/flutter_local_notifications.podspec`, `lib/src/platform_specifics/darwin/{initialization_settings,notification_details}.dart`, `example/ios/Runner/AppDelegate.swift`.
- home_widget: `~/.pub-cache/hosted/pub.dev/home_widget-0.9.3/ios/home_widget/Sources/home_widget/HomeWidgetPlugin.swift`; official https://github.com/ABausG/home_widget/blob/main/docs/setup/ios.mdx (Widget Extension target + App Groups requirement).
- adblocker_webview: `~/.pub-cache/hosted/pub.dev/adblocker_webview-2.3.0/{pubspec.yaml,lib/src/adblocker_webview.dart,lib/src/adblocker_webview_controller_impl.dart}` (Dart-only, iOS branches).
- hive_ce: `~/.pub-cache/hosted/pub.dev/hive_ce_flutter-2.3.4/pubspec.yaml` (depends on path_provider only).
- webview: `~/.pub-cache/hosted/pub.dev/webview_flutter_wkwebview-3.23.7/darwin/webview_flutter_wkwebview.podspec`.
