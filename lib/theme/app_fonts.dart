import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Typefaces bundled under `assets/fonts` (SIL Open Font License). Nothing is
/// downloaded at runtime, so text renders the same offline and no font
/// request leaves the device.
enum AppFont {
  /// Brand typeface and the default.
  outfit('outfit', 'Outfit', 'Outfit'),

  /// Braille Institute design for low-vision legibility.
  atkinson(
    'atkinson',
    'AtkinsonHyperlegibleNext',
    'Atkinson Hyperlegible',
  ),

  /// Wide-spaced sans designed to reduce visual stress while reading.
  lexend('lexend', 'Lexend', 'Lexend'),

  /// Serif designed for long-form reading on screens.
  literata('literata', 'Literata', 'Literata'),

  /// The platform's own UI font (Roboto, San Francisco, Segoe UI…).
  system('system', null, null);

  const AppFont(this.key, this.family, this.displayName);

  /// Value stored in settings.
  final String key;

  /// Family declared in pubspec.yaml; null keeps the platform default.
  final String? family;

  /// Proper name shown in pickers; null for [system], which is localized.
  final String? displayName;

  static AppFont fromKey(String? key) =>
      values.firstWhere((font) => font.key == key, orElse: () => outfit);
}

/// Adds each bundled family's license to the app's license page, which the
/// OFL requires to travel with the fonts.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final font in AppFont.values) {
      final family = font.family;
      if (family == null) continue;
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family/OFL.txt'));
    }
  });
}

/// Article body typefaces in picker order (settings key `typeface`).
/// `'system'` follows the app font; `'serif'` and `'sans-serif'` predate the
/// bundled fonts and keep their meaning through Literata and Atkinson.
const articleTypefaces = [
  'system',
  'serif',
  'sans-serif',
  'lexend',
  'outfit',
  'mono',
];

/// Bundled font behind an article typeface key; null for `'system'` and
/// `'mono'`, which are not bundled faces.
AppFont? articleTypefaceFont(String typeface) => switch (typeface) {
  'serif' => AppFont.literata,
  'sans-serif' => AppFont.atkinson,
  'lexend' => AppFont.lexend,
  'outfit' => AppFont.outfit,
  _ => null,
};

/// Font family for the article body under [typeface] and the app font.
String? articleFontFamily(String typeface, AppFont appFont) =>
    typeface == 'mono'
    ? 'monospace'
    : (articleTypefaceFont(typeface) ?? appFont).family;

/// Platform monospace faces; Flutter resolves `monospace` only on Android.
const monospaceFallback = [
  'Menlo',
  'Consolas',
  'DejaVu Sans Mono',
  'Courier New',
  'Courier',
];
