# Mission: Dondurma RSS Reader — Production-Grade RSS Engine Reliability & Reddit Compatibility Overhaul

## Repository

https://github.com/DevOpen-io/dondurma-rss-reader

**Model:** Devin SWE-2.MAX

**Task type:** Deep codebase investigation, root-cause analysis, implementation, automated testing, regression verification, and final technical report.

## Primary Objective

Perform a comprehensive reliability overhaul of Dondurma's existing RSS/Atom/JSON Feed ingestion and article-reading pipeline.

The application currently experiences intermittent problems with Reddit RSS feeds. However, **this task is NOT limited to Reddit**.

The real objective is to make the entire RSS lifecycle as robust, efficient, predictable, and production-ready as possible.

Investigate and fix problems involving:

- RSS/Atom/JSON Feed downloading and parsing
- HTTP response handling
- Reddit RSS compatibility
- Rate limiting and retries
- Feed refresh scheduling
- Article identity and deduplication
- Full-text extraction
- Content normalization and sanitization
- Media detection and rendering
- Offline caching and persistence
- Background synchronization
- Error reporting
- Performance and memory efficiency

**You are expected to investigate, implement, test, and verify the fixes — not merely produce recommendations.**

Do not stop after fixing the first Reddit-related error. Audit the full ingestion-to-rendering lifecycle.

---

# 1. Mandatory Investigation Before Editing

First, study the repository architecture and identify how data travels through the application:

```text
FeedSubscription
    ↓
FeedProvider / Background Sync
    ↓
FeedRefresher
    ↓
FeedService
    ↓
HTTP Response Validation
    ↓
RSS / Atom / JSON Feed Parser
    ↓
FeedItem Normalization
    ↓
Local Cache / Persistence
    ↓
Article Preparation / Extraction
    ↓
ArticlePageProvider
    ↓
ArticleScreen / UI
```

Start by examining these files:

```text
lib/services/feed_service.dart
lib/services/feed_refresh.dart
lib/services/feed_cache_policy.dart
lib/services/article_identity.dart
lib/services/article_preparation_service.dart
lib/services/full_text_extraction_service.dart
lib/services/article_record_store.dart
lib/services/article_media_store.dart

lib/providers/feed_provider.dart
lib/providers/article_page_provider.dart
lib/providers/subscription_provider.dart

lib/models/feed_item.dart
lib/models/feed_subscription.dart

lib/screens/article_screen.dart
lib/widgets/feed_list_item.dart

lib/services/background_fetch_service.dart

remote_data/suggested_feeds.json
```

Also inspect any other relevant modules, existing test suites, documentation, and configuration.

Do not assume the list above represents the entire system.

## Mandatory Skill Usage

Inspect and use the repository's existing agent skills where applicable, especially:

```text
.agents/skills/diagnosing-bugs/SKILL.md

.agents/skills/flutter-apply-architecture-best-practices/SKILL.md
```

Also inspect other relevant skills for testing, debugging, performance optimization, code quality, and architecture if they exist.

Use the actual installed/repository skill instructions. Do not claim to have used skills you could not access.

Follow an evidence-based debugging workflow:

1. Trace the affected code paths.
2. Identify reproducible failures or concrete architectural risks.
3. Write failing regression tests where feasible.
4. Establish the root cause.
5. Implement the smallest coherent, maintainable fix.
6. Verify the new behavior.
7. Run full regression checks.

Avoid speculative fixes and unnecessary rewriting.

---

# 2. Critical Issue: Reddit RSS Reliability

The suggested feed list contains Reddit subscriptions with different RSS URL structures, including:

```text
https://www.reddit.com/r/programming/.rss
https://reddit.com/r/androiddev.rss
https://www.reddit.com/r/tennis/.rss
https://reddit.com/r/personalfinance/.rss
```

It also contains a multi-subreddit RSS feed.

Inspect the actual feed URLs in the repository rather than relying solely on these examples.

## Required Investigation

Determine whether failures originate from:

- HTTP 403 responses
- HTTP 429 rate limiting
- Reddit access restrictions
- Incorrect or unsupported URL formats
- Redirect behavior
- Missing or incompatible request headers
- Atom parsing issues
- RSS article content extraction
- Reddit media handling
- Repeated requests
- Cached validation headers
- Incorrect failure classification
- Background synchronization behavior

Distinguish between feed retrieval failure and article full-text extraction failure.

These are separate operations.

## Required Improvements

Implement a source-aware request policy system where justified.

A Reddit-specific policy may configure:

