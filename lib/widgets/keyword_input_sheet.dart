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
