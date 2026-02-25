import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';
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
            value: context.watch<FeedProvider>().selectedTheme,
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
            onChanged: (AppTheme? newValue) {
              if (newValue != null) {
                context.read<FeedProvider>().setTheme(newValue);
              }
            },
            underline: const SizedBox(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Language'),
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
            value: context.watch<FeedProvider>().offlineCacheLimit,
            items: [0, 50, 100, 150, 200, 250, 300].map((int value) {
              return DropdownMenuItem<int>(
                value: value,
                child: Text(value == 0 ? 'None' : value.toString()),
              );
            }).toList(),
            borderRadius: BorderRadius.circular(12),
            onChanged: (int? newValue) {
              if (newValue != null) {
                context.read<FeedProvider>().setOfflineCacheLimit(newValue);
              }
            },
            underline: const SizedBox(),
          ),
        ),
        if (context.watch<FeedProvider>().offlineCacheLimit > 0)
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Cache Interval Time'),
            subtitle: const Text('How often feeds sync automatically'),
            trailing: DropdownButton<int>(
              value: context.watch<FeedProvider>().cacheIntervalSeconds,
              items: const [
                DropdownMenuItem<int>(value: 0, child: Text('None')),
                DropdownMenuItem<int>(value: 30, child: Text('30 Seconds')),
                DropdownMenuItem<int>(value: 60, child: Text('1 Minute')),
                DropdownMenuItem<int>(value: 300, child: Text('5 Minutes')),
                DropdownMenuItem<int>(value: 600, child: Text('10 Minutes')),
              ],
              borderRadius: BorderRadius.circular(12),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  context.read<FeedProvider>().setCacheIntervalSeconds(
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
          trailing: Switch(
            value: true,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {},
          ),
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Export Subscriptions (OPML)'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Exporting OPML is not implemented yet.'),
              ),
            );
          },
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, 'About'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Version'),
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