- Conservative refresh scheduling
- Domain-wide cooldown
- Proper HTTP 429 handling
- `Retry-After` support
- Request deduplication
- Avoidance of unnecessary HTML extraction
- Prioritizing usable content already provided in RSS/Atom

The policy should integrate into the general feed architecture rather than create an entirely separate Reddit RSS engine.

**Important restrictions:**

Do not use rotating proxies, CAPTCHA bypasses, stolen credentials, deceptive anti-bot bypasses, or other attempts to defeat Reddit's access controls.

Do not assume changing User-Agent guarantees access.

If Reddit explicitly denies anonymous RSS access, preserve cached content, report the limitation clearly, and document whether an official authorized integration would be required.

Do not introduce a backend service or require user authentication without demonstrating why it is necessary.

The application's local-first, privacy-oriented architecture should remain intact.

---

# 3. HTTP Fetching and Error Handling

Audit and improve `FeedService.fetchFeed()` and all related network operations.

## HTTP Status Handling

Implement explicit handling for:

| Status | Expected behavior |
|---|---|
| 200 | Validate payload, parse, persist |
| 304 | Reuse existing valid cached content |
| 301/308 | Safely process permanent redirect |
| 302/307 | Safely follow temporary redirect |
| 401/403 | Classify as access restricted |
| 404/410 | Classify as missing/gone |
| 429 | Respect rate limit and `Retry-After` |
| 500/502/503/504 | Retry with bounded exponential backoff |
| Timeout | Preserve cache and schedule retry |
| Invalid payload | Report parse/validation failure |

Create structured error results instead of relying primarily on generic exception strings.

Include useful metadata such as:

```text
error category
HTTP status
source URL
retryability
retry-after deadline
failure reason
```

Preserve existing caller contracts where practical.

## Network Safety

Investigate and implement appropriate protections for:

- Connection timeout
- Response body download timeout
- Overall request deadline
- Maximum response body size
- Excessive redirect chains
- Invalid redirect targets
- Cross-origin redirects
- Unnecessary transfer of conditional headers across origins
- Malformed or unexpectedly large payloads
- Resource cleanup
- Proper HTTP client reuse

Review whether the current timeout covers the complete download or only receiving response headers.

Avoid unbounded response buffering.

---

# 4. Intelligent Refresh Scheduling

The existing implementation already limits concurrent feed requests and coalesces some refresh operations.

Preserve these capabilities.

However, investigate missing source-aware scheduling behavior.

Implement or improve:

### Per-domain throttling

Multiple subscriptions from the same host should not generate unnecessarily aggressive request bursts.

### Exponential backoff

Use bounded exponential backoff with jitter for transient failures.

### Retry-After

Respect valid server-provided retry deadlines.

Manual refresh must not violate a server-imposed cooldown.

### Request coalescing

Avoid simultaneously fetching identical feed URLs from different application components.

### Adaptive refresh

Where useful, reduce requests for feeds that change infrequently while allowing actively updated feeds to remain reasonably fresh.

Preserve user expectations regarding manual refresh.

### Background synchronization

Ensure background and foreground refreshes cannot unintentionally bypass the same cooldown and rate-limit policies.

Persist scheduling state when necessary, without introducing unnecessary storage complexity.

Prevent excessive battery, data, and CPU consumption.

---

# 5. Feed Format Detection and Parsing

Audit `FeedService.parseFeedBody()`.

The application supports RSS 2.0, RSS 1.0/RDF, Atom, and JSON Feed.

Retain all supported formats.

## Required Improvements

Inspect:

- Document root detection
- XML validity
- JSON Feed validity
- Empty documents
- Empty but valid feeds
- HTML error pages returned as HTTP 200
- Namespace-prefixed Atom
- RSS 1.0/RDF
- CDATA handling
- XML entities
- Malformed individual entries
- Relative article URLs
- Relative media URLs
- Feed discovery and redirects

Do not assume an HTTP 200 response contains a valid feed.

Do not assume a parser returning zero items necessarily indicates that the document is the correct format.

Choose the appropriate parser using validated document structure.

Preserve legitimate empty feeds as valid.

A malformed entry should not invalidate an otherwise recoverable feed when safe recovery is possible.

## Character Encoding

Investigate the existing encoding logic.

Improve handling of:

- UTF-8
- UTF-8 BOM
- UTF-16 LE/BE
- ISO-8859-1
- Declared XML encodings
- HTTP charset declarations
- Incorrect or missing charset declarations

Do not silently corrupt Unicode text.

---

# 6. Article Normalization, Identity and Deduplication

Review article mapping from every supported feed format.

