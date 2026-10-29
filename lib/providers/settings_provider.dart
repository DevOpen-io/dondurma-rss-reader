import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../services/background_fetch_service.dart';
import '../theme/app_fonts.dart';

/// Manages global application settings with Hive persistence.
///
/// Settings include: theme, locale, offline cache, background sync, notification
/// preferences (master toggle, digest mode, quiet hours), display/readability
/// options (font size, typeface, line spacing), and content filtering keywords.
class SettingsProvider extends ChangeNotifier {
  FlexScheme _flexScheme = FlexScheme.material;
  ThemeMode _themeMode = ThemeMode.system;
  int _offlineCacheLimit = 50;
  int _cacheIntervalSeconds = 30;
  bool _syncBackground = true;
  Locale _locale = const Locale('en');

  // Notification settings
  bool _notificationsEnabled = true;
  String _digestMode = 'instant'; // 'instant', 'daily', 'weekly'
  bool _quietHoursEnabled = true;
  int _quietHoursStart = 22;
  int _quietHoursEnd = 7;

  // Display & Readability settings
  AppFont _appFont = AppFont.outfit;
  String _fontSize = 'medium'; // 'small', 'medium', 'large', 'xl'
  String _typeface = 'system'; // one of articleTypefaces
  double _lineSpacing = 1.5; // 1.2 (tight), 1.5 (normal), 1.8 (relaxed)

  // Content Filtering
  List<String> _globalExcludedKeywords = [];

  // Search History
  List<String> _searchHistory = [];

  // Ad Blocker
  bool _adBlockEnabled = true;

  // Webview Dark Mode
  bool _webviewDarkModeEnabled = false;

  // Browser Mode: 'builtin', 'external', 'system'
  String _browserMode = 'builtin';

  // Full-text extraction
  bool _autoFullText = false;

  // Time format: 'system', '12h', '24h'
  String _timeFormat = 'system';

  // Desktop reading column: 'comfortable' (760 cap), 'expanded' (~93% of
  // pane, capped), 'full' (pane minus padding). Desktop-only — mobile
  // reading is unaffected.
  String _desktopReadingWidth = 'expanded';

  // Article rows on the phone layout: 'cards' (rounded tiles) or 'list'
  // (flat rows split by hairlines).
  String _articleListStyle = 'cards';

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  FlexScheme get flexScheme => _flexScheme;
  ThemeMode get themeMode => _themeMode;
  int get offlineCacheLimit => _offlineCacheLimit;
  int get cacheIntervalSeconds => _cacheIntervalSeconds;
  bool get syncBackground => _syncBackground;
  Locale get locale => _locale;

  bool get notificationsEnabled => _notificationsEnabled;
  String get digestMode => _digestMode;
  bool get quietHoursEnabled => _quietHoursEnabled;
  int get quietHoursStart => _quietHoursStart;
  int get quietHoursEnd => _quietHoursEnd;

  AppFont get appFont => _appFont;
  String get fontSize => _fontSize;
  String get typeface => _typeface;
  double get lineSpacing => _lineSpacing;

  List<String> get globalExcludedKeywords => _globalExcludedKeywords;

  List<String> get searchHistory => _searchHistory;

  bool get adBlockEnabled => _adBlockEnabled;

  bool get webviewDarkModeEnabled => _webviewDarkModeEnabled;

  String get browserMode => _browserMode;

  bool get autoFullText => _autoFullText;

  String get timeFormat => _timeFormat;

  String get desktopReadingWidth => _desktopReadingWidth;

  String get articleListStyle => _articleListStyle;

  // ---------------------------------------------------------------------------
  // Hive box accessor
  // ---------------------------------------------------------------------------

  /// Lazily cached reference to the `'settings'` Hive box.
  Box get _box => Hive.box('settings');

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  SettingsProvider() {
    _loadSettings();
  }

