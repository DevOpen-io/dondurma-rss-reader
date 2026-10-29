import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import 'adaptive_dialog.dart';

/// Asks for a name and keeps [query] as a saved search (#71); also renames
/// an existing one when [initialName] is given.
Future<void> showSaveSearchDialog(
  BuildContext context,
  String query, {
  String? initialName,
}) async {
  final l10n = AppLocalizations.of(context);
  final settings = context.read<SettingsProvider>();
  final controller = TextEditingController(text: initialName ?? query);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(initialName == null ? l10n.saveSearch : l10n.rename),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.savedSearchName),
        onSubmitted: (value) => Navigator.of(dialogCtx).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name != null) await settings.saveSearch(name, query);
}

/// The saved searches as a list section: a tap runs one, a long press
/// offers rename and delete. Nothing when there are none.
class SavedSearchList extends StatelessWidget {
  final ValueChanged<String> onOpen;
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
          ListTile(
            leading: const Icon(Icons.saved_search, size: 20),
            minLeadingWidth: 20,
            title: Text(
              search.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onOpen(search.query),
            onLongPress: () => _showActions(context, search),
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
                showSaveSearchDialog(
                  context,
                  search.query,
                  initialName: search.name,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.delete),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context.read<SettingsProvider>().removeSavedSearch(
                  search.query,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
