# Follow-up Review — PR #60 RSS Engine Reliability

Repository: https://github.com/DevOpen-io/dondurma-rss-reader

Branch: `fix/rss-engine-reliability`

PR: https://github.com/DevOpen-io/dondurma-rss-reader/pull/60

An independent review of your implementation found several issues that must be investigated before merging.

**Work on the EXISTING branch and PR. Do not create a replacement architecture or unrelated refactor. Do not merge the PR.**

## 1. Critical: HostPacer Is Not Actually Shared

Currently:

- `FeedRefresher` creates its own HostPacer.
- `ArticlePreparationService` creates another instance.
- `FullTextExtractionService` performs independent HTTP requests.
- `runBgFetch()` does not apply HostPacer to its feed requests.

Your report claims shared same-host pacing, but the actual implementation does not guarantee it.

Investigate and implement reliable per-host coordination across feed fetching, article extraction, and media preparation.

Foreground and background run in different isolates, so do not assume a Dart singleton is shared across them.

Respect existing concurrency and performance requirements.

## 2. Critical: Rate-Limit Cooldown Is Per-Feed, Not Per-Domain

`FeedBackoff` currently keys cooldowns by feed URL.

When `reddit.com/r/a/.rss` receives HTTP 429, another subscription such as `reddit.com/r/b/.rss` can still be requested.

Implement appropriate shared host/domain rate-limit handling while preserving feed-specific errors and scheduling.

A server-imposed host-level cooldown must protect other relevant requests to that host.

Do not unnecessarily block unrelated domains.

## 3. Foreground/Background Persistence Race

Review the interaction between:

- `FeedProvider._loadFeedBackoff()`
- `FeedProvider._saveFeedBackoff()`
- `runBgFetch()`
- Hive `feedBackoffUntil`
- Foreground and background scheduling

Investigate stale in-memory snapshots and concurrent updates overwriting newer deadlines.

Implement safe state synchronization without unnecessary writes or a disruptive persistence migration.

Add tests proving that a background 429 cannot be immediately bypassed by a foreground refresh, and vice versa.

## 4. Fix HTTP Redirect Handling

In `feed_service.dart`, cross-origin detection compares only `uri.host`.

Compare the complete origin, including scheme, host, and port.

Ensure validators are not incorrectly forwarded across origins.

Also investigate `next.stream.drain()` during redirects: it currently lacks the same explicit body deadline/size protection applied to final responses.

Add regression tests.

Ensure bounded body timeouts actually release/cancel underlying network resources.

## 5. Respect Server Retry-After During Manual Extraction

`FullTextExtractionService.extractFullText(forceRefresh: true)` currently bypasses the failure deadline.

Distinguish local retry suppression from server-mandated cooldown.

Manual refresh may bypass a local heuristic cooldown, but must respect valid server `Retry-After` deadlines.

Support both delta-seconds and HTTP-date values.

Add tests.

## 6. Resolve Existing CodeRabbit Findings

Inspect all open review comments on PR #60.

In particular, verify and fix:

- Full-origin redirect comparison
- Windows-1252 decoding
- HTTP-date Retry-After in extraction

Do not blindly apply suggestions. Validate them against the current code and add regression tests.

## 7. Parser Robustness

Review arbitrary Atom namespace-prefix handling.

The parser should verify the Atom namespace URI and actual XML structure rather than relying only on a matching prefix regex.

Preserve support for existing RSS, RDF, Atom and JSON Feed variants.

Avoid converting unrelated XML namespaces into Atom accidentally.

## 8. Mandatory Regression Tests

Add tests for:

- Multiple Reddit feeds receiving the same host-level 429
- Foreground and background cooldown sharing
- Concurrent Hive cooldown updates
- Host pacing across different services
- Manual extraction during server Retry-After
- Redirect scheme/port changes
- Slow redirect response bodies
- Windows-1252 smart punctuation
- HTTP-date Retry-After
- Valid vs invalid prefixed Atom documents
- Existing cache, bookmark and read-state preservation

Run all existing tests and Flutter analysis.

Verify Android debug build if available.

Do not claim real-device validation unless actually performed.

## 9. Final Report

Provide a Turkish report with:

1. Confirmed defects and root causes
2. Exact implementation changes
3. Relevant changed files
4. New regression tests
5. CI results
6. Remaining risks
7. Final commit SHA
8. Explicit confirmation that PR #60 was not merged

**Objective:** Make PR #60 safe and consistent with its reported guarantees. Prefer targeted, evidence-backed corrections over unnecessary architectural complexity.
