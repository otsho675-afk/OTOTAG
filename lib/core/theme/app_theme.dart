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
    snackBarTheme: const SnackBarThemeData(
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
  const ink = Color(0xFF15231B);
  const primary = Color(0xFF08784D);
  const outline = Color(0xFFD8E5DA);
  final scheme = ColorScheme.fromSeed(
    seedColor: primary, brightness: Brightness.light,
  ).copyWith(
    primary: primary, onPrimary: Colors.white,
    secondary: primary, onSecondary: Colors.white,
    surface: Colors.white, onSurface: ink,
    surfaceContainerHighest: const Color(0xFFECF4ED),
    outline: outline, outlineVariant: outline,
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F9F6),
    canvasColor: const Color(0xFFF6F9F6),
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: 'Roboto', bodyColor: ink, displayColor: ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: outline))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      labelStyle: const TextStyle(color: Color(0xFF52675A)),
      hintStyle: const TextStyle(color: Color(0xFF657669)),
      prefixIconColor: primary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: outline)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: outline)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary, foregroundColor: Colors.white,
        minimumSize: const Size(48, 48))),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary, foregroundColor: Colors.white,
        minimumSize: const Size(48, 48))),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: outline))),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(
      foregroundColor: ink)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFD9F2E2),
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: ink, fontSize: 11)),
      iconTheme: WidgetStateProperty.all(
          const IconThemeData(color: primary))),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: ink, fontSize: 19, fontWeight: FontWeight.w800),
      contentTextStyle: const TextStyle(color: ink, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white, modalBackgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent),
    chipTheme: const ChipThemeData(
      backgroundColor: Color(0xFFF0F6F1),
      selectedColor: Color(0xFFD9F2E2),
      side: BorderSide(color: outline),
      labelStyle: TextStyle(color: ink)),
    dividerTheme: const DividerThemeData(color: outline),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating),
  );
}