Ensure consistent handling of:

- GUID
- Atom ID
- Article URL
- Feed URL
- Missing IDs
- Missing links
- Duplicate articles
- Publication/update dates
- Article title
- Summary
- Full HTML content
- Images and media
- Categories

Article identity must remain stable across refresh cycles.

A previously read article must not become unread simply because the source changes URL formatting or metadata.

Preserve existing bookmark identities and notification tracking.

**Critical:** Do not introduce an identity migration that breaks previously stored user data.

If identity changes are unavoidable, provide a backward-compatible migration with regression tests.

---

# 7. Full-Text Extraction Reliability

Audit:

```text
lib/services/full_text_extraction_service.dart
lib/services/article_preparation_service.dart
lib/providers/article_page_provider.dart
```

A known architectural risk is the session-level failed-URL cache.

A temporary request failure can cause future automatic extraction attempts to be skipped.

Investigate the interaction between:

```text
FullTextExtractionService._failedUrls
```

and the retry/backoff mechanism in article preparation.

## Required Behavior

Separate temporary extraction failures from permanent ones.

Examples:

```text
Timeout → retry later
503 → retry later
429 → respect Retry-After
403 → mark access restricted
404 → classify unavailable
Extraction returned no useful article → retain RSS content
```

Never make an otherwise readable article unusable solely because full-text extraction failed.

Use the feed's provided HTML or summary as a fallback.

Avoid extracting full text when the feed already contains sufficient content, unless the user explicitly requests it or existing preferences require it.

Preserve per-feed and global full-text preferences.

Do not repeatedly download the same article unnecessarily.

Review extraction caches and concurrency behavior.

---

# 8. Article Rendering and Media

Audit the complete rendering process.

Investigate potential failures involving:

- HTML content
- Embedded images
- Galleries
- GIFs
- Video links
- Media RSS
- Atom XHTML
- Relative image links
- Invalid images
- Duplicate hero images
- Broken media URLs
- HTML sanitization
- Unsupported embedded elements

Reddit content can include rich media and external links.

Use structured source content whenever possible.

Never replace valid RSS content with an empty extraction result.

Ensure downloaded article HTML cannot execute unsafe content.

Maintain a clear separation between:

```text
Raw source content
Normalized article content
Extracted full-text content
Cached offline content
Rendered display content
```

Keep the existing application UI/UX intact unless a small, clearly necessary improvement is required for error visibility.

Do not redesign the app.

---

# 9. Offline Cache and Data Integrity

Dondurma is a local-first RSS reader.

This must remain a core guarantee.

Inspect how the application stores and restores:

- Feed articles
- Read/unread state
- Bookmarks
- Extracted content
- Offline images
- Conditional HTTP validators
- Redirect mappings
- Notification state
- Subscription settings

## Critical Invariants

A failed refresh must not erase existing articles.

A failed extraction must not erase readable content.

A 304 response must not unexpectedly clear the local feed.

A corrupt remote response must not replace a known-good cached result.

Background synchronization must not lose existing records.

A user upgrading from an older version must retain their data.

Avoid destructive migrations.

Any schema or persistence changes must be explicitly tested.

---

# 10. Performance Requirements

Investigate and improve actual bottlenecks rather than optimizing speculatively.

Evaluate:

- Repeated XML parsing
- HTML parsing overhead
- Main-isolate blocking
- Excessive `compute()` calls
- Unnecessary object allocations
- Duplicate network requests
- Large response buffering
- Feed refresh CPU usage
- Image caching
- Excessive provider notifications
- Article list rebuilds
- Memory usage with many subscriptions

Test scenarios with:

```text
10 feeds
50 feeds
100+ feeds
Large article bodies
Large XML documents
Slow network
Intermittent connectivity
```

Preserve responsive scrolling and navigation.

Prefer measurable improvements.

Do not introduce unnecessary dependencies or an oversized abstraction layer.

---

# 11. Mandatory Testing

Add meaningful automated tests for newly fixed behavior.

Use mocked HTTP responses and representative real-world feed fixtures.

Tests must not rely exclusively on live websites.

At minimum, test:

