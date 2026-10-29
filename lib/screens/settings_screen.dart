import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router/onboarding_state.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/supported_languages.dart';
import '../providers/bookmark_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/app_backup.dart';
import '../services/app_reset_service.dart';
import '../services/lifecycle_gate.dart';
import '../services/notification_service.dart';
import '../services/opml_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/app_toast.dart';
import '../utils/platform_caps.dart';
import '../utils/time_format.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import '../widgets/adaptive_dialog.dart';
import '../widgets/keyword_input_sheet.dart';
import '../widgets/settings/settings_widgets.dart';
import '../widgets/constrained_width.dart';
import '../theme/app_fonts.dart';
import 'legacy_archive_screen.dart';
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

    return ConstrainedWidth(
      // Desktop settings get a wider working column (~920dp); mobile keeps
      // the original 680dp cap.
      maxWidth: PlatformCaps.isDesktop ? 920 : 680,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          SettingsSectionTitle(title: l10n.general),
          SettingsCard(
            children: [
              SettingsSelectionTile<FlexScheme>(
                icon: Icons.color_lens_outlined,
                title: l10n.theme,
                value: settings.flexScheme,
                items: _kSchemes.map((s) {
                  final color =
                      FlexColor.schemes[s]?.light.primary ?? Colors.blue;
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
                onChanged: (v) =>
                    context.read<SettingsProvider>().setFlexScheme(v!),
              ),
              const SettingsTileDivider(),
              SettingsSelectionTile<ThemeMode>(
                icon: Icons.brightness_6_outlined,
                title: l10n.brightness,
                value: settings.themeMode,
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(l10n.brightnessSystem),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(l10n.brightnessLight),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(l10n.brightnessDark),
                  ),
                ],
                onChanged: (v) =>
                    context.read<SettingsProvider>().setThemeMode(v!),
              ),
              const SettingsTileDivider(),
              SettingsSelectionTile<Locale>(
                icon: Icons.language_rounded,
                title: l10n.language,
                value: settings.locale,
                items: [
                  for (final lang in supportedAppLanguages)
                    DropdownMenuItem(
                      value: lang.locale,
                      child: Text(lang.nativeName),
                    ),
                ],
                onChanged: (v) =>
                    context.read<SettingsProvider>().setLocale(v!),
              ),
              const SettingsTileDivider(),
              SettingsSelectionTile<String>(
                icon: Icons.schedule_outlined,
                title: l10n.timeFormat,
                value: settings.timeFormat,
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(l10n.timeFormatSystem),
                  ),
                  DropdownMenuItem(
                    value: '12h',
                    child: Text(l10n.timeFormat12h),
                  ),
                  DropdownMenuItem(
                    value: '24h',
                    child: Text(l10n.timeFormat24h),
                  ),
                ],
                onChanged: (v) =>
                    context.read<SettingsProvider>().setTimeFormat(v!),
              ),
            ],
          ),

          SettingsSectionTitle(title: l10n.openInBrowser),
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
                      SettingsSelectionTile<String>(
                        icon: Icons.open_in_browser_rounded,
                        title: l10n.browserMode,
                        value: effectiveMode,
                        items: [
                          DropdownMenuItem(
                            value: 'builtin',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(l10n.browserBuiltin),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'external',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
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

          SettingsSectionTitle(title: l10n.displayAndReadability),
          SettingsCard(
            children: [
              SettingsSelectionTile<AppFont>(
                icon: Icons.text_format_rounded,
                title: l10n.appFont,
                value: settings.appFont,
                items: [
                  for (final font in AppFont.values)
                    DropdownMenuItem(
                      value: font,
                      child: font == AppFont.system
                          ? Text(l10n.appFontSystem)
                          : _FontName(font),
                    ),
                ],
                onChanged: (v) =>
                    context.read<SettingsProvider>().setAppFont(v!),
              ),
              const SettingsTileDivider(),
              SettingsSelectionTile<String>(
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
              SettingsSelectionTile<String>(
                icon: Icons.font_download_outlined,
                title: l10n.typeface,
                value: settings.typeface,
                items: [
                  for (final face in articleTypefaces)
                    DropdownMenuItem(
                      value: face,
                      child: switch (face) {
                        'system' => Text(l10n.typefaceDefault),
                        'mono' => Text(
                          l10n.typefaceMono,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: monospaceFallback,
                          ),
                        ),
                        _ => _FontName(articleTypefaceFont(face)!),
                      },
                    ),
                ],
                onChanged: (v) =>
                    context.read<SettingsProvider>().setTypeface(v!),
              ),
              const SettingsTileDivider(),
              SettingsSelectionTile<double>(
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
              const SettingsTileDivider(),
              SettingsSelectionTile<String>(
                icon: Icons.view_agenda_outlined,
                title: l10n.articleListStyle,
                value: settings.articleListStyle,
                items: [
                  DropdownMenuItem(
                    value: 'cards',
                    child: Text(l10n.articleListCards),
                  ),
                  DropdownMenuItem(
                    value: 'list',
                    child: Text(l10n.articleListRows),
                  ),
                ],
                onChanged: (v) =>
                    context.read<SettingsProvider>().setArticleListStyle(v!),
              ),
              if (PlatformCaps.isDesktop) ...[
                const SettingsTileDivider(),
                SettingsSelectionTile<String>(
                  icon: Icons.unfold_more_rounded,
                  title: l10n.readingWidth,
                  value: settings.desktopReadingWidth,
                  items: [
                    DropdownMenuItem(
                      value: 'comfortable',
                      child: Text(l10n.readingWidthComfortable),
                    ),
                    DropdownMenuItem(
                      value: 'expanded',
                      child: Text(l10n.readingWidthExpanded),
                    ),
                    DropdownMenuItem(
                      value: 'full',
                      child: Text(l10n.readingWidthFull),
                    ),
                  ],
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setDesktopReadingWidth(v!),
                ),
              ],
              const SettingsTileDivider(),
              SettingsSwitchTile(
                icon: Icons.article_outlined,
                title: l10n.fullTextExtraction,
                subtitle: l10n.fullTextExtractionDesc,
                value: settings.autoFullText,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setAutoFullText(v),
              ),
              const SettingsTileDivider(),
              SettingsSwitchTile(
                icon: Icons.done_all,
                title: l10n.markReadOnScroll,
                subtitle: l10n.markReadOnScrollDesc,
                value: settings.markReadOnScroll,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setMarkReadOnScroll(v),
              ),
            ],
          ),

          SettingsSectionTitle(title: l10n.contentFiltering),
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
              const SettingsTileDivider(),
              SettingsActionTile(
                icon: Icons.done_all,
                title: l10n.readKeywords,
                subtitle: l10n.readKeywordsDesc,
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                onTap: () => _showReadKeywordsDialog(context),
              ),
            ],
          ),

          SettingsSectionTitle(title: l10n.notifications),
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
                  SettingsSelectionTile<String>(
                    icon: Icons.schedule_rounded,
                    title: l10n.digestMode,
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
                      use24Hour: use24HourFormat(context, settings.timeFormat),
                      onStartChanged: (v) => context
                          .read<SettingsProvider>()
                          .setQuietHoursStart(v),
                      onEndChanged: (v) =>
                          context.read<SettingsProvider>().setQuietHoursEnd(v),
                    ),
                  ],
                ],
              ),
            ),
          ),

          SettingsSectionTitle(title: l10n.dataAndStorage),
          SettingsCard(
            children: [
              SettingsSelectionTile<int>(
                icon: Icons.download_for_offline_outlined,
                title: l10n.offlineCacheLimit,
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
              SettingsSelectionTile<int>(
                icon: Icons.timer_outlined,
                title: l10n.autoRefreshFeeds,
                value:
                    [30, 60, 300, 1800].contains(settings.cacheIntervalSeconds)
                    ? settings.cacheIntervalSeconds
                    : 30,
                items: [
                  DropdownMenuItem(value: 30, child: Text(l10n.thirtySeconds)),
                  DropdownMenuItem(value: 60, child: Text(l10n.oneMinute)),
                  DropdownMenuItem(value: 300, child: Text(l10n.fiveMinutes)),
                  DropdownMenuItem(
                    value: 1800,
                    child: Text(l10n.thirtyMinutes),
                  ),
                ],
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setCacheIntervalSeconds(v!),
              ),
              // OS-level background scheduling exists only on mobile —
              // hiding the toggle on desktop avoids a control that does
              // nothing. The foreground sync interval above still applies.
              if (PlatformCaps.supportsBackgroundScheduler) ...[
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
            ],
          ),

          const SizedBox(height: 4),
          SettingsCard(
            children: [
              SettingsActionTile(
                icon: Icons.inventory_2_outlined,
                title: l10n.legacyArchive,
                subtitle: l10n.legacyArchiveDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LegacyArchiveScreen(),
                  ),
                ),
              ),
              const SettingsTileDivider(),
              SettingsActionTile(
                icon: Icons.delete_sweep_outlined,
                title: l10n.clearCache,
                subtitle: l10n.clearCacheDesc,
                iconColor: theme.colorScheme.error,
                onTap: () async {
                  await context.read<FeedProvider>().clearCache();
                  if (context.mounted) {
                    showAppToast(
                      l10n.cacheClearedSuccess,
                      type: AppToastType.success,
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
                    showAppToast(
                      l10n.searchHistoryCleared,
                      type: AppToastType.success,
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
                      showAppToast(
                        l10n.noSubscriptionsToExport,
                        type: AppToastType.info,
                      );
                    }
                    return;
                  }
                  final success = await OpmlService().exportOpml(subscriptions);
                  if (context.mounted) {
                    showAppToast(
                      success ? l10n.exportSuccess : l10n.exportFailed,
                      type: success ? AppToastType.success : AppToastType.error,
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
                      showAppToast(
                        l10n.noFeedsFoundOrCancelled,
                        type: AppToastType.info,
                      );
                    }
                    return;
                  }
                  if (!context.mounted) return;
                  final added = await context
                      .read<SubscriptionProvider>()
                      .importFeeds(imported);
                  if (context.mounted) {
                    showAppToast(
                      added > 0
                          ? l10n.importedFeeds(added)
                          : l10n.allFeedsExist,
                      type: added > 0
                          ? AppToastType.success
                          : AppToastType.info,
                    );
                  }
                },
              ),
              const SettingsTileDivider(),
              SettingsActionTile(
                icon: Icons.save_alt_outlined,
                title: l10n.exportBackup,
                subtitle: l10n.exportBackupDesc,
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                onTap: () async {
                  final json = exportAppBackup(
                    settings: context.read<SettingsProvider>(),
                    subscriptions: context.read<SubscriptionProvider>(),
                    bookmarks: context.read<BookmarkProvider>(),
                    feed: context.read<FeedProvider>(),
                  );
                  // The visible settings page: an iPad popover anchor that
                  // lies inside the screen wherever the list is scrolled.
                  final box = context.findRenderObject() as RenderBox?;
                  final saved = await saveBackupFile(
                    json,
                    shareOrigin: box == null
                        ? null
                        : box.localToGlobal(Offset.zero) & box.size,
                  );
                  if (saved != null && context.mounted) {
                    showAppToast(
                      saved ? l10n.backupExported : l10n.exportFailed,
                      type: saved ? AppToastType.success : AppToastType.error,
                    );
                  }
                },
              ),
              const SettingsTileDivider(),
              SettingsActionTile(
                icon: Icons.settings_backup_restore,
                title: l10n.restoreBackup,
                subtitle: l10n.restoreBackupDesc,
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                onTap: () => _restoreBackup(context),
              ),
            ],
          ),

          SettingsSectionTitle(title: l10n.about),
          SettingsCard(
            children: [
              GestureDetector(
                onLongPress: () => context.push('/debug'),
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final version = snap.hasData ? snap.data!.version : '—';
                    return SettingsActionTile(
                      icon: Icons.info_outline_rounded,
                      title: l10n.version,
                      subtitle: l10n.versionDesc,
                      trailing: Text(
                        version,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
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
                onTap: () async {
                  final info = await PackageInfo.fromPlatform();
                  if (!context.mounted) return;
                  showLicensePage(
                    context: context,
                    applicationName: l10n.appName,
                    applicationVersion: info.version,
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
        ],
      ),
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
    showAdaptiveSheet<void>(
      context,
      KeywordInputSheet(
        title: l10n.globalExcludedKeywords,
        initialKeywords: settingsProvider.globalExcludedKeywords,
        onSave: (keywords) =>
            settingsProvider.setGlobalExcludedKeywords(keywords),
        onReset: () => settingsProvider.setGlobalExcludedKeywords([]),
      ),
    );
  }

  void _showReadKeywordsDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsProvider = context.read<SettingsProvider>();
    showAdaptiveSheet<void>(
      context,
      KeywordInputSheet(
        title: l10n.readKeywords,
        initialKeywords: settingsProvider.globalReadKeywords,
        onSave: settingsProvider.setGlobalReadKeywords,
        onReset: () => settingsProvider.setGlobalReadKeywords([]),
      ),
    );
  }

  void _showFactoryResetDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    showAdaptiveSheet<void>(
      context,
      Builder(
        builder: (context) => ActionSheet(
        title: Text(l10n.factoryResetConfirmTitle),
        content: Text(l10n.factoryResetConfirmDesc),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () async {
              // This context is the dialog's and is gone after the awaits.
              final router = GoRouter.of(context);
              Navigator.of(context).pop();

              final feeds = context.read<FeedProvider>();
              final subs = context.read<SubscriptionProvider>();
              final settings = context.read<SettingsProvider>();
              final bookmarks = context.read<BookmarkProvider>();

              // One journaled reset: the intent is durable before anything
              // is deleted, and an interrupted reset finishes at next start.
              feeds.discardStateForReset();
              final bool wiped = await AppResetService.run(
                LifecycleGate.current,
                AppResetService.appStages(
                  feedStorage: feeds.wipeStorageForReset,
                ),
              );
              // Storage is empty now; providers reload their memory state.
              await bookmarks.factoryReset();
              subs.reloadAfterReset();
              feeds.finishReset();
              await settings.factoryReset();
              if (!wiped) {
                // The sidecar wipe failed — durable claims may persist
                // until the next reconcile. Say so instead of claiming a
                // clean erase (#40).
                showAppToast(
                  l10n.factoryResetPartialError,
                  type: AppToastType.error,
                );
              }

              // The reset boundary also covers session state that would
              // otherwise suppress the onboarding redirect later (#40).
              sessionOnboardingBypassed = false;
              // The reset boundary also covers what outlives the boxes:
              // local notifications and the app-owned WebView session
              // (#40). External browser/OS state is untouched.
              unawaited(NotificationService.instance.cancelAll());
              if (!kIsWeb &&
                  (defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS ||
                      defaultTargetPlatform == TargetPlatform.macOS)) {
                unawaited(WebViewCookieManager().clearCookies());
              }

              router.go('/onboarding');
            },
            // Destructive, like deleting a feed: the error color itself.
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: Text(l10n.factoryReset),
          ),
        ],
      ),
      ),
    );
  }
}


