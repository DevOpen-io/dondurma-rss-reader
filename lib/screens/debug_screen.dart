import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/bookmark_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/settings_provider.dart';

/// Hidden debug screen accessible by long-pressing the app version tile in
/// Settings. Displays Hive box sizes, background sync status, and data metrics.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final feed = context.watch<FeedProvider>();
    final bookmarks = context.watch<BookmarkProvider>();
    final subscriptions = context.watch<SubscriptionProvider>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bug_report_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(l10n.debugScreen),
          ],
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Sync Status ─────────────────────────────────────────────
          _SectionTitle(title: l10n.syncStatus, icon: Icons.sync_rounded),
          _DebugCard(
            children: [
              _InfoRow(
                icon: Icons.cloud_sync_outlined,
                label: l10n.backgroundSync,
                value: settings.syncBackground
                    ? l10n.syncActive
                    : l10n.syncInactive,
                valueColor: settings.syncBackground
                    ? Colors.green
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const _CardDivider(),
              _InfoRow(
                icon: Icons.access_time_rounded,
                label: l10n.lastSyncTime,
                value: _formatSyncTime(feed.lastSyncTime, l10n),
              ),
              const _CardDivider(),
              _InfoRow(
                icon: Icons.timer_outlined,
                label: l10n.lastSyncDuration,
                value: _formatDuration(feed.lastSyncDuration, l10n),
              ),
              if (feed.isSyncing) ...[
                const _CardDivider(),
                _InfoRow(
                  icon: Icons.sync_rounded,
                  label: l10n.syncInProgress,
                  trailing: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ── Hive Storage ────────────────────────────────────────────
          _SectionTitle(title: l10n.hiveStorage, icon: Icons.storage_rounded),
          _DebugCard(
            children: [
              _StorageRow(
                icon: Icons.settings_rounded,
                label: l10n.settingsBoxSize,
                boxName: 'settings',
              ),
              const _CardDivider(),
              _StorageRow(
                icon: Icons.rss_feed_rounded,
                label: l10n.feedsBoxSize,
                boxName: 'feeds',
              ),
              const _CardDivider(),
              _StorageRow(
                icon: Icons.bookmark_rounded,
                label: l10n.bookmarksBoxSize,
                boxName: 'bookmarks',
              ),
            ],
          ),

          // ── Data Summary ────────────────────────────────────────────
          _SectionTitle(
            title: l10n.dataSummary,
            icon: Icons.data_usage_rounded,
          ),
          _DebugCard(
            children: [
              _InfoRow(
                icon: Icons.article_outlined,
                label: l10n.totalArticlesCached,
                value: feed.items.length.toString(),
              ),
              const _CardDivider(),
              _InfoRow(
                icon: Icons.visibility_outlined,
                label: l10n.readArticles,
                value: feed.items
                    .where((i) => feed.isRead(i.id))
                    .length
                    .toString(),
              ),
              const _CardDivider(),
              _InfoRow(
                icon: Icons.bookmark_border_rounded,
                label: l10n.bookmarkedArticles,
                value: bookmarks.bookmarkedItems.length.toString(),
              ),
              const _CardDivider(),
              _InfoRow(
                icon: Icons.rss_feed_rounded,
                label: l10n.subscribedFeeds,
                value: subscriptions.subscriptions.length.toString(),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────

  String _formatSyncTime(DateTime? time, AppLocalizations l10n) {
    if (time == null) return l10n.noSyncYet;
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDuration(Duration? d, AppLocalizations l10n) {
    if (d == null) return l10n.noSyncYet;
    if (d.inSeconds >= 1) {
      return '${d.inSeconds}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
    }
    return '${d.inMilliseconds}ms';
  }
}

// =============================================================================
// Reusable debug widgets
// =============================================================================

/// Section header matching the settings screen style.
class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 20, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded card container matching settings screen style.
class _DebugCard extends StatelessWidget {
  final List<Widget> children;

  const _DebugCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Thin divider used between items inside a card.
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0,
      thickness: 0.5,
      indent: 54,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.25),
    );
  }
}

/// Row showing a label + value.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _DebugIcon(icon: icon),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing:
          trailing ??
          Text(
            value ?? '',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color:
                  valueColor ??
                  theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
    );
  }
}

/// Row that calculates and shows a Hive box's approximate size.
class _StorageRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String boxName;

  const _StorageRow({
    required this.icon,
    required this.label,
    required this.boxName,
  });

  @override
  Widget build(BuildContext context) {
    final box = Hive.box(boxName);
    final sizeBytes = _estimateBoxSize(box);
    return _InfoRow(icon: icon, label: label, value: _formatBytes(sizeBytes));
  }

  int _estimateBoxSize(Box box) {
    int total = 0;
    for (final key in box.keys) {
      final value = box.get(key);
      if (value is String) {
        total += value.length * 2; // UTF-16 approximation
      } else if (value is List) {
        total += jsonEncode(value).length;
      } else if (value is Map) {
        total += jsonEncode(value).length;
      } else if (value is bool) {
        total += 1;
      } else if (value is int) {
        total += 8;
      } else if (value is double) {
        total += 8;
      } else {
        total += value.toString().length;
      }
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Small rounded-square icon background matching settings screen style.
class _DebugIcon extends StatelessWidget {
  final IconData icon;

  const _DebugIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.primary;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: c),
    );
  }
}
