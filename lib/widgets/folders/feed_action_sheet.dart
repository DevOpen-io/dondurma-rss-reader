import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/subscription_provider.dart';

class FeedActionSheet extends StatelessWidget {
  const FeedActionSheet({
    super.key,
    required this.subUrl,
    required this.onMove,
    required this.onEdit,
    required this.onDelete,
  });

  final String subUrl;
  final VoidCallback onMove;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _domain(String url) {
    try {
      return Uri.parse(url).host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SubscriptionProvider>();
    final matches = sp.subscriptions.where((s) => s.url == subUrl);
    if (matches.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    final sub = matches.first;
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
                  child: Icon(Icons.rss_feed_rounded, size: 20, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.name,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _domain(sub.url),
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      sub.notificationsEnabled
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      size: 20,
                      color: sub.notificationsEnabled ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(l10n.feedNotifications, style: tt.bodyMedium),
                    trailing: Switch(
                      value: sub.notificationsEnabled,
                      onChanged: (_) => context.read<SubscriptionProvider>().toggleFeedNotifications(sub.url),
                    ),
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      sub.fullTextEnabled ? Icons.article : Icons.article_outlined,
                      size: 20,
                      color: sub.fullTextEnabled ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(l10n.fullTextToggle, style: tt.bodyMedium),
                    trailing: Switch(
                      value: sub.fullTextEnabled,
                      onChanged: (_) => context.read<SubscriptionProvider>().toggleFullText(sub.url),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  FolderActionTile(
                    icon: Icons.drive_file_move_outline,
                    label: l10n.moveToFolder,
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                    onTap: onMove,
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  FolderActionTile(
                    icon: Icons.edit_outlined,
                    label: l10n.editFeed,
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                    onTap: onEdit,
                  ),
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.2)),
                  FolderActionTile(
                    icon: Icons.delete_outline,
                    label: l10n.deleteFeed,
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

class FolderActionTile extends StatelessWidget {
  const FolderActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: effectiveColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: effectiveColor),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
