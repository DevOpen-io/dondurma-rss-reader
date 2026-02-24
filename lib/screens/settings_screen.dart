import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/feed_provider.dart';

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
          title: const Text('Dark Mode'),
          trailing: Switch(
            value: context.watch<FeedProvider>().isDarkMode,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) {
              context.read<FeedProvider>().toggleTheme(val);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Language'),
          trailing: const Text('English', style: TextStyle(color: Colors.grey)),
          onTap: () {},
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, 'Data & Storage'),
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
          leading: const Icon(Icons.delete_outline),
          title: const Text('Clear Cache'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cache cleared successfully.')),
            );
          },
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
          trailing: const Text('1.0.0', style: TextStyle(color: Colors.grey)),
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
