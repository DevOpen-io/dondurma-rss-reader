import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/notification_service.dart';
import '../services/opml_service.dart';
import '../theme/app_theme.dart';
import '../widgets/keyword_input_dialog.dart';

/// Full settings screen with sections for Appearance, Feed Management,
/// Notifications, Display & Readability, Content Filtering, and Data
/// Management (OPML import/export, cache control).
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
        _buildSectionHeader(context, l10n.displayAndReadability),
        ListTile(
          leading: const Icon(Icons.format_size),
          title: Text(l10n.fontSize),
          trailing: DropdownButton<String>(
            value: context.watch<SettingsProvider>().fontSize,
            items: [
              DropdownMenuItem(value: 'small', child: Text(l10n.fontSizeSmall)),
              DropdownMenuItem(
                value: 'medium',
                child: Text(l10n.fontSizeMedium),
              ),
              DropdownMenuItem(value: 'large', child: Text(l10n.fontSizeLarge)),
              DropdownMenuItem(value: 'xl', child: Text(l10n.fontSizeXl)),
            ],
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.only(left: 12),
            underline: const SizedBox(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                context.read<SettingsProvider>().setFontSize(newValue);
              }
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.font_download_outlined),
          title: Text(l10n.typeface),
          trailing: DropdownButton<String>(
            value: context.watch<SettingsProvider>().typeface,
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text(l10n.typefaceDefault),
              ),
              DropdownMenuItem(value: 'serif', child: Text(l10n.typefaceSerif)),
              DropdownMenuItem(
                value: 'sans-serif',
                child: Text(l10n.typefaceSansSerif),
              ),
              DropdownMenuItem(value: 'mono', child: Text(l10n.typefaceMono)),
            ],
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.only(left: 12),
            underline: const SizedBox(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                context.read<SettingsProvider>().setTypeface(newValue);
              }
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.format_line_spacing),
          title: Text(l10n.lineSpacing),
          trailing: DropdownButton<double>(
            value: context.watch<SettingsProvider>().lineSpacing,
            items: [
              DropdownMenuItem(value: 1.2, child: Text(l10n.lineSpacingTight)),
              DropdownMenuItem(value: 1.5, child: Text(l10n.lineSpacingNormal)),
              DropdownMenuItem(
                value: 1.8,
                child: Text(l10n.lineSpacingRelaxed),
              ),
            ],
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.only(left: 12),
            underline: const SizedBox(),
            onChanged: (double? newValue) {
              if (newValue != null) {
                context.read<SettingsProvider>().setLineSpacing(newValue);
              }
            },
          ),
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, l10n.contentFiltering),
        ListTile(
          leading: const Icon(Icons.filter_alt_off_outlined),
          title: Text(l10n.globalExcludedKeywords),
          subtitle: Text(l10n.globalExcludedKeywordsDesc),
          onTap: () {
            _showGlobalKeywordsDialog(context);
          },
        ),
        Divider(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        _buildSectionHeader(context, l10n.notifications),
        if (!NotificationService.instance.isSupported)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.notificationsNotSupported,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!NotificationService.instance.isSupported)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Card(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.notificationsSupportedPlatforms,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Opacity(
          opacity: NotificationService.instance.isSupported ? 1.0 : 0.4,
          child: IgnorePointer(
            ignoring: !NotificationService.instance.isSupported,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.enableNotifications),
                  subtitle: Text(l10n.enableNotificationsDesc),
                  trailing: Switch(
                    value: context
                        .watch<SettingsProvider>()
                        .notificationsEnabled,
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                    onChanged: (val) {
                      context.read<SettingsProvider>().setNotificationsEnabled(
                        val,
                      );
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(l10n.digestMode),
                  subtitle: Text(l10n.digestModeDesc),
                  trailing: DropdownButton<String>(
                    value: context.watch<SettingsProvider>().digestMode,
                    items: [
                      DropdownMenuItem<String>(
                        value: 'instant',
                        child: Text(l10n.digestInstant),
                      ),
                      DropdownMenuItem<String>(
                        value: 'daily',
                        child: Text(l10n.digestDaily),
                      ),
                      DropdownMenuItem<String>(
                        value: 'weekly',
                        child: Text(l10n.digestWeekly),
                      ),
                    ],
                    borderRadius: BorderRadius.circular(12),
                    padding: const EdgeInsets.only(left: 12),
                    onChanged:
                        context.watch<SettingsProvider>().notificationsEnabled
                        ? (String? newValue) {
                            if (newValue != null) {
                              context.read<SettingsProvider>().setDigestMode(
                                newValue,
                              );
                            }
                          }
                        : null,
                    underline: const SizedBox(),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.do_not_disturb_on_outlined),
                  title: Text(l10n.quietHours),
                  subtitle: Text(l10n.quietHoursDesc),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.quietHoursFrom,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          DropdownButton<int>(
                            value: context
                                .watch<SettingsProvider>()
                                .quietHoursStart,
                            items: List.generate(24, (i) => i)
                                .map(
                                  (h) => DropdownMenuItem<int>(
                                    value: h,
                                    child: Text(
                                      '${h.toString().padLeft(2, '0')}:00',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged:
                                context
                                    .watch<SettingsProvider>()
                                    .notificationsEnabled
                                ? (int? v) {
                                    if (v != null) {
                                      context
                                          .read<SettingsProvider>()
                                          .setQuietHoursStart(v);
                                    }
                                  }
                                : null,
                            underline: const SizedBox(),
                            isDense: true,
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.quietHoursTo,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          DropdownButton<int>(
                            value: context
                                .watch<SettingsProvider>()
                                .quietHoursEnd,
                            items: List.generate(24, (i) => i)
                                .map(
                                  (h) => DropdownMenuItem<int>(
                                    value: h,
                                    child: Text(
                                      '${h.toString().padLeft(2, '0')}:00',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged:
                                context
                                    .watch<SettingsProvider>()
                                    .notificationsEnabled
                                ? (int? v) {
                                    if (v != null) {
                                      context
                                          .read<SettingsProvider>()
                                          .setQuietHoursEnd(v);
                                    }
                                  }
                                : null,
                            underline: const SizedBox(),
                            isDense: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
          leading: const Icon(Icons.manage_search),
          title: Text(l10n.clearSearchHistory),
          subtitle: Text(l10n.clearSearchHistoryDesc),
          onTap: () async {
            await context.read<SettingsProvider>().clearSearchHistory();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.searchHistoryCleared)),
              );
            }
          },
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

  void _showGlobalKeywordsDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsProvider = context.read<SettingsProvider>();

    showDialog(
      context: context,
      builder: (context) {
        return KeywordInputDialog(
          title: l10n.globalExcludedKeywords,
          initialKeywords: settingsProvider.globalExcludedKeywords,
          onSave: (keywords) {
            settingsProvider.setGlobalExcludedKeywords(keywords);
          },
          onReset: () {
            settingsProvider.setGlobalExcludedKeywords([]);
          },
        );
      },
    );
  }
}
