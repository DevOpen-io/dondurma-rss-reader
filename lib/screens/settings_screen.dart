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

/// Premium settings screen with grouped card sections inspired by iOS Settings.
///
/// Each section is wrapped in a rounded [Card] with a subtle surface tint,
/// giving a clean, modern look with clear visual grouping.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        // ── Appearance ──────────────────────────────────────────────────
        _SectionTitle(title: l10n.general, icon: Icons.palette_outlined),
        _SettingsCard(
          children: [
            _DropdownTile<AppTheme>(
              icon: Icons.color_lens_outlined,
              title: l10n.theme,
              value: settings.selectedTheme,
              items: AppTheme.values
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(_themeDisplayName(context, t)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => context.read<SettingsProvider>().setTheme(v!),
            ),
            const _TileDivider(),
            _DropdownTile<Locale>(
              icon: Icons.language_rounded,
              title: l10n.language,
              value: settings.locale,
              items: [
                DropdownMenuItem(
                  value: const Locale('en'),
                  child: Text(l10n.english),
                ),
                DropdownMenuItem(
                  value: const Locale('tr'),
                  child: Text(l10n.turkish),
                ),
              ],
              onChanged: (v) => context.read<SettingsProvider>().setLocale(v!),
            ),
          ],
        ),

        // ── Browser ─────────────────────────────────────────────────────
        _SectionTitle(title: l10n.openInBrowser, icon: Icons.public_outlined),
        _SettingsCard(
          children: [
            _SwitchTile(
              icon: Icons.shield_outlined,
              title: l10n.adBlocker,
              subtitle: l10n.adBlockerDesc,
              value: settings.adBlockEnabled,
              onChanged: (v) =>
                  context.read<SettingsProvider>().setAdBlockEnabled(v),
            ),
            const _TileDivider(),
            _SwitchTile(
              icon: Icons.dark_mode_outlined,
              title: l10n.webviewDarkMode,
              subtitle: l10n.webviewDarkModeDesc,
              value: settings.webviewDarkModeEnabled,
              onChanged: (v) =>
                  context.read<SettingsProvider>().setWebviewDarkModeEnabled(v),
            ),
          ],
        ),

        // ── Display & Readability ───────────────────────────────────────
        _SectionTitle(
          title: l10n.displayAndReadability,
          icon: Icons.text_fields_rounded,
        ),
        _SettingsCard(
          children: [
            _DropdownTile<String>(
              icon: Icons.format_size_rounded,
              title: l10n.fontSize,
              value: settings.fontSize,
              items: [
                DropdownMenuItem(
                  value: 'small',
                  child: Text(l10n.fontSizeSmall),
                ),
                DropdownMenuItem(
                  value: 'medium',
                  child: Text(l10n.fontSizeMedium),
                ),
                DropdownMenuItem(
                  value: 'large',
                  child: Text(l10n.fontSizeLarge),
                ),
                DropdownMenuItem(value: 'xl', child: Text(l10n.fontSizeXl)),
              ],
              onChanged: (v) =>
                  context.read<SettingsProvider>().setFontSize(v!),
            ),
            const _TileDivider(),
            _DropdownTile<String>(
              icon: Icons.font_download_outlined,
              title: l10n.typeface,
              value: settings.typeface,
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(l10n.typefaceDefault),
                ),
                DropdownMenuItem(
                  value: 'serif',
                  child: Text(l10n.typefaceSerif),
                ),
                DropdownMenuItem(
                  value: 'sans-serif',
                  child: Text(l10n.typefaceSansSerif),
                ),
                DropdownMenuItem(value: 'mono', child: Text(l10n.typefaceMono)),
              ],
              onChanged: (v) =>
                  context.read<SettingsProvider>().setTypeface(v!),
            ),
            const _TileDivider(),
            _DropdownTile<double>(
              icon: Icons.format_line_spacing_rounded,
              title: l10n.lineSpacing,
              value: settings.lineSpacing,
              items: [
                DropdownMenuItem(
                  value: 1.2,
                  child: Text(l10n.lineSpacingTight),
                ),
                DropdownMenuItem(
                  value: 1.5,
                  child: Text(l10n.lineSpacingNormal),
                ),
                DropdownMenuItem(
                  value: 1.8,
                  child: Text(l10n.lineSpacingRelaxed),
                ),
              ],
              onChanged: (v) =>
                  context.read<SettingsProvider>().setLineSpacing(v!),
            ),
          ],
        ),

        // ── Content Filtering ──────────────────────────────────────────
        _SectionTitle(
          title: l10n.contentFiltering,
          icon: Icons.filter_alt_outlined,
        ),
        _SettingsCard(
          children: [
            _ActionTile(
              icon: Icons.block_rounded,
              title: l10n.globalExcludedKeywords,
              subtitle: l10n.globalExcludedKeywordsDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onTap: () => _showGlobalKeywordsDialog(context),
            ),
          ],
        ),

        // ── Notifications ──────────────────────────────────────────────
        _SectionTitle(
          title: l10n.notifications,
          icon: Icons.notifications_outlined,
        ),
        if (!NotificationService.instance.isSupported)
          _buildNotificationWarning(context, l10n),
        Opacity(
          opacity: NotificationService.instance.isSupported ? 1.0 : 0.4,
          child: IgnorePointer(
            ignoring: !NotificationService.instance.isSupported,
            child: _SettingsCard(
              children: [
                _SwitchTile(
                  icon: Icons.notifications_active_outlined,
                  title: l10n.enableNotifications,
                  subtitle: l10n.enableNotificationsDesc,
                  value: settings.notificationsEnabled,
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setNotificationsEnabled(v),
                ),
                const _TileDivider(),
                _DropdownTile<String>(
                  icon: Icons.schedule_rounded,
                  title: l10n.digestMode,
                  subtitle: l10n.digestModeDesc,
                  value: settings.digestMode,
                  items: [
                    DropdownMenuItem(
                      value: 'instant',
                      child: Text(l10n.digestInstant),
                    ),
                    DropdownMenuItem(
                      value: 'daily',
                      child: Text(l10n.digestDaily),
                    ),
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text(l10n.digestWeekly),
                    ),
                  ],
                  onChanged: settings.notificationsEnabled
                      ? (v) =>
                            context.read<SettingsProvider>().setDigestMode(v!)
                      : null,
                ),
                const _TileDivider(),
                _QuietHoursTile(
                  icon: Icons.do_not_disturb_on_outlined,
                  title: l10n.quietHours,
                  subtitle: l10n.quietHoursDesc,
                  fromLabel: l10n.quietHoursFrom,
                  toLabel: l10n.quietHoursTo,
                  startHour: settings.quietHoursStart,
                  endHour: settings.quietHoursEnd,
                  enabled: settings.notificationsEnabled,
                  onStartChanged: (v) =>
                      context.read<SettingsProvider>().setQuietHoursStart(v),
                  onEndChanged: (v) =>
                      context.read<SettingsProvider>().setQuietHoursEnd(v),
                ),
              ],
            ),
          ),
        ),

        // ── Data & Storage ─────────────────────────────────────────────
        _SectionTitle(title: l10n.dataAndStorage, icon: Icons.storage_outlined),
        _SettingsCard(
          children: [
            _DropdownTile<int>(
              icon: Icons.download_for_offline_outlined,
              title: l10n.offlineCacheLimit,
              subtitle: l10n.offlineCacheLimitDesc,
              value: settings.offlineCacheLimit,
              items: [0, 50, 100, 150, 200, 250, 300]
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(v == 0 ? l10n.none : v.toString()),
                    ),
                  )
                  .toList(),
              onChanged: (v) =>
                  context.read<SettingsProvider>().setOfflineCacheLimit(v!),
            ),
            const _TileDivider(),
            _DropdownTile<int>(
              icon: Icons.timer_outlined,
              title: l10n.autoRefreshFeeds,
              subtitle: l10n.autoRefreshFeedsDesc,
              value: [30, 60, 300].contains(settings.cacheIntervalSeconds)
                  ? settings.cacheIntervalSeconds
                  : 30,
              items: [
                DropdownMenuItem(value: 30, child: Text(l10n.thirtySeconds)),
                DropdownMenuItem(value: 60, child: Text(l10n.oneMinute)),
                DropdownMenuItem(value: 300, child: Text(l10n.fiveMinutes)),
              ],
              onChanged: (v) =>
                  context.read<SettingsProvider>().setCacheIntervalSeconds(v!),
            ),
            const _TileDivider(),
            _SwitchTile(
              icon: Icons.sync_rounded,
              title: l10n.syncBackground,
              subtitle: l10n.syncBackgroundDesc,
              value: settings.syncBackground,
              onChanged: (v) =>
                  context.read<SettingsProvider>().setSyncBackground(v),
            ),
          ],
        ),

        // ── Actions ────────────────────────────────────────────────────
        const SizedBox(height: 4),
        _SettingsCard(
          children: [
            _ActionTile(
              icon: Icons.delete_sweep_outlined,
              title: l10n.clearCache,
              subtitle: l10n.clearCacheDesc,
              iconColor: theme.colorScheme.error,
              onTap: () async {
                await context.read<FeedProvider>().clearCache();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.cacheClearedSuccess)),
                  );
                }
              },
            ),
            const _TileDivider(),
            _ActionTile(
              icon: Icons.manage_search_rounded,
              title: l10n.clearSearchHistory,
              subtitle: l10n.clearSearchHistoryDesc,
              iconColor: theme.colorScheme.error,
              onTap: () async {
                await context.read<SettingsProvider>().clearSearchHistory();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.searchHistoryCleared)),
                  );
                }
              },
            ),
          ],
        ),

        // ── Import / Export ────────────────────────────────────────────
        const SizedBox(height: 4),
        _SettingsCard(
          children: [
            _ActionTile(
              icon: Icons.file_download_outlined,
              title: l10n.exportSubscriptions,
              subtitle: l10n.exportSubscriptionsDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
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
            const _TileDivider(),
            _ActionTile(
              icon: Icons.file_upload_outlined,
              title: l10n.importSubscriptions,
              subtitle: l10n.importSubscriptionsDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
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
                        added > 0
                            ? l10n.importedFeeds(added)
                            : l10n.allFeedsExist,
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),

        // ── Accessibility ──────────────────────────────────────────────
        _SectionTitle(
          title: l10n.accessibility,
          icon: Icons.accessibility_new_rounded,
        ),
        _SettingsCard(
          children: [
            _SwitchTile(
              icon: Icons.contrast_rounded,
              title: l10n.highContrastMode,
              subtitle: l10n.highContrastModeDesc,
              value:
                  settings.selectedTheme == AppTheme.highContrastLight ||
                  settings.selectedTheme == AppTheme.highContrastDark,
              onChanged: (val) {
                final current = context.read<SettingsProvider>().selectedTheme;
                if (val) {
                  final isDark =
                      current == AppTheme.dark ||
                      current == AppTheme.catppuccinFrappe ||
                      current == AppTheme.catppuccinMacchiato ||
                      current == AppTheme.catppuccinMocha ||
                      current == AppTheme.highContrastDark;
                  context.read<SettingsProvider>().setTheme(
                    isDark
                        ? AppTheme.highContrastDark
                        : AppTheme.highContrastLight,
                  );
                } else {
                  final isDark = current == AppTheme.highContrastDark;
                  context.read<SettingsProvider>().setTheme(
                    isDark ? AppTheme.dark : AppTheme.light,
                  );
                }
              },
            ),
          ],
        ),

        // ── About ──────────────────────────────────────────────────────
        _SectionTitle(title: l10n.about, icon: Icons.info_outline_rounded),
        _SettingsCard(
          children: [
            _ActionTile(
              icon: Icons.info_outline_rounded,
              title: l10n.version,
              subtitle: l10n.versionDesc,
              trailing: Text(
                '1.0.0',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
            ),
            const _TileDivider(),
            _ActionTile(
              icon: Icons.star_outline_rounded,
              title: l10n.rateTheApp,
              subtitle: l10n.rateTheAppDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onTap: () {},
            ),
          ],
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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
      case AppTheme.highContrastLight:
        return l10n.themeHighContrastLight;
      case AppTheme.highContrastDark:
        return l10n.themeHighContrastDark;
    }
  }

  Widget _buildNotificationWarning(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.notificationsNotSupported,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.notificationsSupportedPlatforms,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGlobalKeywordsDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsProvider = context.read<SettingsProvider>();
    showDialog(
      context: context,
      builder: (context) => KeywordInputDialog(
        title: l10n.globalExcludedKeywords,
        initialKeywords: settingsProvider.globalExcludedKeywords,
        onSave: (keywords) =>
            settingsProvider.setGlobalExcludedKeywords(keywords),
        onReset: () => settingsProvider.setGlobalExcludedKeywords([]),
      ),
    );
  }
}

// =============================================================================
// Reusable internal widgets
// =============================================================================

/// Section title with icon and label.
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

/// Rounded card container for a group of settings tiles.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

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

/// Thin divider used between items inside a [_SettingsCard].
class _TileDivider extends StatelessWidget {
  const _TileDivider();

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

/// A settings row with an icon, title, optional subtitle, and a [Switch].
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _SettingsIcon(icon: icon),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            )
          : null,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: theme.colorScheme.primary,
      ),
    );
  }
}

