import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

/// Manages global application settings with Hive persistence.
///
/// Settings include: theme, locale, offline cache, background sync, notification
/// preferences (master toggle, digest mode, quiet hours), display/readability
/// options (font size, typeface, line spacing), and content filtering keywords.
class SettingsProvider extends ChangeNotifier {
  AppTheme _selectedTheme = AppTheme.system;
  int _offlineCacheLimit = 50;
  int _cacheIntervalSeconds = 30;
  bool _syncBackground = true;
  Locale _locale = const Locale('en');

  // Notification settings
  bool _notificationsEnabled = true;
  String _digestMode = 'instant'; // 'instant', 'daily', 'weekly'
  int _quietHoursStart = 22;
  int _quietHoursEnd = 7;

  // Display & Readability settings
  String _fontSize = 'medium'; // 'small', 'medium', 'large', 'xl'
  String _typeface = 'system'; // 'system', 'serif', 'sans-serif', 'mono'
  double _lineSpacing = 1.5; // 1.2 (tight), 1.5 (normal), 1.8 (relaxed)

  // Content Filtering
  List<String> _globalExcludedKeywords = [];

  // Search History
  List<String> _searchHistory = [];

  // Ad Blocker
  bool _adBlockEnabled = true;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  AppTheme get selectedTheme => _selectedTheme;
  int get offlineCacheLimit => _offlineCacheLimit;
  int get cacheIntervalSeconds => _cacheIntervalSeconds;
  bool get syncBackground => _syncBackground;
  Locale get locale => _locale;

  bool get notificationsEnabled => _notificationsEnabled;
  String get digestMode => _digestMode;
  int get quietHoursStart => _quietHoursStart;
  int get quietHoursEnd => _quietHoursEnd;

  String get fontSize => _fontSize;
  String get typeface => _typeface;
  double get lineSpacing => _lineSpacing;

  List<String> get globalExcludedKeywords => _globalExcludedKeywords;

  List<String> get searchHistory => _searchHistory;

  bool get adBlockEnabled => _adBlockEnabled;

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
        ? 30
        : savedInterval;
    _syncBackground = _box.get('syncBackground', defaultValue: true);

    final themeName = _box.get('selectedTheme');
    if (themeName != null) {
      try {
        _selectedTheme = AppTheme.values.firstWhere((e) => e.name == themeName);
      } catch (_) {
        _selectedTheme = AppTheme.system;
      }
    } else {
      final isDark = _box.get('isDarkMode', defaultValue: true);
      _selectedTheme = isDark ? AppTheme.dark : AppTheme.system;
    }

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
    _quietHoursStart = _box.get('quietHoursStart', defaultValue: 22);
    _quietHoursEnd = _box.get('quietHoursEnd', defaultValue: 7);

    // Display settings
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

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Setters — each persists to Hive then notifies listeners
  // ---------------------------------------------------------------------------

  /// Updates the active theme and persists the choice.
  Future<void> setTheme(AppTheme theme) async {
    _selectedTheme = theme;
    notifyListeners();
    await _box.put('selectedTheme', theme.name);
  }

  /// Sets the maximum number of articles cached for offline reading.
  Future<void> setOfflineCacheLimit(int limit) async {
    _offlineCacheLimit = limit;
    notifyListeners();
    await _box.put('offlineCacheLimit', limit);
  }

  /// Sets the background auto-refresh interval in seconds.
  Future<void> setCacheIntervalSeconds(int interval) async {
    _cacheIntervalSeconds = interval;
    notifyListeners();
    await _box.put('cacheIntervalSeconds', interval);
  }

  /// Enables or disables background auto-refresh.
  Future<void> setSyncBackground(bool value) async {
    _syncBackground = value;
    notifyListeners();
    await _box.put('syncBackground', value);
  }

  /// Updates the app locale and persists the language code.
  Future<void> setLocale(Locale newLocale) async {
    _locale = newLocale;
    notifyListeners();
    await _box.put('locale', newLocale.languageCode);
  }

  /// Enables or disables the global notification master toggle.
  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    notifyListeners();
    await _box.put('notificationsEnabled', value);
  }

  /// Sets the notification digest mode: `'instant'`, `'daily'`, or `'weekly'`.
  Future<void> setDigestMode(String mode) async {
    _digestMode = mode;
    notifyListeners();
    await _box.put('digestMode', mode);
  }

  /// Sets the hour (0-23) when the quiet period begins.
  Future<void> setQuietHoursStart(int hour) async {
    _quietHoursStart = hour;
    notifyListeners();
    await _box.put('quietHoursStart', hour);
  }

  /// Sets the hour (0-23) when the quiet period ends.
  Future<void> setQuietHoursEnd(int hour) async {
    _quietHoursEnd = hour;
    notifyListeners();
    await _box.put('quietHoursEnd', hour);
  }

  /// Sets the article body font size: `'small'`, `'medium'`, `'large'`, `'xl'`.
  Future<void> setFontSize(String size) async {
    _fontSize = size;
    notifyListeners();
    await _box.put('fontSize', size);
  }

  /// Sets the article typeface: `'system'`, `'serif'`, `'sans-serif'`, `'mono'`.
  Future<void> setTypeface(String face) async {
    _typeface = face;
    notifyListeners();
    await _box.put('typeface', face);
  }

  /// Sets the article line spacing multiplier (e.g. 1.2, 1.5, 1.8).
  Future<void> setLineSpacing(double spacing) async {
    _lineSpacing = spacing;
    notifyListeners();
    await _box.put('lineSpacing', spacing);
  }

  /// Replaces the global excluded keywords list.
  Future<void> setGlobalExcludedKeywords(List<String> keywords) async {
    _globalExcludedKeywords = keywords;
    notifyListeners();
    await _box.put('globalExcludedKeywords', keywords);
  }

  /// Enables or disables the built-in ad blocker for the in-app browser.
  Future<void> setAdBlockEnabled(bool value) async {
    _adBlockEnabled = value;
    notifyListeners();
    await _box.put('adBlockEnabled', value);
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
}
