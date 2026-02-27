import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/opml_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 16),
        _buildSectionHeader(context, 'General'),
        ListTile(
          leading: const Icon(Icons.palette),
          title: const Text('Theme'),
          subtitle: const Text('Select application style'),
          trailing: DropdownButton<AppTheme>(
            value: context.watch<SettingsProvider>().selectedTheme,
            items: AppTheme.values.map((AppTheme theme) {
              return DropdownMenuItem<AppTheme>(
                value: theme,
                child: Text(
                  theme.displayName,
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.only(left: 12),
            onChanged: (AppTheme? newValue) {
              if (newValue != null) {
                context.read<SettingsProvider>().setTheme(newValue);
              }
            },
            underline: const SizedBox(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Language'),
          subtitle: const Text('Change the app language'),
          trailing: Text(
            'English',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          onTap: () {},
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, 'Data & Storage'),
        ListTile(
          leading: const Icon(Icons.download_for_offline),
          title: const Text('Offline Cache Limit'),
          subtitle: const Text('Recent articles kept for offline reading'),
          trailing: DropdownButton<int>(
            value: context.watch<SettingsProvider>().offlineCacheLimit,
            items: [0, 50, 100, 150, 200, 250, 300].map((int value) {
              return DropdownMenuItem<int>(
                value: value,
                child: Text(value == 0 ? 'None' : value.toString()),
              );
            }).toList(),
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.only(left: 12),
            onChanged: (int? newValue) {
              if (newValue != null) {
                context.read<SettingsProvider>().setOfflineCacheLimit(newValue);
              }
            },
            underline: const SizedBox(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Auto Refresh Feeds'),
          subtitle: const Text('How often feeds sync in background'),
          trailing: DropdownButton<int>(
            value:
                [30, 60, 300].contains(
                  context.watch<SettingsProvider>().cacheIntervalSeconds,
                )
                ? context.watch<SettingsProvider>().cacheIntervalSeconds
                : 30,
            items: const [
              DropdownMenuItem<int>(value: 30, child: Text('30 Seconds')),
              DropdownMenuItem<int>(value: 60, child: Text('1 Minute')),
              DropdownMenuItem<int>(value: 300, child: Text('5 Minutes')),
            ],
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.only(left: 12),
            onChanged: (int? newValue) {
              if (newValue != null) {
                context.read<SettingsProvider>().setCacheIntervalSeconds(
                  newValue,
                );
              }
            },
            underline: const SizedBox(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Clear Cache'),
          subtitle: const Text('Remove downloaded articles to free up space'),
          onTap: () async {
            await context.read<FeedProvider>().clearCache();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared successfully.')),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync Background'),
          subtitle: const Text('Fetch new articles while app is open'),
          trailing: Switch(
            value: context.watch<SettingsProvider>().syncBackground,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {
              context.read<SettingsProvider>().setSyncBackground(val);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Export Subscriptions (OPML)'),
          subtitle: const Text('Backup your feeds to a file'),
          onTap: () async {
            final subscriptions = context
                .read<SubscriptionProvider>()
                .subscriptions;
            if (subscriptions.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No subscriptions to export.')),
                );
              }
              return;
            }
            final success = await OpmlService().exportOpml(subscriptions);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'Subscriptions exported successfully.'
                        : 'Export failed. Please try again.',
                  ),
                ),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Import Subscriptions (OPML)'),
          subtitle: const Text('Restore feeds from an OPML file'),
          onTap: () async {
            final imported = await OpmlService().importOpml();
            if (imported.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No feeds found or import was cancelled.'),
                  ),
                );
              }
              return;
            }
            if (!context.mounted) return;
            final added = await context
                .read<SubscriptionProvider>()
                .importFeeds(imported);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    added > 0
                        ? 'Imported $added new feed${added == 1 ? '' : 's'}.'
                        : 'All feeds already exist — nothing new imported.',
                  ),
                ),
              );
            }
          },
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, 'About'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Version'),
          subtitle: const Text('Current build of Ice Cream Reader'),
          trailing: Text(
            '1.0.0',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.star_border),
          title: const Text('Rate the App'),
          subtitle: const Text('Support the development on the App Store'),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
