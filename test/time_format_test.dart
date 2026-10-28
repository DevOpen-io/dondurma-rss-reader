import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ice_cream_rss_reader/l10n/app_localizations.dart';
import 'package:ice_cream_rss_reader/utils/time_format.dart';

void main() {
  group('resolveUse24Hour', () {
    test('system preference follows the system flag', () {
      expect(resolveUse24Hour('system', true), isTrue);
      expect(resolveUse24Hour('system', false), isFalse);
    });

    test('explicit preferences override the system flag', () {
      expect(resolveUse24Hour('12h', true), isFalse);
      expect(resolveUse24Hour('24h', false), isTrue);
    });

    test('unknown values fall back to the system flag', () {
      expect(resolveUse24Hour('bogus', true), isTrue);
      expect(resolveUse24Hour('', false), isFalse);
    });
  });

  group('formatHourLabel', () {
    test('24-hour style', () {
      expect(formatHourLabel(0, true), '00:00');
      expect(formatHourLabel(7, true), '07:00');
      expect(formatHourLabel(22, true), '22:00');
    });

    test('12-hour style', () {
      expect(formatHourLabel(0, false), '12 AM');
      expect(formatHourLabel(7, false), '7 AM');
      expect(formatHourLabel(12, false), '12 PM');
      expect(formatHourLabel(13, false), '1 PM');
      expect(formatHourLabel(22, false), '10 PM');
    });
  });

  group('articleDatePattern', () {
    test('selects clock pattern per format', () {
      expect(articleDatePattern(true), 'MMM d, yyyy  HH:mm');
      expect(articleDatePattern(false), 'MMM d, yyyy  h:mm a');
    });
  });

  group('relativeTimeLabel', () {
    final now = DateTime(2026, 10, 17, 12);
    final en = lookupAppLocalizations(const Locale('en'));
    final tr = lookupAppLocalizations(const Locale('tr'));

    // The app gets this from GlobalMaterialLocalizations.
    setUpAll(initializeDateFormatting);

    test('follows the app language', () {
      final tenMinutes = now.subtract(const Duration(minutes: 10));
      expect(relativeTimeLabel(tenMinutes, en, now: now), '10m');
      expect(relativeTimeLabel(tenMinutes, tr, now: now), '10 dk');
      expect(
        relativeTimeLabel(now.subtract(const Duration(hours: 3)), tr, now: now),
        '3 sa',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 2)), tr, now: now),
        '2 g',
      );
      expect(relativeTimeLabel(now, tr, now: now), 'şimdi');
    });

    test('small clock skew reads as now, larger skew shows the date', () {
      final skewed = now.add(const Duration(minutes: 5));
      expect(relativeTimeLabel(skewed, en, now: now), en.timeNow);
      final future = now.add(const Duration(days: 3));
      expect(relativeTimeLabel(future, en, now: now), 'Oct 20');
    });

    test('older than a week shows a localized date', () {
      final old = DateTime(2026, 9, 2);
      expect(relativeTimeLabel(old, en, now: now), 'Sep 2');
      expect(relativeTimeLabel(old, tr, now: now), '2 Eyl');
    });

    test('missing date yields an empty label', () {
      expect(relativeTimeLabel(null, en, now: now), isEmpty);
    });
  });
}
