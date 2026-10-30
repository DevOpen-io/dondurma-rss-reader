import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ice_cream_rss_reader/theme/app_fonts.dart';
import 'package:ice_cream_rss_reader/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const schemes = [
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
  final font = AppFont.values.first;

  test('every scheme keeps the theme color readable where it is text', () {
    for (final scheme in schemes) {
      for (final theme in [
        AppThemeBuilder.light(scheme, font),
        AppThemeBuilder.dark(scheme, font),
      ]) {
        final cs = theme.colorScheme;
        final bg = theme.scaffoldBackgroundColor;
        final label = AppThemeBuilder.readableAccent(
          cs.primary,
          background: bg,
          fallback: cs.onSurface,
        );
        expect(
          _contrast(label, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme ${cs.brightness}',
        );
        // The reading-mode thumb and the add button carry onPrimary text.
        expect(
          _contrast(cs.onPrimary, cs.primary),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme ${cs.brightness} onPrimary',
        );
        // Both stand out from what they sit on.
        expect(
          _contrast(cs.primary, cs.surfaceContainerHigh),
          greaterThanOrEqualTo(1.5),
          reason: '$scheme ${cs.brightness} thumb on track',
        );
        expect(
          _contrast(cs.primary, bg),
          greaterThanOrEqualTo(1.5),
          reason: '$scheme ${cs.brightness} button on page',
        );
      }
    }
  });

  test('tonal controls share the theme color\'s hue in every scheme', () {
    for (final scheme in schemes) {
      for (final theme in [
        AppThemeBuilder.light(scheme, font),
        AppThemeBuilder.dark(scheme, font),
      ]) {
        final cs = theme.colorScheme;
        final primary = HSLColor.fromColor(cs.primary);
        final tonal = HSLColor.fromColor(cs.secondaryContainer);
        if (primary.saturation < 0.15) continue; // Near-grey: no hue.
        final gap = (primary.hue - tonal.hue).abs();
        expect(
          gap > 180 ? 360 - gap : gap,
          lessThan(40),
          reason: '$scheme ${cs.brightness}',
        );
      }
    }
  });

  test('an accent that reads well is kept as it is', () {
    expect(
      AppThemeBuilder.readableAccent(
        Colors.black,
        background: Colors.white,
        fallback: Colors.black,
      ),
      Colors.black,
    );
  });
}
