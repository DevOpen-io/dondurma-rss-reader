import 'package:flutter_test/flutter_test.dart';
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
}
