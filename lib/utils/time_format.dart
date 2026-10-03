import 'package:flutter/widgets.dart';

/// Resolves the effective 24-hour clock flag from the user's `timeFormat`
/// preference ('system' | '12h' | '24h') and the system clock setting.
bool resolveUse24Hour(String timeFormat, bool system24Hour) {
  return switch (timeFormat) {
    '12h' => false,
    '24h' => true,
    _ => system24Hour,
  };
}

/// Effective 24-hour flag for the current [context] and provider preference.
bool use24HourFormat(BuildContext context, String timeFormat) {
  return resolveUse24Hour(
    timeFormat,
    MediaQuery.of(context).alwaysUse24HourFormat,
  );
}

/// '22:00' for 24-hour clocks, '10 PM' for 12-hour clocks.
String formatHourLabel(int hour, bool use24Hour) {
  if (use24Hour) return '${hour.toString().padLeft(2, '0')}:00';
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h ${hour < 12 ? 'AM' : 'PM'}';
}

/// intl pattern for article timestamps under the given clock format.
String articleDatePattern(bool use24Hour) {
  return use24Hour ? 'MMM d, yyyy  HH:mm' : 'MMM d, yyyy  h:mm a';
}
