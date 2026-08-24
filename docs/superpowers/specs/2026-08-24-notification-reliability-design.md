# Notification Reliability Design

Date: 2026-08-24
Status: implemented

## Goal

An article identity may be claimed as new at most once within the observed-history retention window. Refresh failures, lifecycle changes, foreground/background overlap, settings, cache limits, and subscription initialization must not make it new again during that window.

Delivery is at-most-once attempt. Once claimed, an OS notification failure does not make the article eligible again.

## Scope

Included:

- feed-scoped observed history;
- fourteen-day retention by observation time, safely exceeding the 48-hour notification eligibility window;
- silent first-feed initialization and legacy migration;
- successful-feed-only state changes;
- cross-isolate exclusive claim;
- conservative RSS/Atom identity hardening;
- foreground/background flow integration and regression tests.

Excluded:

- cooldown/rate-limit changes;
- notification grouping or ID changes;
- digest scheduling;
- notification UI/settings changes;
- delivery retries.

## Observed State

`ObservedArticleStore` owns durable notification identity state independently from Hive article cache and current feed response windows.

Conceptual schema:

```json
{
  "schema": 1,
  "feeds": {
    "normalized-feed-url": {
      "initialized": true,
      "articles": {
        "article-identity": "2026-08-24T10:00:00.000Z"
      }
    }
  }
}
```

Feed namespace combines normalized feed URL with a persisted subscription epoch. This prevents unrelated feeds with equal GUIDs from colliding and makes every new subscription—including unsubscribe/resubscribe of the same URL—initialize silently. Entries are pruned when last observation time is older than fourteen days, seven times the 48-hour notification eligibility window. Pruning never uses publication date, `offlineCacheLimit`, cache contents, or current response size.

Only successful valid feed results enter the store. HTTP failure leaves that feed untouched. HTTP 304 does not erase or replace history and cannot initialize an uninitialized namespace from cached items; only an authoritative HTTP 200 response may initialize it.

## Claim Operation

Input is one successful feed batch plus whether feed is already initialized. Under one exclusive critical section, store:

1. reads state fresh from disk;
2. parses with fallback-safe defaults;
3. prunes observations older than fourteen days;
4. deduplicates batch identities;
5. if feed is uninitialized, records all items and returns no claims;
6. otherwise records absent identities and returns those identities as claimed;
7. writes complete state to a unique temp file in same directory;
8. renames temp file over state file atomically.

Claim occurs before delivery checks. Global/per-feed notification switches, quiet hours, and digest mode control only delivery. Suppressed articles stay observed and never backfill.

## Cross-Isolate Mutual Exclusion

Advisory `RandomAccessFile.lock()` is not used.

Lock ownership uses atomic filesystem creation:

```text
File.create(exclusive: true)
```

Only one contender can create the lock path. Existing lock causes bounded short retry/backoff. Lock metadata contains a unique owner token and creation timestamp for diagnostics only.

Lock holder performs fresh read, prune, claim, temp write, rename. Release deletes lock in `finally`, but only after verifying metadata still matches its owner token.

Runtime contention never steals, renames, or deletes another owner's lock based on age. Existing lock causes bounded retry/backoff. Acquisition timeout fails closed: no article is returned as newly claimed. Synchronization/cache work may continue, but notification delivery is skipped rather than risking duplicates.

Cross-platform owner-death detection cannot be guaranteed without more infrastructure. Version 1 therefore performs no runtime stale-lock recovery. A process crash may leave an orphan lock that suppresses future notification claims until controlled cleanup or app-data reset. Missing notifications are preferred over duplicate notifications. Controlled startup cleanup may be considered later only if it can prove no holder is active.

## State-file durability

State and temp files share directory/filesystem. Temp filename is unique per write. Data is flushed before rename. Rename replaces destination. Orphan temp files are harmless and may be cleaned opportunistically.

Corrupt/missing state is treated conservatively: successful feeds silently initialize instead of producing historical notifications.

## Initialization and Migration

Every feed has independent `initialized` state.