  /// Loads all settings synchronously from the Hive box.
  ///
  /// Hive boxes are memory-mapped, so [Box.get] is a synchronous read.
  /// Running this in the constructor ensures settings are available
  /// immediately — no async gap where defaults are visible.
  void _loadSettings() {
    _offlineCacheLimit = _box.get('offlineCacheLimit', defaultValue: 50);
    final savedInterval = _box.get('cacheIntervalSeconds');
    _cacheIntervalSeconds = (savedInterval == null || savedInterval == 0)
        ? 1800
        : savedInterval;
    _syncBackground = _box.get('syncBackground', defaultValue: true);

    final schemeName =
        _box.get('flexScheme', defaultValue: 'material') as String;
    _flexScheme = FlexScheme.values.firstWhere(
      (e) => e.name == schemeName,
      orElse: () => FlexScheme.material,
    );

    final modeName = _box.get('themeMode', defaultValue: 'system') as String;
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == modeName,
      orElse: () => ThemeMode.system,
    );

    // Locale
    final savedLocale = _box.get('locale');
    if (savedLocale != null) {
      try {
        _locale = Locale(savedLocale);
      } catch (_) {
        _locale = const Locale('en');
      }
    }

    // Notification settings
    _notificationsEnabled = _box.get(
      'notificationsEnabled',
      defaultValue: true,
    );
    _digestMode = _box.get('digestMode', defaultValue: 'instant');
    _quietHoursEnabled = _box.get('quietHoursEnabled', defaultValue: true);
    _quietHoursStart = _box.get('quietHoursStart', defaultValue: 22);
    _quietHoursEnd = _box.get('quietHoursEnd', defaultValue: 7);

    // Display settings
    _appFont = AppFont.fromKey(_box.get('appFont') as String?);
    _fontSize = _box.get('fontSize', defaultValue: 'medium');
    _typeface = _box.get('typeface', defaultValue: 'system');
    _lineSpacing = _box.get('lineSpacing', defaultValue: 1.5);

    // Filtering settings
    _globalExcludedKeywords =
        (_box.get('globalExcludedKeywords') as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    // Search history
    _searchHistory =
        (_box.get('searchHistory') as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    // Ad Blocker
    _adBlockEnabled = _box.get('adBlockEnabled', defaultValue: true);

    // Webview Dark Mode
    _webviewDarkModeEnabled = _box.get(
      'webviewDarkModeEnabled',
      defaultValue: false,
    );

    // Browser Mode
    _browserMode = _box.get('browserMode', defaultValue: 'builtin');

    // Full-text extraction
    _autoFullText = _box.get('autoFullText', defaultValue: false);

    // Time format
    _timeFormat = _box.get('timeFormat', defaultValue: 'system');

    // Desktop reading width
    _desktopReadingWidth = _box.get(
      'desktopReadingWidth',
      defaultValue: 'expanded',
    );

    _articleListStyle = _box.get('articleListStyle', defaultValue: 'cards');

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Setters — each notifies listeners, then persists to Hive
  // ---------------------------------------------------------------------------

  Future<void> _store(String key, Object value) {
    notifyListeners();
    return _box.put(key, value);
  }

  Future<void> setFlexScheme(FlexScheme scheme) {
    _flexScheme = scheme;
    return _store('flexScheme', scheme.name);
  }

  Future<void> setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    return _store('themeMode', mode.name);
  }

  /// Sets the maximum number of articles cached for offline reading.
  Future<void> setOfflineCacheLimit(int limit) {
    _offlineCacheLimit = limit;
    return _store('offlineCacheLimit', limit);
  }

  /// Sets the background auto-refresh interval in seconds.
  Future<void> setCacheIntervalSeconds(int interval) {
    _cacheIntervalSeconds = interval;
    return _store('cacheIntervalSeconds', interval);
  }

  /// Enables or disables background auto-refresh.
  Future<void> setSyncBackground(bool value) async {
    _syncBackground = value;
    notifyListeners();
    await _box.put('syncBackground', value);
    // Reflect the toggle in the OS scheduler immediately so disabling stops
    // background fetches without requiring an app restart.
    if (value) {
      await registerBgFetch();
    } else {
      await Workmanager().cancelByUniqueName('rss_bg_fetch');
    }
  }

  /// Updates the app locale and persists the language code.
  Future<void> setLocale(Locale newLocale) {
    _locale = newLocale;
    return _store('locale', newLocale.languageCode);
  }

  /// Enables or disables the global notification master toggle.
  Future<void> setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    return _store('notificationsEnabled', value);
  }

  Future<void> setQuietHoursEnabled(bool value) {
    _quietHoursEnabled = value;
    return _store('quietHoursEnabled', value);
  }