/// Picks a backup file, checks it, confirms, and merges it into the app.
Future<void> _restoreBackup(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  void problem(BackupProblem problem) => showAppToast(
    problem == BackupProblem.tooNew ? l10n.backupTooNew : l10n.backupInvalid,
    type: AppToastType.error,
  );
  final String? json;
  try {
    json = await pickBackupFile();
    if (json != null) checkAppBackup(json);
  } on BackupException catch (e) {
    return problem(e.problem);
  } catch (_) {
    // Unreadable file (not text) or a picker failure.
    return problem(BackupProblem.notABackup);
  }
  if (json == null || !context.mounted) return;
  final confirmed = await showAdaptiveSheet<bool>(
    context,
    Builder(
      builder: (dialogCtx) => ActionSheet(
        title: Text(l10n.restoreBackup),
        content: Text(l10n.restoreBackupConfirm),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.restoreAction),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final RestoreSummary summary;
  try {
    summary = await restoreAppBackup(
      json,
      settings: context.read<SettingsProvider>(),
      subscriptions: context.read<SubscriptionProvider>(),
      bookmarks: context.read<BookmarkProvider>(),
      feed: context.read<FeedProvider>(),
    );
  } catch (_) {
    return showAppToast(l10n.restoreFailed, type: AppToastType.error);
  }
  // The backup may have switched the language.
  final done = context.mounted ? AppLocalizations.of(context) : l10n;
  showAppToast(
    done.backupRestored(summary.feeds, summary.bookmarks),
    type: AppToastType.success,
  );
}

/// A bundled font's name, set in that font so the picker previews it.
class _FontName extends StatelessWidget {
  final AppFont font;
  const _FontName(this.font);

  @override
  Widget build(BuildContext context) =>
      Text(font.displayName!, style: TextStyle(fontFamily: font.family));
}
