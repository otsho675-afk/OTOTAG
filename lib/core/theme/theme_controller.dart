import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulamanın tema tercihini merkezi olarak yönetir ve cihazda saklar.
class AppThemeController {
  AppThemeController._();

  static const String _preferenceKey = 'app_theme_mode';

  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_preferenceKey);

    mode.value = saved == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  static bool get isLight => mode.value == ThemeMode.light;

  static Future<void> setMode(ThemeMode themeMode) async {
    if (themeMode != ThemeMode.light && themeMode != ThemeMode.dark) {
      themeMode = ThemeMode.dark;
    }

    mode.value = themeMode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _preferenceKey,
      themeMode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  static Future<void> setLightMode(bool enabled) {
    return setMode(enabled ? ThemeMode.light : ThemeMode.dark);
  }

  static Future<void> toggle() {
    return setLightMode(!isLight);
  }
}