1. RSS 2.0 parsing.
2. RSS 1.0/RDF parsing.
3. Atom parsing.
4. JSON Feed parsing.
5. Malformed XML.
6. HTML response with HTTP 200.
7. Legitimate empty feed.
8. HTTP 304 cache reuse.
9. HTTP 403 handling.
10. HTTP 429 + Retry-After.
11. Domain-level cooldown.
12. Transient network failures.
13. Retry with exponential backoff.
14. Stable article identity.
15. Duplicate article elimination.
16. RSS content fallback after extraction failure.
17. Full-text retry after temporary failure.
18. Cache preservation after failed refresh.
19. Bookmark/read-state preservation.
20. Foreground/background scheduling interaction.
21. Reddit Atom fixtures.
22. Multiple subreddit RSS URL formats.
23. Charset and Unicode decoding.
24. Relative image and article URLs.
25. Large response limits.

Add regression tests for all verified defects.

Run existing test suites as well.

Run:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Follow repository-specific verification instructions too.

If integration or device tests cannot run in your environment, state this explicitly rather than claiming they passed.

---

# 12. Implementation Rules

These rules are mandatory:

**Do not rewrite the entire RSS reader from scratch.**

Improve the existing implementation incrementally.

Preserve:

- Flutter architecture
- Provider-based state management
- Hive persistence
- Existing UI and navigation
- Offline-first behavior
- User subscriptions
- Bookmarks
- Read/unread status
- Notifications
- Settings
- Android/iOS compatibility
- Existing RSS formats
- Current public-facing features

Additional rules:

- Avoid unrelated code refactoring.
- Avoid premature abstraction.
- Avoid unnecessary packages.
- Preserve backward compatibility.
- Avoid unnecessary API changes.
- Do not silently remove Reddit feeds.
- Do not modify `remote_data` merely to hide broken feeds.
- Do not introduce a mandatory paid API, backend, login, or proxy.
- Avoid changes that reduce user privacy.
- Prefer small, readable, testable components.
- Document design decisions where necessary.
- Verify each major change before moving forward.
- Never hide errors behind a fake success state.

If a proposed improvement creates more risk than value, document the trade-off and choose the safer implementation.

---

# 13. Definition of Done

Do not consider the task complete until:

- [ ] RSS fetch failures are properly classified.
- [ ] HTTP 429 and Retry-After are handled.
- [ ] Domain-aware request throttling works.
- [ ] Retry behavior is bounded and predictable.
- [ ] Feed parsing distinguishes valid/invalid documents.
- [ ] RSS, Atom, RDF, and JSON Feed continue working.
- [ ] Article identity remains stable.
- [ ] Cached articles survive network failures.
- [ ] Extraction failures preserve RSS content.
- [ ] Temporary extraction failures can recover.
- [ ] Reddit RSS limitations are handled gracefully.
- [ ] No aggressive or unauthorized Reddit bypass is introduced.
- [ ] Existing read/bookmark/notification behavior is preserved.
- [ ] Automated regression tests cover implemented fixes.
- [ ] Flutter analysis and available tests pass.
- [ ] Remaining limitations are accurately documented.

Every checked item must have evidence.

Do not mark an untested requirement as passed.

---

# 14. Deliverables

Implement the changes in a dedicated Git branch.

Create logically separated commits.

If repository permissions and the environment allow, open a pull request against the default branch.

**Do not merge the PR automatically.**

Provide a comprehensive final report in Turkish containing:

### A. Root Cause Analysis

What was actually broken, and why?

Separate confirmed defects from suspected risks.

### B. Changes Implemented

List each changed file, what changed, and why.

### C. Reddit Compatibility

Explain exactly which Reddit-related failures are fixed, which behaviors are improved, and which server-side restrictions remain outside the app's control.

### D. Architecture

Explain the final request, parsing, caching, extraction, and rendering workflow.

### E. Test Evidence

Provide test names, commands, actual results, and before/after comparisons where available.

### F. Performance

Report measurable improvements if benchmarks were performed. Do not fabricate numbers.

### G. Compatibility

Explain how existing users' subscriptions, cached content, bookmarks, and preferences are preserved.

### H. Remaining Risks

Explicitly list unresolved issues, unsupported scenarios, or tests that could not be executed.

### I. Review Information

Include:

```text
Branch:
Commit SHA(s):
Pull Request URL:
Changed Files:
Tests Passed:
Tests Failed:
Unverified Cases:
Known Limitations:
```

The final report must be sufficiently detailed for an independent code reviewer to verify every important change.

---

# Final Instruction

This is a production application with real users.

Prioritize **correctness, resilience, backward compatibility, and long-term maintainability** over completing the task quickly.

First understand the existing implementation, then implement evidence-backed fixes, then test thoroughly.

Do not finish with a theoretical report or superficial improvements.

The expected result is a materially more reliable RSS reader, backed by actual code changes and tests, without breaking current functionality.

When finished, provide the full Turkish technical report and all reviewable Git references.
