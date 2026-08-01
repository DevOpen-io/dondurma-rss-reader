import 'package:flutter/widgets.dart';

/// A language supported by the app.
class AppLanguage {
  const AppLanguage(this.locale, this.nativeName);

  /// Locale used by [AppLocalizations] and MaterialApp.
  final Locale locale;

  /// The language's self-name (endonym), e.g. "Español" for Spanish.
  final String nativeName;
}

/// Single source of truth for the app's supported languages.
///
/// To add a new language:
/// 1. Create `lib/l10n/app_<code>.arb` with the translations.
/// 2. Append one [AppLanguage] entry here.
///
/// Both `MaterialApp.supportedLocales` and the settings language picker
/// derive from this list, so no other code needs to change.
const List<AppLanguage> supportedAppLanguages = [
  AppLanguage(Locale('en'), 'English'),
  AppLanguage(Locale('tr'), 'Türkçe'),
  AppLanguage(Locale('es'), 'Español'),
];
