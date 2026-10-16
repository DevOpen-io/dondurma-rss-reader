# Multiplatform Performance & Correctness Audit

Branch `feature/multiplatform-desktop`. Date: 2026-10-17. Commit base: `42be530` + working-tree changes in this audit.

## A. Test environments

| Environment | Detail |
|---|---|
| OS | Fedora Linux 44, KDE Plasma, Wayland (`WAYLAND_DISPLAY=wayland-0`, `DISPLAY=:0`) |
| Flutter | 3.47.6 stable (rev 5fc346839b), Dart SDK ^3.11.0 |
| CPU/RAM | 20 logical cores, 30 GB RAM |
| Renderer | Impeller (OpenGLESSDF) on Linux |
| Mode tested | `flutter test` (debug VM), `flutter run --profile`, `flutter build linux --profile` |
| Devices visible | Linux desktop, Android emulator (sdk gphone64 x86_64, API 36), Chrome |
| **Not available** | Windows, macOS, iOS hosts; physical Android/iOS devices |

## B. Baseline measurements (Linux, profile mode, real user dataset)

Startup trace (`--trace-startup`, warm Hive cache):

| Metric | Value |
|---|---|
| Framework init | 87.7 ms |
| **Time to first frame** | **219.8 ms** |
| First frame rasterized | 271.8 ms |

Process-level sampling (`/proc/<pid>/stat`, `/proc/<pid>/status`):

| Metric | Value |
|---|---|
| Idle CPU (10 s window, post-refresh) | **0 %** (utime+stime delta 0 jiffies) |
| RSS after refresh settled | ~318 MB (includes profile-mode VM overhead) |

Micro-benchmarks (`test/perf_baseline_test.dart`, debug VM, median of 5 runs, 10k `FeedItem` fixtures — run tests, not release binaries; absolute numbers are pessimistic but comparable across changes):

| Operation (10k items) | Before | After |
|---|---|---|
| `applyFeedFilters` (global view) | 7.7 ms | 7.5 ms |
| `groupFeedItemsByDate` | 15.7 ms | 15.1 ms |
| Merge sort comparator | 255.4 ms | **1.8 ms** |
| `jsonEncode` (cache write) | 42.4 ms | 41.7 ms |
| `jsonDecode` + `fromJson` (cache read) | 103.1 ms | 100.2 ms |
| `parseFeedBody`, 100-item RSS | 21.4 ms | 21.0 ms |

JSON decode/encode and feed parsing already run in isolates (`compute`) — they do not stall the UI isolate.

## C. Problems identified & fixed

### P0 — correctness

1. **Today/Yesterday grouping mixed UTC fields with local `now`** —
   `groupFeedItemsByDate` compared `pubDate.year/month/day` (UTC instants)
   against the local calendar without `toLocal()`. Articles near midnight
   landed in the wrong bucket. Fixed: all dates are `.toLocal()` before
   calendar comparison. `lib/services/feed_date_groups.dart`

2. **Mislabeled feed timestamps produced "future" articles** — evidence:
   CNN TÜK serves local Türkiye time tagged `GMT` (feed claimed 00:39 GMT
   while UTC was ~22:01 → displayed ~03:39 local = 2 h "ahead"). Parsing was
   correct; the source label is wrong. Policy added: `pubDate` is never
   mutated (identity/cache stable), but ordering and grouping use
   `effectivePublicationDate` — timestamps more than
   `kFuturePubDateAllowance` (30 min) ahead are clamped to `now` for sort
   and grouping, so they cannot pin the top of the timeline forever.
   Relative display shows `now` only within the allowance; beyond it the
   real (future) date is shown — nothing is disguised.

3. **Profile/release crash in `_PaneSlot`** — `AnimatedContainer` with
   `clipBehavior: Clip.hardEdge` and no decoration hits
   `decoration!` in `Container.build` (debug only asserts; profile threw
   `Null check operator used on a null value` at runtime on Linux). Fixed
   by using a plain `ClipRect` around the `OverflowBox`.
   `lib/screens/desktop/desktop_home_screen.dart`

