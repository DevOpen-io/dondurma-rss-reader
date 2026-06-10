import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/notification_service.dart';
import '../services/opml_service.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import '../widgets/keyword_input_sheet.dart';
import '../widgets/settings/settings_widgets.dart';
import 'privacy_policy_page.dart';
import 'terms_of_service_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _kSchemes = [
  FlexScheme.material,
  FlexScheme.blue,
  FlexScheme.indigo,
  FlexScheme.deepPurple,
  FlexScheme.sakura,
  FlexScheme.red,
  FlexScheme.tealM3,
  FlexScheme.green,
  FlexScheme.amber,
  FlexScheme.outerSpace,
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        SettingsSectionTitle(title: l10n.general, icon: Icons.palette_outlined),
        SettingsCard(
          children: [
            SettingsDropdownTile<FlexScheme>(
              icon: Icons.color_lens_outlined,
              title: l10n.theme,
              value: settings.flexScheme,
              items: _kSchemes.map((s) {
                final color = FlexColor.schemes[s]?.light.primary ?? Colors.blue;
                return DropdownMenuItem<FlexScheme>(
                  value: s,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(backgroundColor: color, radius: 8),
                      const SizedBox(width: 8),
                      Text(_schemeDisplayName(s)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => context.read<SettingsProvider>().setFlexScheme(v!),
            ),
            const SettingsTileDivider(),
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              leading: SettingsIcon(icon: Icons.brightness_6_outlined),
              title: Text(l10n.brightness, style: const TextStyle(fontSize: 15)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(value: ThemeMode.system, label: Text(l10n.brightnessSystem)),
                    ButtonSegment(value: ThemeMode.light, label: Text(l10n.brightnessLight)),
                    ButtonSegment(value: ThemeMode.dark, label: Text(l10n.brightnessDark)),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) =>
                      context.read<SettingsProvider>().setThemeMode(s.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity(horizontal: -2, vertical: -2),
                  ),
                ),
              ),
              isThreeLine: true,
            ),
            const SettingsTileDivider(),
            SettingsDropdownTile<Locale>(
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

        SettingsSectionTitle(title: l10n.openInBrowser, icon: Icons.public_outlined),
        Builder(
          builder: (context) {
            final isMobile =
                !kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS);

            final effectiveMode =
                (!isMobile && settings.browserMode == 'system')
                ? 'builtin'
                : settings.browserMode;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsCard(
                  children: [
                    SettingsDropdownTile<String>(
                      icon: Icons.open_in_browser_rounded,
                      title: l10n.browserMode,
                      subtitle: l10n.browserModeDesc,
                      value: effectiveMode,
                      items: [
                        DropdownMenuItem(
                          value: 'builtin',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(l10n.browserBuiltin),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'external',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(l10n.browserExternal),
                          ),
                        ),
                        if (isMobile)
                          DropdownMenuItem(
                            value: 'system',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(l10n.browserSystem),
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          context.read<SettingsProvider>().setBrowserMode(v!),
                    ),
                    const SettingsTileDivider(),
                    Opacity(
                      opacity: effectiveMode == 'builtin' ? 1.0 : 0.4,
                      child: IgnorePointer(
                        ignoring: effectiveMode != 'builtin',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SettingsSwitchTile(
                              icon: Icons.shield_outlined,
                              title: l10n.adBlocker,
                              subtitle: l10n.adBlockerDesc,
                              value: settings.adBlockEnabled,
                              onChanged: (v) => context
                                  .read<SettingsProvider>()
                                  .setAdBlockEnabled(v),
                            ),
                            const SettingsTileDivider(),
                            SettingsSwitchTile(
                              icon: Icons.dark_mode_outlined,
                              title: l10n.webviewDarkMode,
                              subtitle: l10n.webviewDarkModeDesc,
                              value: settings.webviewDarkModeEnabled,
                              onChanged: (v) => context
                                  .read<SettingsProvider>()
                                  .setWebviewDarkModeEnabled(v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isMobile)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: theme.colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.browserSystemMobileOnly,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),

        SettingsSectionTitle(
          title: l10n.displayAndReadability,
          icon: Icons.text_fields_rounded,
        ),
        SettingsCard(
          children: [
            SettingsDropdownTile<String>(
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
            const SettingsTileDivider(),
            SettingsDropdownTile<String>(
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
            const SettingsTileDivider(),
            SettingsDropdownTile<double>(
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

        SettingsSectionTitle(
          title: l10n.contentFiltering,
          icon: Icons.filter_alt_outlined,
        ),
        SettingsCard(
          children: [
            SettingsActionTile(
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

        SettingsSectionTitle(
          title: l10n.notifications,
          icon: Icons.notifications_outlined,
        ),
        if (!NotificationService.instance.isSupported)
          _buildNotificationWarning(context, l10n),
        Opacity(
          opacity: NotificationService.instance.isSupported ? 1.0 : 0.4,
          child: IgnorePointer(
            ignoring: !NotificationService.instance.isSupported,
            child: SettingsCard(
              children: [
                SettingsSwitchTile(
                  icon: Icons.notifications_active_outlined,
                  title: l10n.enableNotifications,
                  subtitle: l10n.enableNotificationsDesc,
                  value: settings.notificationsEnabled,
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setNotificationsEnabled(v),
                ),
                const SettingsTileDivider(),
                SettingsDropdownTile<String>(
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
                const SettingsTileDivider(),
                SettingsSwitchTile(
                  icon: Icons.do_not_disturb_on_outlined,
                  title: l10n.quietHoursEnabled,
                  value: settings.quietHoursEnabled,
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setQuietHoursEnabled(v),
                ),
                if (settings.quietHoursEnabled) ...[
                  const SettingsTileDivider(),
                  SettingsQuietHoursTile(
                    icon: Icons.schedule_outlined,
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
              ],
            ),
          ),
        ),

        SettingsSectionTitle(title: l10n.dataAndStorage, icon: Icons.storage_outlined),
        SettingsCard(
          children: [
            SettingsDropdownTile<int>(
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
            const SettingsTileDivider(),
            SettingsDropdownTile<int>(
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
            const SettingsTileDivider(),
            SettingsSwitchTile(
              icon: Icons.sync_rounded,
              title: l10n.syncBackground,
              subtitle: l10n.syncBackgroundDesc,
              value: settings.syncBackground,
              onChanged: (v) =>
                  context.read<SettingsProvider>().setSyncBackground(v),
            ),
          ],
        ),

        const SizedBox(height: 4),
        SettingsCard(
          children: [
            SettingsActionTile(
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
            const SettingsTileDivider(),
            SettingsActionTile(
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
            const SettingsTileDivider(),
            SettingsActionTile(
              icon: Icons.warning_amber_rounded,
              title: l10n.factoryReset,
              subtitle: l10n.factoryResetDesc,
              iconColor: theme.colorScheme.error,
              onTap: () => _showFactoryResetDialog(context),
            ),
          ],
        ),

        const SizedBox(height: 4),
        SettingsCard(
          children: [
            SettingsActionTile(
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
            const SettingsTileDivider(),
            SettingsActionTile(
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

        SettingsSectionTitle(title: l10n.about, icon: Icons.info_outline_rounded),
        SettingsCard(
          children: [
            GestureDetector(
              onLongPress: () => context.push('/debug'),
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) {
                  final version = snap.hasData
                      ? snap.data!.version
                      : '—';
                  return SettingsActionTile(
                    icon: Icons.info_outline_rounded,
                    title: l10n.version,
                    subtitle: l10n.versionDesc,
                    trailing: Text(
                      version,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SettingsTileDivider(),
            SettingsActionTile(
              icon: Icons.people_outline_rounded,
              title: l10n.developerInfo,
              subtitle: l10n.developerInfoDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onTap: () {
                launchUrl(Uri.parse('https://github.com/DevOpen-io'));
              },
            ),
            const SettingsTileDivider(),
            SettingsActionTile(
              icon: Icons.email_outlined,
              title: l10n.contactUs,
              subtitle: l10n.contactUsDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onTap: () {
                launchUrl(Uri.parse('mailto:info@devopen.io'));
              },
            ),
            const SettingsTileDivider(),
            SettingsActionTile(
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

        const SizedBox(height: 4),
        SettingsCard(
          children: [
            SettingsActionTile(
              icon: Icons.privacy_tip_outlined,
              title: l10n.privacyPolicy,
              subtitle: l10n.privacyPolicyDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyPage(),
                  ),
                );
              },
            ),
            const SettingsTileDivider(),
            SettingsActionTile(
              icon: Icons.description_outlined,
              title: l10n.termsOfService,
              subtitle: l10n.termsOfServiceDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TermsOfServicePage(),
                  ),
                );
              },
            ),
            const SettingsTileDivider(),
            SettingsActionTile(
              icon: Icons.source_outlined,
              title: l10n.openSourceLicenses,
              subtitle: l10n.openSourceLicensesDesc,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: l10n.appName,
                  applicationVersion: '1.0.0',
                  applicationIcon: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/logo.ico',
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 90),
      ],
    );
  }

  String _schemeDisplayName(FlexScheme s) {
    return s.name
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .trim()
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => KeywordInputSheet(
        title: l10n.globalExcludedKeywords,
        initialKeywords: settingsProvider.globalExcludedKeywords,
        onSave: (keywords) =>
            settingsProvider.setGlobalExcludedKeywords(keywords),
        onReset: () => settingsProvider.setGlobalExcludedKeywords([]),
      ),
    );
  }

  void _showFactoryResetDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.factoryResetConfirmTitle),
        content: Text(l10n.factoryResetConfirmDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: () async {
              Navigator.of(context).pop();

              final feeds = context.read<FeedProvider>();
              final subs = context.read<SubscriptionProvider>();
              final settings = context.read<SettingsProvider>();
              final bookmarks = context.read<BookmarkProvider>();

              await bookmarks.factoryReset();
              await subs.factoryReset();
              await feeds.factoryReset();
              await settings.factoryReset();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.factoryResetSuccess)),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            child: Text(l10n.factoryReset),
          ),
        ],
      ),
    );
  }
}
