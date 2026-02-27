import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/opml_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Returns the localized display name for the given [AppTheme].
  String _themeDisplayName(BuildContext context, AppTheme theme) {
    final l10n = AppLocalizations.of(context);
    switch (theme) {
      case AppTheme.system:
        return l10n.themeSystemDefault;
      case AppTheme.light:
        return l10n.themeLightClassic;
      case AppTheme.dark:
        return l10n.themeDarkClassic;
      case AppTheme.catppuccinLatte:
        return l10n.themeLatte;
      case AppTheme.catppuccinFrappe:
        return l10n.themeFrappe;
      case AppTheme.catppuccinMacchiato:
        return l10n.themeMacchiato;
      case AppTheme.catppuccinMocha:
        return l10n.themeMocha;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        const SizedBox(height: 16),
        _buildSectionHeader(context, l10n.general),
        ListTile(
          leading: const Icon(Icons.palette),
          title: Text(l10n.theme),
          subtitle: Text(l10n.selectAppStyle),
          trailing: DropdownButton<AppTheme>(
            value: context.watch<SettingsProvider>().selectedTheme,
            items: AppTheme.values.map((AppTheme theme) {
              return DropdownMenuItem<AppTheme>(
                value: theme,
                child: Text(
                  _themeDisplayName(context, theme),
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
          title: Text(l10n.language),
          subtitle: Text(l10n.changeAppLanguage),
          trailing: DropdownButton<Locale>(
            value: context.watch<SettingsProvider>().locale,
            items: [
              DropdownMenuItem<Locale>(
                value: const Locale('en'),
                child: Text(
                  l10n.english,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
              DropdownMenuItem<Locale>(
                value: const Locale('tr'),
                child: Text(
                  l10n.turkish,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.only(left: 12),
            underline: const SizedBox(),
            onChanged: (Locale? newValue) {
              if (newValue != null) {
                context.read<SettingsProvider>().setLocale(newValue);
              }
            },
          ),
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, l10n.dataAndStorage),
        ListTile(
          leading: const Icon(Icons.download_for_offline),
          title: Text(l10n.offlineCacheLimit),
          subtitle: Text(l10n.offlineCacheLimitDesc),
          trailing: DropdownButton<int>(
            value: context.watch<SettingsProvider>().offlineCacheLimit,
            items: [0, 50, 100, 150, 200, 250, 300].map((int value) {
              return DropdownMenuItem<int>(
                value: value,
                child: Text(value == 0 ? l10n.none : value.toString()),
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
          title: Text(l10n.autoRefreshFeeds),
          subtitle: Text(l10n.autoRefreshFeedsDesc),
          trailing: DropdownButton<int>(
            value:
                [30, 60, 300].contains(
                  context.watch<SettingsProvider>().cacheIntervalSeconds,
                )
                ? context.watch<SettingsProvider>().cacheIntervalSeconds
                : 30,
            items: [
              DropdownMenuItem<int>(value: 30, child: Text(l10n.thirtySeconds)),
              DropdownMenuItem<int>(value: 60, child: Text(l10n.oneMinute)),
              DropdownMenuItem<int>(value: 300, child: Text(l10n.fiveMinutes)),
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
          title: Text(l10n.clearCache),
          subtitle: Text(l10n.clearCacheDesc),
          onTap: () async {
            await context.read<FeedProvider>().clearCache();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.cacheClearedSuccess)));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(l10n.syncBackground),
          subtitle: Text(l10n.syncBackgroundDesc),
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
          title: Text(l10n.exportSubscriptions),
          subtitle: Text(l10n.exportSubscriptionsDesc),
          onTap: () async {
            final subscriptions = context
                .read<SubscriptionProvider>()
                .subscriptions;
            if (subscriptions.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.noSubscriptionsToExport)),
                );
              }
              return;
            }
            final success = await OpmlService().exportOpml(subscriptions);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? l10n.exportSuccess : l10n.exportFailed,
                  ),
                ),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: Text(l10n.importSubscriptions),
          subtitle: Text(l10n.importSubscriptionsDesc),
          onTap: () async {
            final imported = await OpmlService().importOpml();
            if (imported.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.noFeedsFoundOrCancelled)),
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
                    added > 0 ? l10n.importedFeeds(added) : l10n.allFeedsExist,
                  ),
                ),
              );
            }
          },
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, l10n.about),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.version),
          subtitle: Text(l10n.versionDesc),
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
          title: Text(l10n.rateTheApp),
          subtitle: Text(l10n.rateTheAppDesc),
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
