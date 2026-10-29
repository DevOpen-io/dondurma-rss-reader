import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/saved_search.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import 'adaptive_dialog.dart';

/// Asks for a name and keeps the current search — query, scope and
/// filters — as a saved search (#71).
Future<void> saveCurrentSearch(BuildContext context) {
  final search = context.read<FeedProvider>().currentSearch('');
  return _askName(context, search.rename(search.query), isNew: true);
}

Future<void> _askName(
  BuildContext context,
  SavedSearch search, {
  required bool isNew,
}) async {
  final settings = context.read<SettingsProvider>();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _SearchNameDialog(initialName: search.name, isNew: isNew),
  );
  if (name == null) return;
  await settings.saveSearch(
    search.rename(name.trim().isEmpty ? search.query : name.trim()),
  );
}

class _SearchNameDialog extends StatefulWidget {
  final String initialName;
  final bool isNew;

  const _SearchNameDialog({required this.initialName, required this.isNew});

  @override
  State<_SearchNameDialog> createState() => _SearchNameDialogState();
}

class _SearchNameDialogState extends State<_SearchNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.isNew ? l10n.saveSearch : l10n.rename),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.savedSearchName),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// The saved searches as a list section: a tap runs one; a long press or a
/// right click offers rename and delete. Nothing when there are none.
class SavedSearchList extends StatelessWidget {
  final ValueChanged<SavedSearch> onOpen;
  final Widget Function(BuildContext context, String title) header;

  const SavedSearchList({
    super.key,
    required this.onOpen,
    required this.header,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final searches = context.select<SettingsProvider, List<SavedSearch>>(
      (s) => s.savedSearches,
    );
    if (searches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(context, l10n.savedSearches),
        for (final search in searches)
          GestureDetector(
            onSecondaryTap: () => _showActions(context, search),
            child: ListTile(
              leading: const Icon(Icons.saved_search, size: 20),
              minLeadingWidth: 20,
              title: Text(
                search.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onOpen(search),
              onLongPress: () => _showActions(context, search),
            ),
          ),
      ],
    );
  }

  void _showActions(BuildContext context, SavedSearch search) {
    final l10n = AppLocalizations.of(context);
    showAdaptiveSheet<void>(
      context,
      Builder(
        builder: (sheetCtx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.rename),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _askName(context, search, isNew: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.delete),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context.read<SettingsProvider>().removeSavedSearch(search);
              },
            ),
          ],
        ),
      ),
    );
  }
}
