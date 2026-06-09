---
title: Keyword Input Bottom Sheet
date: 2026-06-09
status: approved
---

# Keyword Input Bottom Sheet

## Goal

Convert `KeywordInputDialog` (AlertDialog) to a `KeywordInputSheet` (modal bottom sheet) matching the existing bottom sheet design language used in `add_feed_dialog.dart`.

## Scope

Two call sites:
- `lib/screens/settings_screen.dart` — global excluded keywords (`_showGlobalKeywordsDialog`)
- `lib/widgets/folders/folder_dialogs.dart` — per-feed excluded keywords

## Approach

**In-place rewrite (Approach A):** Rename `keyword_input_dialog.dart` → `keyword_input_sheet.dart`, rename widget class `KeywordInputDialog` → `KeywordInputSheet`, rewrite from `AlertDialog` to bottom sheet content. Update both call sites from `showDialog` → `showModalBottomSheet`.

## Widget Structure

```
KeywordInputSheet (StatefulWidget)
  ├── title: String
  ├── initialKeywords: List<String>
  ├── onSave: Function(List<String>)
  └── onReset: VoidCallback
```

The widget returns a Column (bottom sheet content), not a dialog.

## Layout

```
Column(mainAxisSize: min)
  ├── Drag handle (36×4, onSurfaceVariant α0.3, radius 2)
  ├── Title row
  │     ├── Icon container (primaryContainer bg, radius 10, label_off_rounded icon)
  │     └── Text: title (titleMedium, w700)
  ├── Input row (AnimatedContainer, surfaceContainerHigh, radius 12, focus border)
  │     ├── Icon (label_rounded, onSurfaceVariant)
  │     ├── TextField (collapsed, no border)
  │     └── FilledButton "Add" (radius 10, shrinkWrap)
  ├── Flexible → SingleChildScrollView → Wrap (chips) OR empty state text
  └── Action row (top border separator)
        ├── TextButton "Reset" (error color)
        ├── Spacer
        ├── TextButton "Cancel"
        └── FilledButton "Save"
```

## Styling Rules (matching add_feed_dialog.dart)

| Element | Spec |
|---------|------|
| Sheet corners | `borderRadius: vertical(top: 24)` |
| Drag handle | 36×4, `onSurfaceVariant` α0.3 |
| Title icon bg | `primaryContainer`, radius 10 |
| Input bg | `surfaceContainerHigh` |
| Input border default | none |
| Input border focused | `primary`, width 2 |
| Input field | `InputDecoration.collapsed` |
| Chip delete icon | `Icons.cancel`, size 18 |
| Empty state | italic, `onSurface` α0.5, centered |
| Action row bg | `surface` |
| Action row top border | `outlineVariant` α0.4 |
| Action row padding | `fromLTRB(20, 12, 20, 24)` |
| Keyboard safe | `MediaQuery.viewInsetsOf(context).bottom` on outer padding |

## showModalBottomSheet Call

```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (ctx) => KeywordInputSheet(
    title: ...,
    initialKeywords: ...,
    onSave: ...,
    onReset: ...,
  ),
);
```

## Files Changed

| File | Change |
|------|--------|
| `lib/widgets/keyword_input_dialog.dart` | Delete (replaced) |
| `lib/widgets/keyword_input_sheet.dart` | Create (rewrite) |
| `lib/screens/settings_screen.dart` | Update import + `showDialog` → `showModalBottomSheet` |
| `lib/widgets/folders/folder_dialogs.dart` | Update import + `showDialog` → `showModalBottomSheet` |

## Success Criteria

- Bottom sheet opens from bottom with 24-radius top corners
- Drag handle visible at top
- Title icon + text visible
- Input field accepts text, Add button adds chip
- Chips display with delete × button
- Empty state shows when no keywords
- Keyboard pushes content up (no overflow)
- Reset clears all keywords
- Cancel dismisses without saving
- Save persists keywords (processes leftover text field input first)
- Both call sites (settings + folder dialogs) use the new sheet
