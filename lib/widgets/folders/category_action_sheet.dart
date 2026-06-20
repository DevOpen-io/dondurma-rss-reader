import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'feed_action_sheet.dart';

class CategoryActionSheet extends StatelessWidget {
  const CategoryActionSheet({
    super.key,
    required this.category,
    required this.categoryIcon,
    required this.onMarkAllRead,
    required this.onRename,
    required this.onDelete,
  });

  final String category;
  final IconData categoryIcon;
  final VoidCallback onMarkAllRead;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, size: 20, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  FolderActionTile(
                    icon: Icons.done_all_rounded,
                    label: l10n.markAllAsRead,
                    onTap: onMarkAllRead,
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  FolderActionTile(
                    icon: Icons.drive_file_rename_outline,
                    label: l10n.renameFolder,
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                    onTap: onRename,
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  FolderActionTile(
                    icon: Icons.delete_outline,
                    label: l10n.deleteFolder,
                    color: cs.error,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
