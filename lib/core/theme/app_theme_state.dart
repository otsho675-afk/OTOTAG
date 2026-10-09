import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global appearance preference. Unrelated to account/session state.
class AppThemeState {
  AppThemeState._();

  static const preferenceKey = 'oto_tag_light_theme';
  static const previousAdminKey = 'oto_tag_admin_light_theme';
  static final ValueNotifier<bool> light = ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      light.value = prefs.getBool(preferenceKey) ??
          prefs.getBool(previousAdminKey) ?? false;
    } catch (_) {
      light.value = false;
    }
  }

  static Future<bool> setLight(bool value) async {
    light.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(preferenceKey, value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggle() => setLight(!light.value);
}