  /// Sets the notification digest mode: `'instant'`, `'daily'`, or `'weekly'`.
  Future<void> setDigestMode(String mode) {
    _digestMode = mode;
    return _store('digestMode', mode);
  }

  /// Sets the hour (0-23) when the quiet period begins.
  Future<void> setQuietHoursStart(int hour) {
    _quietHoursStart = hour;
    return _store('quietHoursStart', hour);
  }

  /// Sets the hour (0-23) when the quiet period ends.
  Future<void> setQuietHoursEnd(int hour) {
    _quietHoursEnd = hour;
    return _store('quietHoursEnd', hour);
  }

  /// Sets the bundled typeface for the whole interface.
  Future<void> setAppFont(AppFont font) {
    _appFont = font;
    return _store('appFont', font.key);
  }

  /// Sets the article body font size: `'small'`, `'medium'`, `'large'`, `'xl'`.
  Future<void> setFontSize(String size) {
    _fontSize = size;
    return _store('fontSize', size);
  }

  /// Sets the article typeface, one of [articleTypefaces].
  Future<void> setTypeface(String face) {
    _typeface = face;
    return _store('typeface', face);
  }

  /// Sets the article line spacing multiplier (e.g. 1.2, 1.5, 1.8).
  Future<void> setLineSpacing(double spacing) {
    _lineSpacing = spacing;
    return _store('lineSpacing', spacing);
  }

  /// Replaces the global excluded keywords list.
  Future<void> setGlobalExcludedKeywords(List<String> keywords) {
    _globalExcludedKeywords = keywords;
    return _store('globalExcludedKeywords', keywords);
  }

  /// Enables or disables the built-in ad blocker for the in-app browser.
  Future<void> setAdBlockEnabled(bool value) {
    _adBlockEnabled = value;
    return _store('adBlockEnabled', value);
  }

  /// Enables or disables dark mode for the in-app browser.
  Future<void> setWebviewDarkModeEnabled(bool value) {
    _webviewDarkModeEnabled = value;
    return _store('webviewDarkModeEnabled', value);
  }

  /// Sets the browser mode: `'builtin'`, `'external'`, or `'system'`.
  Future<void> setBrowserMode(String mode) {
    _browserMode = mode;
    return _store('browserMode', mode);
  }

  /// Enables or disables automatic full-text extraction for all feeds.
  Future<void> setAutoFullText(bool value) {
    _autoFullText = value;
    return _store('autoFullText', value);
  }

  /// Sets the clock display format: `'system'`, `'12h'`, or `'24h'`.
  Future<void> setTimeFormat(String format) {
    _timeFormat = format;
    return _store('timeFormat', format);
  }

  /// Sets the desktop reading column mode: `'comfortable'`, `'expanded'`,
  /// or `'full'`. Only consulted by the desktop reader pane.
  Future<void> setDesktopReadingWidth(String mode) async {
    if (mode != 'comfortable' && mode != 'expanded' && mode != 'full') return;
    _desktopReadingWidth = mode;
    await _store('desktopReadingWidth', mode);
  }

  /// Sets how the phone layout draws article rows: `'cards'` or `'list'`.
  Future<void> setArticleListStyle(String style) async {
    if (style != 'cards' && style != 'list') return;
    _articleListStyle = style;
    await _store('articleListStyle', style);
  }

  /// Adds a search query to the history.
  ///
  /// Trims whitespace, ignores empty strings, removes duplicates, and
  /// caps the list at 10 entries (most-recent-first).
  Future<void> addSearchQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _searchHistory.remove(trimmed);
    _searchHistory.insert(0, trimmed);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    notifyListeners();
    await _box.put('searchHistory', _searchHistory);
  }

  /// Removes a single query from the search history.
  Future<void> removeSearchQuery(String query) async {
    _searchHistory.remove(query);
    notifyListeners();
    await _box.put('searchHistory', _searchHistory);
  }

  /// Clears the entire search history.
  Future<void> clearSearchHistory() async {
    _searchHistory = [];
    notifyListeners();
    await _box.put('searchHistory', <String>[]);
  }

  /// Clears all settings and restores default values.
  Future<void> factoryReset() async {
    await _box.clear();
    _loadSettings();
  }
}
