# Notification Reliability Design

Date: 2026-08-24
Status: approved design, pending implementation

## Goal

An observed article may be claimed as new at most once. Refresh failures, lifecycle changes, foreground/background overlap, settings, cache limits, and subscription initialization must not make it new again.

Delivery is at-most-once attempt. Once claimed, an OS notification failure does not make the article eligible again.

## Scope

Included:

- feed-scoped observed history;
- seven-day retention by observation time;
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

Feed namespace prevents unrelated feeds with equal GUIDs from colliding. Entries are pruned when observation time is older than seven days. Pruning never uses publication date, `offlineCacheLimit`, cache contents, or current response size.

Only successful valid feed results enter the store. HTTP failure leaves that feed untouched. HTTP 304 does not erase or replace history.

## Claim Operation

Input is one successful feed batch plus whether feed is already initialized. Under one exclusive critical section, store:

1. reads state fresh from disk;
2. parses with fallback-safe defaults;
3. prunes observations older than seven days;
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

Only one contender can create the lock path. Existing lock causes bounded short retry/backoff. Lock metadata contains a unique owner token and creation timestamp.

Lock holder performs fresh read, prune, claim, temp write, rename. Release deletes lock in `finally`, but only after verifying metadata still matches its owner token.

### Stale-lock recovery

A lock older than a conservative stale threshold is eligible for recovery. Recovery does not blindly delete it:

1. contender reads lock metadata;
2. verifies timestamp is stale;
3. attempts atomic rename from lock path to a unique quarantine path;
4. only successful renamer owns recovery;
5. quarantine file is deleted;
6. contender retries exclusive lock creation.

Atomic rename ensures two recoverers cannot both remove the same lock. Owner-token verification prevents an old holder from deleting a successor's lock. Critical-section work is short; threshold comfortably exceeds expected file I/O time.

Lock acquisition has finite timeout. Timeout fails closed: no article is returned as newly claimed. Synchronization/cache work may continue, but notification delivery is skipped rather than risking duplicates.

## State-file durability

State and temp files share directory/filesystem. Temp filename is unique per write. Data is flushed before rename. Rename replaces destination. Orphan temp files are harmless and may be cleaned opportunistically.

Corrupt/missing state is treated conservatively: successful feeds silently initialize instead of producing historical notifications.

## Initialization and Migration

Every feed has independent `initialized` state.

- First successful fetch for any uninitialized feed records current identities and returns zero claims.
- New subscription therefore initializes silently even if other feeds are initialized.
- Failed first fetch leaves feed uninitialized; later first success remains silent.
- Null/empty new store initializes silently.
- Existing `bgKnownItemIds` signals legacy installation. Legacy IDs are not force-mapped to feeds. Current subscriptions silently initialize on first successful fetch.
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
- Cleanup failure: stale-lock recovery handles later acquisition.

## Tests

Unit tests cover:

- null/empty store and first feed initialization;
- new subscription with 50 items, then one new item;
- repeated stable article, response truncation/reappearance, restart;
- successful feed plus failed feed and alternating recovery;
- suppressed delivery settings without later backfill;
- foreground/background sequential directions;
- concurrent two-store claim against same old state, exactly one winner;
- active lock retry, stale-lock recovery, competing stale recovery, owner-safe cleanup;
- RSS/Atom empty ID handling, URL normalization, fallback stability, batch dedupe;
- HTTP 304 and mixed success/304/failure history preservation;
- cache trimming independence and seven-day pruning.

Concurrency test uses two independent store instances and simultaneous futures against same real temporary directory. It asserts exactly one combined claim for one article and validates final persisted state.

## Verification

```bash
dart format .
flutter analyze
flutter test
```

No platform integration code should change. If implementation requires platform files, relevant build/smoke verification becomes mandatory.