- First successful fetch for any uninitialized feed records current identities and returns zero claims.
- New subscription therefore initializes silently even if other feeds are initialized.
- Failed first fetch leaves feed uninitialized; later first success remains silent.
- Null/empty new store initializes silently.
- Existing subscriptions missing an epoch deserialize to `legacy-v1`; newly created subscriptions receive a unique persisted epoch. Existing `bgKnownItemIds` remains legacy evidence but its global IDs are not force-mapped to feeds. Each `legacy-v1` feed silently initializes on first successful fetch.
- Absence of legacy state also uses silent initialization. This covers fresh installs.
- Legacy key remains readable during migration but is no longer notification authority.

Historical notification loss during update is preferred over storm risk.

## Identity

Feed key uses conservative URL normalization:

- trim whitespace;
- lowercase HTTP(S) scheme and host;
- remove fragment;
- remove default ports;
- preserve path and query;
- preserve non-HTTP identifiers except trimming.

Article identity selection:

1. non-empty trimmed RSS GUID or Atom ID;
2. normalized non-empty article URL;
3. existing fallback inputs: normalized feed URL, title, raw publication/update value.

Stable publisher IDs remain preferred, so title/content changes do not affect identity when GUID/Atom ID exists. Empty IDs are rejected. Batch candidates are deduplicated within feed namespace.

Migration does not reinterpret old IDs into new per-feed identities; silent initialization prevents format changes from generating update-time alerts.

## Foreground Flow

```text
successful feed result
claim batch in ObservedArticleStore
first load/uninitialized feed returns no claims
apply 48-hour/pubDate eligibility
apply per-feed/global/digest/quiet delivery rules
attempt notification
```

`_hasLoadedOnce` may remain UI/lifecycle metadata but cannot prevent observation advancement. HTTP 304 and failure preserve history. Foreground refresh coalescing remains unchanged.

## Background Flow

Background fetch does not return early for notification settings. It reads subscriptions, fetches feeds, updates cache/widgets as before, and submits each successful feed result to store. Failed results are omitted from claims and state changes.

After claims, background applies global, digest, quiet-hours, per-feed, publication-date, and 48-hour checks. Suppressed claims remain observed.

## Error Handling

- Feed failure: preserve observed state.
- State parse failure: silent initialize successful feed; no historical delivery.
- Lock timeout: skip claims/delivery; never claim without exclusion.
- State write failure: return no claims.
- Notification failure: claimed state remains; no retry.
- Cleanup failure: later acquisitions fail closed; version 1 does not steal an orphan lock.

## Tests

Unit tests cover:

- null/empty store and first feed initialization;
- new subscription with 50 items, then one new item;
- repeated stable article, response truncation/reappearance, restart;
- successful feed plus failed feed and alternating recovery;
- suppressed delivery settings without later backfill;
- foreground/background sequential directions;
- concurrent two-store claim against same old state, exactly one winner;
- active lock retry, timeout without lock stealing, and owner-safe cleanup;
- RSS/Atom empty ID handling, URL normalization, fallback stability, batch dedupe;
- HTTP 304 and mixed success/304/failure history preservation;
- cache trimming independence and fourteen-day pruning;
- article leaves and re-enters a response inside retention, producing zero new claim.

Concurrency tests use two independent store instances against the same real temporary directory. One starts simultaneous claims and asserts exactly one combined claim. Another holds the first critical section open, verifies the second contender times out without stealing the lock, then verifies exactly one claim and valid persisted state.

## Remaining risks

- Bounded history is deliberate. If a publisher reintroduces the same stable article after its identity has been pruned beyond fourteen days, it may be observed again. The 48-hour publication-date eligibility normally prevents delivery, but a publisher that also changes/recenters the date can make it eligible.
- A crash while holding the exclusive-creation lock can leave an orphan lock. Version 1 fails closed until controlled cleanup or app-data reset because correctness is preferred over liveness.

## Verification

```bash
dart format .
flutter analyze
flutter test
```

No platform integration code should change. If implementation requires platform files, relevant build/smoke verification becomes mandatory.
