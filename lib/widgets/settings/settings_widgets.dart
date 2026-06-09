import 'package:flutter/material.dart';

class SettingsSectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const SettingsSectionTitle({required this.title, required this.icon, super.key});

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
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
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
        activeTrackColor: theme.colorScheme.primary,
      ),
    );
  }
}

class SettingsDropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const SettingsDropdownTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
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
        ],
      ),
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
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SettingsIcon(icon: icon, color: iconColor),
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

class SettingsQuietHoursTile extends StatelessWidget {
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

  const SettingsQuietHoursTile({
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsTimePill(
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
              SettingsTimePill(
                label: toLabel,
                hour: endHour,
                enabled: enabled,
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
  final ValueChanged<int> onChanged;

  const SettingsTimePill({
    required this.label,
    required this.hour,
    required this.enabled,
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

class SettingsIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const SettingsIcon({required this.icon, this.color, super.key});

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