/// A settings row with an icon, title, optional subtitle, and a right-aligned
/// [DropdownButton].
class _DropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const _DropdownTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _SettingsIcon(icon: icon),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            )
          : null,
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(
            fontSize: 13.5,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
          icon: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          isDense: true,
        ),
      ),
    );
  }
}

/// A tappable settings tile (e.g. for navigation or actions).
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _SettingsIcon(icon: icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Quiet-hours row with two compact time pickers.
class _QuietHoursTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String fromLabel;
  final String toLabel;
  final int startHour;
  final int endHour;
  final bool enabled;
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;

  const _QuietHoursTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.fromLabel,
    required this.toLabel,
    required this.startHour,
    required this.endHour,
    required this.enabled,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _SettingsIcon(icon: icon),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimePill(
            label: fromLabel,
            hour: startHour,
            enabled: enabled,
            onChanged: onStartChanged,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '–',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ),
          _TimePill(
            label: toLabel,
            hour: endHour,
            enabled: enabled,
            onChanged: onEndChanged,
          ),
        ],
      ),
    );
  }
}

/// Compact pill-shaped time picker.
class _TimePill extends StatelessWidget {
  final String label;
  final int hour;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _TimePill({
    required this.label,
    required this.hour,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 2),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: hour,
            isDense: true,
            items: List.generate(
              24,
              (i) => DropdownMenuItem(
                value: i,
                child: Text(
                  '${i.toString().padLeft(2, '0')}:00',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            onChanged: enabled ? (v) => onChanged(v!) : null,
            icon: const SizedBox.shrink(),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small rounded-square icon background for consistency.
class _SettingsIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const _SettingsIcon({required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.colorScheme.primary;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 19, color: iconColor),
    );
  }
}
