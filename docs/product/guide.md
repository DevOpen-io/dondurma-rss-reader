# Dondurma Product Guide

[Documentation index](../README.md) · [Implementation status](status.md) · [Roadmap](roadmap.md)

## Audience

Daily RSS/Atom readers valuing privacy, focus, offline access, predictable organization, and control over algorithmic discovery. UI supports English, Turkish, Spanish.

## Promise

No accounts, tracking, algorithmic timeline, or ads. Users choose sources, folders, filters, notification behavior, and reading appearance.

Success: users find, read, save, resume wanted articles without attention traps.

## Personality

Calm, capable, personal. Ice-cream identity adds warmth; functionality stays serious. Friendly utility, never noisy or childish.

## Product pillars

1. **Control:** user-defined feeds, folders, keywords, browser, sync, notifications.
2. **Focused reading:** clear hierarchy, comfortable typography, minimal chrome.
3. **Local-first privacy:** Hive storage; no account, analytics, advertising SDK.
4. **Resilience:** cache, conditional HTTP, background sync, recoverable feedback.
5. **Inclusive access:** EN/TR/ES, semantics, 48 dp targets, contrast, reduced motion, responsive widths.

## Design language

- Material 3, FlexColorScheme, Outfit typography by default. Fonts are bundled (OFL) — never fetched at runtime; users can switch the app font to Atkinson Hyperlegible, Lexend, Literata or the system font, and pick the article typeface separately. The chosen theme color washes every surface lightly (cards and sheets more than the page, more in dark mode) and drives the controls — selection, switches, chips, the add button; text stays neutral (`lib/theme/app_theme.dart`).
- Adding a feed is a labeled floating button on the Feeds and Categories tabs; it folds to its icon while a list is scrolled down. The article view keeps one control row (summary/full pill and read aloud) and ends with a card for the original page.
- Rounded surfaces, restrained elevation, consistent spacing, clear primary action.
- Article rows are rounded cards by default; Settings › Article List switches the phone layout to flat rows split by hairlines.
- No decoration without information: no tinted icon tiles, uppercase tracked micro-labels, accent bars or background blobs.
- Content leads. Decoration supports brand without competing.
- Toasts handle transient feedback; dialogs/sheets handle decisions and input.
- Wide layouts cap content width; phone layouts stay compact.

## Avoid

- Algorithmic recommendations, engagement loops, accounts, telemetry, ads, upsells
- Hidden destructive actions or ambiguous gestures
- Unlocalized UI strings or motion ignoring accessibility settings
- Dense enterprise-reader chrome

## Current boundary

Local-first feed reading. Statistics, external read-later services, advanced search, and reading queues remain backlog, not shipped features.