### P1 — responsiveness

4. **Per-comparison deadline allocation in date sort** — the merge
   comparator called `effectivePublicationDate` (which does
   `now.add(allowance)` internally) for ~140k comparisons on 10k items.
   Extracted `sortByEffectivePubDateDesc` (deadline hoisted once,
   deterministic `id` tie-break kept) shared by `FeedProvider` merge and
   `FeedService.capItems`. 255 ms → 1.8 ms in the micro-benchmark.

5. **Desktop shell rebuilt on status-only notifications** — the shell did
   `context.watch<FeedProvider>()` and rebuilt + re-copied the item list on
   every `notifyListeners` (e.g. `_isLoading` toggles during refresh).
   Now selects on the memoized `FeedDateGroups` instance, which is only
   replaced when underlying data changes. `_currentItems` copy runs only
   when it must.

### P3 — polish

6. **Hardcoded durations bypassed reduced-motion** — rail selection pill
   (150 ms), `Scrollable.ensureVisible` (120 ms), ExpansionTile default
   timing. All now flow through `motionDuration`; ExpansionTile gets an
   explicit `AnimationStyle` (200 ms, `easeOutCubic`).

7. **Abrupt article switching in reader** — added a one-shot keyed
   `TweenAnimationBuilder` fade-in (160 ms, `easeOut`). Single subtree —
   no crossfade, no duplicate article widgets.

## D. Escape navigation

- Desktop shell: `CallbackShortcuts` Escape → exits Focus Read Mode first,
  then unfocuses search; dashboard root is a no-op (no destructive action).
- Pushed Settings/Discover routes are wrapped in `_EscapePopScope`
  (`PopScope` + Escape shortcut on the route) — pop without touching
  underlying workspace state.
- Dialogs, dropdowns, context menus keep native Escape handling (topmost
  route wins; our handlers never intercept modal routes).
- Android/iOS unaffected — all wiring lives in the desktop shell.

Tests (`test/desktop_nav_selection_test.dart`): dashboard no-op,
Settings push+Escape pop, consecutive Escape, Focus Mode toggle + Escape
exit — 13/13 in file, 512/512 full suite.

## E. Cross-platform matrix

| Platform | Build | Automated tests | Runtime smoke | Performance profiled |
|---|---|---|---|---|
| Linux | ✅ `flutter build linux --profile` | ✅ 512 tests | ✅ profile run, clean log | ✅ startup trace + proc sampling + micro-bench |
| Android | not rebuilt this task | ✅ (shared suite) | not this task | ❌ |
| Windows | ❌ no host | ❌ | ❌ | ❌ |
| macOS | ❌ no host | ❌ | ❌ | ❌ |
| iOS | ❌ no host | ❌ | ❌ | ❌ |

GitHub Actions `desktop-build.yml` compiles Windows/macOS artifacts, but
compilation is not runtime profiling — those remain unverified.

## F. Remaining limitations

- No Windows/macOS/iOS runtime data — cannot claim resize, DPI, Retina or
  keyboard behavior beyond code review.
- Linux measurements are single-machine (Wayland + Impeller/GLES); X11 and
  other GPU backends unmeasured.
- Micro-benchmarks run in the debug VM — good for before/after comparison,
  not representative of release absolute numbers.
- Feed fetch errors seen in logs (HBR TLS handshake, TED 8 MB limit,
  Bigpara/Beyinsizler 403, Borsagundem WRONG_VERSION_NUMBER, Africanews
  406, Beetekno 404) are server-side issues, unchanged.

## G. Recommended follow-up (evidence-based)

- Frame-time profiling (`SchedulerBinding` timeline / DevTools) during
  continuous window resize on Linux — pane-slot animations retarget fine
  in code review, but raster cost under dragging is unmeasured.
- Image decode dimensions audit (`cached_network_image_ce` thumbnails) —
  not measured this round.
- RSS sync benchmark against a local mock server at 100–500 subscriptions
  to validate host pacing under load.
