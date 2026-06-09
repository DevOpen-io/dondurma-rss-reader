# Keyword Input Bottom Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `KeywordInputDialog` (AlertDialog) with a `KeywordInputSheet` (modal bottom sheet) that matches the existing design language of `add_feed_dialog.dart`.

**Architecture:** Single widget file rewrite — `keyword_input_dialog.dart` → `keyword_input_sheet.dart`. Both call sites (`settings_screen.dart` and `folder_dialogs.dart`) switch from `showDialog` to `showModalBottomSheet`. No new abstractions; pure in-place replacement.

**Tech Stack:** Flutter, Material 3 (`ColorScheme`, `FilledButton`, `Chip`), `MediaQuery.viewInsetsOf` for keyboard safety.

---

## File Map

| Action | File |
|--------|------|
| Create | `lib/widgets/keyword_input_sheet.dart` |
| Delete | `lib/widgets/keyword_input_dialog.dart` |
| Modify | `lib/screens/settings_screen.dart` |
| Modify | `lib/widgets/folders/folder_dialogs.dart` |

---

### Task 1: Create `keyword_input_sheet.dart`

**Files:**
- Create: `lib/widgets/keyword_input_sheet.dart`

- [ ] **Step 1: Create the new widget file**

Create `lib/widgets/keyword_input_sheet.dart` with this full content:

```dart
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class KeywordInputSheet extends StatefulWidget {
  final String title;
  final List<String> initialKeywords;
  final Function(List<String>) onSave;
  final VoidCallback onReset;

  const KeywordInputSheet({
    super.key,
    required this.title,
    required this.initialKeywords,
    required this.onSave,
    required this.onReset,
  });

  @override
  State<KeywordInputSheet> createState() => _KeywordInputSheetState();
}

class _KeywordInputSheetState extends State<KeywordInputSheet> {
  late List<String> _keywords;
  final TextEditingController _controller = TextEditingController();
  bool _fieldFocused = false;

  @override
  void initState() {
    super.initState();
    _keywords = List.from(widget.initialKeywords);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final input = _controller.text.trim();
    if (input.isNotEmpty) {
      final newWords = input
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !_keywords.contains(s));
      if (newWords.isNotEmpty) {
        setState(() => _keywords.addAll(newWords));
      }
      _controller.clear();
    }
  }

  void _removeKeyword(String keyword) {
    setState(() => _keywords.remove(keyword));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.label_off_rounded,
                    color: cs.onPrimaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Input row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _fieldFocused
                      ? cs.primary
                      : cs.outlineVariant.withValues(alpha: 0.4),
                  width: _fieldFocused ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    Icons.label_rounded,
                    size: 18,
                    color: _fieldFocused ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Focus(
                      onFocusChange: (f) =>
                          setState(() => _fieldFocused = f),
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: l10n.excludedKeywordsHint,
                          hintStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                          ),
                        ),
                        onSubmitted: (_) => _addKeyword(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (_, val, _) {
                        final hasText = val.text.trim().isNotEmpty;
                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: hasText ? 1.0 : 0.35,
                          child: FilledButton(
                            onPressed: hasText ? _addKeyword : null,
                            style: FilledButton.styleFrom(
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Text(l10n.addKeyword),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Chips or empty state
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _keywords.isNotEmpty
                  ? Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: _keywords.map((keyword) {
                        return Chip(
                          label: Text(keyword),
                          onDeleted: () => _removeKeyword(keyword),
                          deleteIcon: const Icon(Icons.cancel, size: 18),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l10n.noKeywordsAdded,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          // Action row
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    widget.onReset();
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: Text(l10n.reset),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    _addKeyword();
                    widget.onSave(_keywords);
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(l10n.save),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify Dart analysis passes**

Run: `flutter analyze lib/widgets/keyword_input_sheet.dart`
Expected: no errors.

---

### Task 2: Update `settings_screen.dart`

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Swap the import**

In `lib/screens/settings_screen.dart`, replace line 14:

```dart
// OLD
import '../widgets/keyword_input_dialog.dart';

// NEW
import '../widgets/keyword_input_sheet.dart';
```

- [ ] **Step 2: Replace `_showGlobalKeywordsDialog` method**

Replace the method body at ~line 759 (the `showDialog` call):

```dart
// OLD
void _showGlobalKeywordsDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final settingsProvider = context.read<SettingsProvider>();
  showDialog(
    context: context,
    builder: (context) => KeywordInputDialog(
      title: l10n.globalExcludedKeywords,
      initialKeywords: settingsProvider.globalExcludedKeywords,
      onSave: (keywords) =>
          settingsProvider.setGlobalExcludedKeywords(keywords),
      onReset: () => settingsProvider.setGlobalExcludedKeywords([]),
    ),
  );
}

// NEW
void _showGlobalKeywordsDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final settingsProvider = context.read<SettingsProvider>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => KeywordInputSheet(
      title: l10n.globalExcludedKeywords,
      initialKeywords: settingsProvider.globalExcludedKeywords,
      onSave: (keywords) =>
          settingsProvider.setGlobalExcludedKeywords(keywords),
      onReset: () => settingsProvider.setGlobalExcludedKeywords([]),
    ),
  );
}
```

- [ ] **Step 3: Verify analysis**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: no errors.

---

### Task 3: Update `folder_dialogs.dart`

**Files:**
- Modify: `lib/widgets/folders/folder_dialogs.dart`

- [ ] **Step 1: Swap the import**

In `lib/widgets/folders/folder_dialogs.dart`, find the import for `keyword_input_dialog.dart` and replace:

```dart
// OLD
import '../../widgets/keyword_input_dialog.dart';

// NEW
import '../../widgets/keyword_input_sheet.dart';
```

- [ ] **Step 2: Replace `showDialog` call with `showModalBottomSheet`**

Find the `onTap` callback (~line 231) and replace:

```dart
// OLD
onTap: () => showDialog<void>(
  context: context,
  builder: (ctx) => KeywordInputDialog(
    title: l10n.excludedKeywords,
    initialKeywords: _keywords,
    onSave: (kw) => setState(() => _keywords = kw),
    onReset: () => setState(() => _keywords = []),
  ),
),

// NEW
onTap: () => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (ctx) => KeywordInputSheet(
    title: l10n.excludedKeywords,
    initialKeywords: _keywords,
    onSave: (kw) => setState(() => _keywords = kw),
    onReset: () => setState(() => _keywords = []),
  ),
),
```

- [ ] **Step 3: Verify analysis**

Run: `flutter analyze lib/widgets/folders/folder_dialogs.dart`
Expected: no errors.

---

### Task 4: Delete old dialog file and final check

**Files:**
- Delete: `lib/widgets/keyword_input_dialog.dart`

- [ ] **Step 1: Delete the old file**

Delete `lib/widgets/keyword_input_dialog.dart` — it has no remaining importers.

- [ ] **Step 2: Full project analysis**

Run: `flutter analyze`
Expected: no errors referencing `keyword_input_dialog`.

- [ ] **Step 3: Hot-reload and manual smoke test**

Launch the app. Test both entry points:
1. Settings screen → "Global Excluded Keywords" → tap → bottom sheet opens from bottom with drag handle, title icon, input field, Add button, chips area, Reset/Cancel/Save buttons.
2. Folder/feed edit dialog → "Excluded Keywords" row → tap → same bottom sheet opens.

Verify:
- Typing a keyword and pressing Add (or Enter) → chip appears
- Tapping chip × → chip removed
- Empty state text shown when no chips
- Keyboard opens → content shifts up, no overflow
- Reset → all chips cleared, sheet closes
- Cancel → no changes saved
- Save → keywords persisted
