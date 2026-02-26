import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

class SettingsProvider extends ChangeNotifier {
  AppTheme _selectedTheme = AppTheme.system;
  int _offlineCacheLimit = 50;
  int _cacheIntervalSeconds = 0;

  AppTheme get selectedTheme => _selectedTheme;
  int get offlineCacheLimit => _offlineCacheLimit;
  int get cacheIntervalSeconds => _cacheIntervalSeconds;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final box = Hive.box('settings');

    _offlineCacheLimit = box.get('offlineCacheLimit', defaultValue: 50);
    _cacheIntervalSeconds = box.get('cacheIntervalSeconds', defaultValue: 0);

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
}
