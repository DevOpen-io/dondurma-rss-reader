import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Reusable dialog for managing a list of keywords (e.g. content exclusion
/// filters). Supports adding comma-separated keywords, removing individual
/// chips, saving, and resetting.
class KeywordInputDialog extends StatefulWidget {
  final String title;
  final List<String> initialKeywords;
  final Function(List<String>) onSave;
  final VoidCallback onReset;

  const KeywordInputDialog({
    super.key,
    required this.title,
    required this.initialKeywords,
    required this.onSave,
    required this.onReset,
  });

  @override
  State<KeywordInputDialog> createState() => _KeywordInputDialogState();
}

class _KeywordInputDialogState extends State<KeywordInputDialog> {
  late List<String> _keywords;
  final TextEditingController _controller = TextEditingController();

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
      // Split by commas to allow pasting a comma-separated list as well
      final newWords = input
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !_keywords.contains(s));

      if (newWords.isNotEmpty) {
        setState(() {
          _keywords.addAll(newWords);
        });
      }
      _controller.clear();
    }
  }

  void _removeKeyword(String keyword) {
    setState(() {
      _keywords.remove(keyword);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: l10n.addKeyword, // Will add this to ARB
                      hintText: l10n.excludedKeywordsHint,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addKeyword(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  color: Theme.of(context).colorScheme.primary,
                  iconSize: 32,
                  onPressed: _addKeyword,
                  tooltip: l10n.addKeyword,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_keywords.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
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
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  l10n.noKeywordsAdded, // Will add this to ARB
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onReset();
            Navigator.of(context).pop();
          },
          child: Text(l10n.reset),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            // Also process anything left in the text field before saving
            _addKeyword();
            widget.onSave(_keywords);
            Navigator.of(context).pop();
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
