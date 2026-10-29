import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../adaptive_dialog.dart';
import '../../providers/feed_provider.dart';

enum _Scope {
  all(null),
  olderThanDay(Duration(days: 1)),
  olderThanWeek(Duration(days: 7));

  const _Scope(this.olderThan);
  final Duration? olderThan;

  String label(AppLocalizations l10n) => switch (this) {
    all => l10n.markReadAll,
    olderThanDay => l10n.markReadOlderThanDay,
    olderThanWeek => l10n.markReadOlderThanWeek,
  };
}

/// Asks which unread articles of the current view (folder, feed, search and
/// sheet filters) to mark read — all, or only those older than a day or a
/// week, each with its count — and marks the chosen list. The lists are
/// taken when the sheet opens, so articles arriving meanwhile stay unread.
Future<void> showMarkReadDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final feed = context.read<FeedProvider>();
  final lists = {
    for (final scope in _Scope.values)
      scope: feed.unreadInView(olderThan: scope.olderThan),
  };
  if (lists[_Scope.all]!.isEmpty) return;
  var scope = _Scope.all;
  final confirmed = await showAdaptiveSheet<bool>(
    context,
    StatefulBuilder(
      builder: (sheetCtx, setState) => ActionSheet(
        title: Text(l10n.markAllAsRead),
        content: RadioGroup<_Scope>(
          groupValue: scope,
          onChanged: (value) => setState(() => scope = value!),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in _Scope.values)
                RadioListTile<_Scope>(
                  value: option,
                  enabled: lists[option]!.isNotEmpty,
                  // Radios line up with the sheet title.
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.label(l10n)),
                  secondary: Text('${lists[option]!.length}'),
                ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(sheetCtx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(sheetCtx).pop(true),
            child: Text(l10n.markReadAction),
          ),
        ],
      ),
    ),
  );
  if (confirmed == true) await feed.markItemsAsRead(lists[scope]!);
}

/// Desktop list toolbar entry for [showMarkReadDialog]; disabled while the
/// view has nothing unread.
class MarkAllReadButton extends StatelessWidget {
  const MarkAllReadButton({super.key});

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.select<FeedProvider, bool>(
      (p) => p.hasUnreadInView,
    );
    return IconButton(
      icon: const Icon(Icons.done_all),
      iconSize: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      tooltip: AppLocalizations.of(context).markAllAsRead,
      onPressed: hasUnread ? () => showMarkReadDialog(context) : null,
    );
  }
}
