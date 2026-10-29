import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/time_format.dart';
import '../adaptive_dialog.dart';

class SettingsSectionTitle extends StatelessWidget {
  final String title;

  const SettingsSectionTitle({required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 24, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class SettingsTileDivider extends StatelessWidget {
  const SettingsTileDivider({super.key});

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

/// Settings title row: label + optional ⓘ button that opens the
/// description in a dialog instead of printing it under the label.
class _SettingsTileLabel extends StatelessWidget {
  final String title;
  final String? info;

  const _SettingsTileLabel(this.title, this.info);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(title, style: const TextStyle(fontSize: 15))),
        if (info != null)
          // The tooltip doubles as the semantics label; default constraints
          // keep a 48dp target on touch platforms.
          IconButton(
            onPressed: () => _showInfoDialog(context),
            tooltip: AppLocalizations.of(context).semanticSettingInfo(title),
            iconSize: 15,
            icon: Icon(
              Icons.info_outline_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
      ],
    );
  }

  void _showInfoDialog(BuildContext context) {
    showAdaptiveSheet<void>(
      context,
      Builder(
        builder: (dialogContext) => ActionSheet(
          title: Text(title),
          content: Text(info!),
          actions: [
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).okButtonLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SettingsIcon(icon: icon),
      title: _SettingsTileLabel(title, subtitle),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: theme.colorScheme.primary,
      ),
    );
  }
}

class SettingsSelectionTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const SettingsSelectionTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    final selected = items.firstWhere(
      (i) => i.value == value,
      orElse: () => items.first,
    );
    final labelColor = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SettingsIcon(icon: icon),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultTextStyle(
            style: TextStyle(
              fontSize: 13.5,
              color: labelColor,
              fontWeight: FontWeight.w500,
            ),
            child: Flexible(child: selected.child),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.expand_more_rounded, size: 18, color: labelColor),
          ),
        ],
      ),
      onTap: enabled ? () => _showOptions(context) : null,
    );
  }

  void _showOptions(BuildContext context) {
    final theme = Theme.of(context);
    showAdaptiveSheet<void>(
      context,
      Builder(
        builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      title: DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 15,
                          color: item.value == value
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                          fontWeight: item.value == value
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        child: item.child,
                      ),
                      trailing: item.value == value
                          ? Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onChanged?.call(item.value);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
      showDragHandle: true,
    );
  }
}

class SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  const SettingsActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SettingsIcon(icon: icon, color: iconColor),
      title: _SettingsTileLabel(title, subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class SettingsQuietHoursTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String fromLabel;
  final String toLabel;
  final int startHour;
  final int endHour;
  final bool enabled;
  final bool use24Hour;
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;

  const SettingsQuietHoursTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.fromLabel,
    required this.toLabel,
    required this.startHour,
    required this.endHour,
    required this.enabled,
    this.use24Hour = true,
    required this.onStartChanged,
    required this.onEndChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SettingsIcon(icon: icon),
          const SizedBox(width: 16),
          Expanded(child: _SettingsTileLabel(title, subtitle)),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsTimePill(
                label: fromLabel,
                hour: startHour,
                enabled: enabled,
                use24Hour: use24Hour,
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
              SettingsTimePill(
                label: toLabel,
                hour: endHour,
                enabled: enabled,
                use24Hour: use24Hour,
                onChanged: onEndChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsTimePill extends StatelessWidget {
  final String label;
  final int hour;
  final bool enabled;
  final bool use24Hour;
  final ValueChanged<int> onChanged;

  const SettingsTimePill({
    required this.label,
    required this.hour,
    required this.enabled,
    this.use24Hour = true,
    required this.onChanged,
    super.key,
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
                  formatHourLabel(i, use24Hour),
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

class SettingsIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const SettingsIcon({required this.icon, this.color, super.key});

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    size: 22,
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
  );
}
