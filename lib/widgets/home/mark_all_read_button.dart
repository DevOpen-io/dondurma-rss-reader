import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/feed_provider.dart';

enum _Scope {
  all(null),
  olderThanDay(Duration(days: 1)),
  olderThanWeek(Duration(days: 7));

  const _Scope(this.olderThan);
  final Duration? olderThan;
}

/// Marks the current view (folder, feed, search and sheet filters) as read:
/// everything, or only articles older than a day or a week. The articles
/// are taken when the choice is made and confirmed with their count first.
class MarkAllReadButton extends StatelessWidget {
  final bool desktop;

  const MarkAllReadButton({super.key, this.desktop = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final feed = context.read<FeedProvider>();
    PopupMenuItem<_Scope> entry(_Scope scope, String label) => PopupMenuItem(
      value: scope,
      enabled: feed.unreadInView(olderThan: scope.olderThan).isNotEmpty,
      child: Text(label),
    );
    return PopupMenuButton<_Scope>(
      icon: Icon(
        Icons.done_all,
        size: desktop ? 20 : null,
        color: desktop ? cs.onSurfaceVariant : null,
      ),
      tooltip: l10n.markAllAsRead,
      itemBuilder: (_) => [
        entry(_Scope.all, l10n.markReadAll),
        entry(_Scope.olderThanDay, l10n.markReadOlderThanDay),
        entry(_Scope.olderThanWeek, l10n.markReadOlderThanWeek),
      ],
      onSelected: (scope) => _confirm(context, feed, scope),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    FeedProvider feed,
    _Scope scope,
  ) async {
    final l10n = AppLocalizations.of(context);
    final items = feed.unreadInView(olderThan: scope.olderThan);
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        content: Text(l10n.markReadConfirm(items.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.markReadAction),
          ),
        ],
      ),
    );
    if (confirmed == true) await feed.markItemsAsRead(items);
  }
}
