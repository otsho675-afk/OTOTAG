import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import 'app_motion.dart';

ThemeData appTheme() {
  const primary = AppConstants.primaryColor;
  const onPrimary = AppConstants.primaryInk;
  const radius = 14.0;

  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: primary,
    secondary: primary,
    tertiary: primary,
    error: AppConstants.dangerColor,
    surface: AppConstants.cardColor,
    surfaceContainerHighest: AppConstants.fieldColor,
    surfaceTint: Colors.transparent,
    onPrimary: onPrimary,
    onSecondary: onPrimary,
    onSurface: AppConstants.textColor,
    outline: AppConstants.borderColor,
    outlineVariant: AppConstants.borderColor,
  );

  const baseText = TextStyle(
    fontFamily: 'Roboto',
    color: AppConstants.textColor,
    height: 1.25,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['sans-serif', 'Arial'],
    scaffoldBackgroundColor: AppConstants.bgColor,
    canvasColor: AppConstants.bgColor,
    colorScheme: scheme,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: AppPageTransitionsBuilder(),
      TargetPlatform.iOS: AppPageTransitionsBuilder(native: true),
      TargetPlatform.macOS: AppPageTransitionsBuilder(native: true),
      TargetPlatform.windows: AppPageTransitionsBuilder(),
      TargetPlatform.linux: AppPageTransitionsBuilder(),
      TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
    }),
    textTheme: TextTheme(
      displayLarge: baseText.copyWith(
          fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2),
      displayMedium: baseText.copyWith(
          fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1.0),
      headlineLarge: baseText.copyWith(
          fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.7),
      headlineMedium: baseText.copyWith(
          fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: baseText.copyWith(
          fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: baseText.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      bodyLarge: baseText.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      bodyMedium: baseText.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: baseText.copyWith(
          fontSize: 12, color: AppConstants.mutedColor, height: 1.35),
      labelLarge: baseText.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: baseText.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppConstants.fieldColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle:
          const TextStyle(color: AppConstants.mutedColor, fontSize: 13),
      floatingLabelStyle: const TextStyle(
          color: AppConstants.primaryColor, fontWeight: FontWeight.w700),
      hintStyle:
          const TextStyle(color: AppConstants.subtleTextColor, fontSize: 13),
      prefixIconColor: AppConstants.mutedColor,
      suffixIconColor: AppConstants.mutedColor,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppConstants.borderColor)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppConstants.borderColor)),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppConstants.borderColor)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide:
              const BorderSide(color: AppConstants.primaryColor, width: 1.4)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppConstants.dangerColor)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide:
              const BorderSide(color: AppConstants.dangerColor, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        animationDuration: AppMotion.interaction,
        backgroundColor: primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: const Color(0xFF202D28),
        disabledForegroundColor: const Color(0xFF9EAFA7),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        elevation: 0,
        textStyle: const TextStyle(
            fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        animationDuration: AppMotion.interaction,
        foregroundColor: primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius - 2)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        animationDuration: AppMotion.interaction,
        foregroundColor: AppConstants.textColor,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        side: const BorderSide(color: AppConstants.borderStrongColor),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        animationDuration: AppMotion.interaction,
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppConstants.textColor,
        hoverColor: primary.withValues(alpha: .08),
        highlightColor: primary.withValues(alpha: .10),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppConstants.bgColor,
      foregroundColor: AppConstants.textColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: AppConstants.textColor,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppConstants.borderColor,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppConstants.mutedColor,
      textColor: AppConstants.textColor,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: AppConstants.cardColor,
      indicatorColor: primary.withValues(alpha: .14),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : AppConstants.mutedColor,
            size: 23,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppConstants.textColor
                : AppConstants.mutedColor,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          )),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppConstants.cardColor,
      selectedItemColor: primary,
      unselectedItemColor: AppConstants.mutedColor,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelStyle:
          TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppConstants.fieldColor,
      selectedColor: primary.withValues(alpha: .14),
      disabledColor: AppConstants.fieldColor,
      side: const BorderSide(color: AppConstants.borderColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(
          color: AppConstants.textColor, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(
          color: AppConstants.primaryColor, fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppConstants.cardColor,
      modalBackgroundColor: AppConstants.cardColor,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppConstants.borderStrongColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppConstants.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Roboto',
        color: AppConstants.textColor,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Roboto',
        color: AppConstants.mutedColor,
        fontSize: 14,
        height: 1.4,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppConstants.cardElevated,
      contentTextStyle: const TextStyle(
          color: AppConstants.textColor, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppConstants.cardElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppConstants.cardElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppConstants.borderColor),
      ),
      textStyle: const TextStyle(
          color: AppConstants.textColor, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}


ThemeData appLightTheme() {
  // Daylight design system: quiet green accents, crisp surfaces and readable
  // typography. Dark mode continues to use the independent appTheme().
  const ink = Color(0xFF17271F);
  const muted = Color(0xFF56675D);
  const primary = Color(0xFF216747);
  const canvas = Color(0xFFF5F7F6);
  const surface = Colors.white;
  const surfaceSoft = Color(0xFFF0F4F1);
  const outline = Color(0xFFDCE5DE);
  const outlineStrong = Color(0xFFC8D7CD);
  const selected = Color(0xFFE1EEE5);
  const danger = Color(0xFFBA3048);
  const radius = 16.0;

  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: selected,
    onPrimaryContainer: const Color(0xFF164B34),
    secondary: const Color(0xFF466B56),
    onSecondary: Colors.white,
    secondaryContainer: surfaceSoft,
    onSecondaryContainer: ink,
    tertiary: const Color(0xFF557263),
    onTertiary: Colors.white,
    error: danger,
    onError: Colors.white,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceContainerLowest: surface,
    surfaceContainerLow: const Color(0xFFFAFBFA),
    surfaceContainer: surfaceSoft,
    surfaceContainerHigh: const Color(0xFFEAF0EC),
    surfaceContainerHighest: const Color(0xFFE4ECE6),
    outline: outlineStrong,
    outlineVariant: outline,
    inverseSurface: ink,
    onInverseSurface: Colors.white,
    shadow: const Color(0xFF203329),
    scrim: const Color(0xFF17271F),
    surfaceTint: Colors.transparent,
  );
  const base = TextStyle(fontFamily: 'Roboto', color: ink, height: 1.30);
  final corners = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['sans-serif', 'Arial'],
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    cardColor: surface,
    dividerColor: outline,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: AppPageTransitionsBuilder(),
      TargetPlatform.iOS: AppPageTransitionsBuilder(native: true),
      TargetPlatform.macOS: AppPageTransitionsBuilder(native: true),
      TargetPlatform.windows: AppPageTransitionsBuilder(),
      TargetPlatform.linux: AppPageTransitionsBuilder(),
      TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
    }),
    textTheme: TextTheme(
      displayLarge: base.copyWith(fontSize: 39, fontWeight: FontWeight.w800, letterSpacing: -1.1),
      displayMedium: base.copyWith(fontSize: 33, fontWeight: FontWeight.w800, letterSpacing: -.9),
      headlineLarge: base.copyWith(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.7),
      headlineMedium: base.copyWith(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5),
      titleLarge: base.copyWith(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.35),
      titleMedium: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      titleSmall: base.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      bodyLarge: base.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      bodyMedium: base.copyWith(fontSize: 14),
      bodySmall: base.copyWith(fontSize: 12, color: muted),
      labelLarge: base.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: base.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
      labelSmall: base.copyWith(fontSize: 11, color: muted, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: ink),
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto', color: ink, fontSize: 18,
        fontWeight: FontWeight.w800, letterSpacing: -.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: muted, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(color: primary, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: Color(0xFF708077), fontSize: 13),
      prefixIconColor: muted,
      suffixIconColor: muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: outlineStrong),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: primary, width: 1.7),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: danger, width: 1.7),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE3E9E5),
        disabledForegroundColor: const Color(0xFF7F9185),
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        elevation: 0,
        animationDuration: AppMotion.interaction,
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        shape: corners,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE3E9E5),
        disabledForegroundColor: const Color(0xFF7F9185),
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        elevation: 0,
        animationDuration: AppMotion.interaction,
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        shape: corners,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        side: const BorderSide(color: outlineStrong),
        animationDuration: AppMotion.interaction,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: corners,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        animationDuration: AppMotion.interaction,
        shape: corners,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: ink,
        hoverColor: primary.withValues(alpha: .055),
        highlightColor: primary.withValues(alpha: .09),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: selected,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        size: 23, color: states.contains(WidgetState.selected) ? primary : muted,
      )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 11,
        color: states.contains(WidgetState.selected) ? primary : muted,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
      )),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: primary,
      unselectedItemColor: muted,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor: muted,
      indicatorColor: primary,
      dividerColor: outline,
      labelStyle: TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceSoft,
      selectedColor: selected,
      disabledColor: surfaceSoft,
      side: const BorderSide(color: outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w700),
      secondaryLabelStyle: const TextStyle(color: primary, fontWeight: FontWeight.w800),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? primary : const Color(0xFFCFDDD3)),
      thumbColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? Colors.white : const Color(0xFF687D70)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? primary : Colors.white),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: outlineStrong, width: 1.5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary, linearTrackColor: surfaceSoft, circularTrackColor: surfaceSoft,
    ),
    dividerTheme: const DividerThemeData(color: outline, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: muted,
      textColor: ink,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: outlineStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Roboto', color: ink, fontSize: 20, fontWeight: FontWeight.w800,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Roboto', color: muted, fontSize: 14, height: 1.5,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 7,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );
}
