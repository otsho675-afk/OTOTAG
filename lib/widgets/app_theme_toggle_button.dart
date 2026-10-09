import 'package:flutter/material.dart';
import '../core/theme/app_theme_state.dart';
import '../core/theme/app_palette.dart';

/// Compact appearance action reused by login, registration, user and business areas.
class AppThemeToggleButton extends StatelessWidget {
  const AppThemeToggleButton({super.key, this.compact = true});
  final bool compact;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AppThemeState.light,
        builder: (context, isLight, _) => IconButton(
          tooltip: isLight ? 'Karanlık temaya geç' : 'Aydınlık temaya geç',
          onPressed: () => AppThemeState.toggle(),
          icon: Icon(
            isLight ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            color: isLight ? AppPalette.accent : const Color(0xFF00E58F),
            size: compact ? 23 : 26,
          ),
        ),
      );
}
