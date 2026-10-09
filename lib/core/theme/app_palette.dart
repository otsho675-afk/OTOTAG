import 'package:flutter/material.dart';
import 'app_theme_state.dart';

/// Shared semantic colors for legacy pages that do not use ColorScheme yet.
/// Always consult the live setting so an open page reacts to theme changes.
abstract final class AppPalette {
  static bool get light => AppThemeState.light.value;
  static Color get page => light ? const Color(0xFFF6F9F6) : const Color(0xFF030508);
  static Color get surface => light ? Colors.white : const Color(0xFF111418);
  static Color get surfaceAlt => light ? const Color(0xFFF0F7F2) : const Color(0xFF191F1C);
  static Color get field => light ? Colors.white : const Color(0xFF191C21);
  static Color get border => light ? const Color(0xFFD5E3D8) : const Color(0xFF30363B);
  static Color get text => light ? const Color(0xFF14231A) : const Color(0xFFF5F8F6);
  static Color get muted => light ? const Color(0xFF52665A) : const Color(0xFFA5B4AA);
  static Color get subtle => light ? const Color(0xFF66776B) : const Color(0xFF7E8A84);
  static Color get accent => light ? const Color(0xFF08784D) : const Color(0xFF00FFA3);
  static Color get accentText => light ? Colors.white : const Color(0xFF071A12);
  static Color get accentSoft => light ? const Color(0xFFDDF3E5) : const Color(0xFF103827);
  static Color get danger => light ? const Color(0xFFB92F45) : const Color(0xFFFF586B);
  static Color get shadow => Colors.black.withValues(alpha: light ? .07 : .26);
}
