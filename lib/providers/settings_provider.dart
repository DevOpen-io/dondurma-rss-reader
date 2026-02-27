import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

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

  AppTheme get selectedTheme => _selectedTheme;
  int get offlineCacheLimit => _offlineCacheLimit;
  int get cacheIntervalSeconds => _cacheIntervalSeconds;
  bool get syncBackground => _syncBackground;
  Locale get locale => _locale;

  bool get notificationsEnabled => _notificationsEnabled;
  String get digestMode => _digestMode;
  int get quietHoursStart => _quietHoursStart;
  int get quietHoursEnd => _quietHoursEnd;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final box = Hive.box('settings');

    _offlineCacheLimit = box.get('offlineCacheLimit', defaultValue: 50);
    final savedInterval = box.get('cacheIntervalSeconds');
    _cacheIntervalSeconds = (savedInterval == null || savedInterval == 0)
        ? 30
        : savedInterval;
    _syncBackground = box.get('syncBackground', defaultValue: true);

    final themeName = box.get('selectedTheme');
    if (themeName != null) {
      try {
        _selectedTheme = AppTheme.values.firstWhere((e) => e.name == themeName);
      } catch (_) {
        _selectedTheme = AppTheme.system;
      }
    } else {
      final isDark = box.get('isDarkMode', defaultValue: true);
      _selectedTheme = isDark ? AppTheme.dark : AppTheme.system;
    }

    // Load locale
    final savedLocale = box.get('locale');
    if (savedLocale != null) {
      try {
        _locale = Locale(savedLocale);
      } catch (_) {
        _locale = const Locale('en');
      }
    }

    // Load notification settings
    _notificationsEnabled = box.get('notificationsEnabled', defaultValue: true);
    _digestMode = box.get('digestMode', defaultValue: 'instant');
    _quietHoursStart = box.get('quietHoursStart', defaultValue: 22);
    _quietHoursEnd = box.get('quietHoursEnd', defaultValue: 7);

    notifyListeners();
  }

  void setTheme(AppTheme theme) async {
    _selectedTheme = theme;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('selectedTheme', theme.name);
  }

  Future<void> setOfflineCacheLimit(int limit) async {
    _offlineCacheLimit = limit;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('offlineCacheLimit', limit);
  }

  Future<void> setCacheIntervalSeconds(int interval) async {
    _cacheIntervalSeconds = interval;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('cacheIntervalSeconds', interval);
  }

  Future<void> setSyncBackground(bool value) async {
    _syncBackground = value;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('syncBackground', value);
  }

  Future<void> setLocale(Locale newLocale) async {
    _locale = newLocale;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('locale', newLocale.languageCode);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('notificationsEnabled', value);
  }

  Future<void> setDigestMode(String mode) async {
    _digestMode = mode;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('digestMode', mode);
  }

  Future<void> setQuietHoursStart(int hour) async {
    _quietHoursStart = hour;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('quietHoursStart', hour);
  }

  Future<void> setQuietHoursEnd(int hour) async {
    _quietHoursEnd = hour;
    notifyListeners();
    final box = Hive.box('settings');
    await box.put('quietHoursEnd', hour);
  }
}
