import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import 'app_motion.dart';
import 'theme_controller.dart';

ThemeData appTheme() =>
    AppThemeController.isLight ? lightAppTheme() : darkAppTheme();

ThemeData darkAppTheme() {
  return _buildTheme(
    brightness: Brightness.dark,
    background: AppConstants.bgColor,
    surface: AppConstants.cardColor,
    elevatedSurface: AppConstants.cardElevated,
    field: AppConstants.fieldColor,
    text: AppConstants.textColor,
    muted: AppConstants.mutedColor,
    subtle: AppConstants.subtleTextColor,
    border: AppConstants.borderColor,
    strongBorder: AppConstants.borderStrongColor,
  );
}

ThemeData lightAppTheme() {
  return _buildTheme(
    brightness: Brightness.light,
    background: const Color(0xFFF5F7F6),
    surface: Colors.white,
    elevatedSurface: const Color(0xFFFAFCFB),
    field: const Color(0xFFF0F4F2),
    text: const Color(0xFF111815),
    muted: const Color(0xFF65706B),
    subtle: const Color(0xFF7C8782),
    border: const Color(0xFFDCE4E0),
    strongBorder: const Color(0xFFC8D3CE),
  );
}

ThemeData _buildTheme({
  required Brightness brightness,
  required Color background,
  required Color surface,
  required Color elevatedSurface,
  required Color field,
  required Color text,
  required Color muted,
  required Color subtle,
  required Color border,
  required Color strongBorder,
}) {
  const primary = AppConstants.primaryColor;
  const onPrimary = AppConstants.primaryInk;
  const radius = 14.0;
  final isDark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
  ).copyWith(
    primary: primary,
    secondary: primary,
    tertiary: primary,
    error: AppConstants.dangerColor,
    surface: surface,
    surfaceContainerHighest: field,
    surfaceTint: Colors.transparent,
    onPrimary: onPrimary,
    onSecondary: onPrimary,
    onSurface: text,
    outline: border,
    outlineVariant: border,
  );

  TextStyle baseText = TextStyle(
    fontFamily: 'Roboto',
    color: text,
    height: 1.25,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['sans-serif', 'Arial'],
    scaffoldBackgroundColor: background,
    canvasColor: background,
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
      titleMedium:
          baseText.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      bodyLarge: baseText.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      bodyMedium: baseText.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: baseText.copyWith(
          fontSize: 12, color: muted, height: 1.35),
      labelLarge:
          baseText.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium:
          baseText.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: TextStyle(color: muted, fontSize: 13),
      floatingLabelStyle: const TextStyle(
          color: AppConstants.primaryColor, fontWeight: FontWeight.w700),
      hintStyle: TextStyle(color: subtle, fontSize: 13),
      prefixIconColor: muted,
      suffixIconColor: muted,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border)),
      disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: primary, width: 1.4)),
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
        disabledBackgroundColor:
            isDark ? const Color(0xFF202D28) : const Color(0xFFDCE5E1),
        disabledForegroundColor:
            isDark ? const Color(0xFF9EAFA7) : const Color(0xFF7C8983),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        elevation: 0,
        textStyle: const TextStyle(
            fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w700),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        animationDuration: AppMotion.interaction,
        foregroundColor: isDark ? primary : AppConstants.primaryDark,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius - 2)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        animationDuration: AppMotion.interaction,
        foregroundColor: text,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        side: BorderSide(color: strongBorder),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: text,
        hoverColor: primary.withValues(alpha: .08),
        highlightColor: primary.withValues(alpha: .10),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            ),
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      textColor: text,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: surface,
      indicatorColor: primary.withValues(alpha: isDark ? .14 : .20),
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 2,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : muted,
            size: 23,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected) ? text : muted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          )),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: isDark ? primary : AppConstants.primaryDark,
      unselectedItemColor: muted,
      elevation: isDark ? 0 : 8,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: field,
      selectedColor: primary.withValues(alpha: isDark ? .14 : .20),
      disabledColor: field,
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(color: text, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(
          color: isDark ? primary : AppConstants.primaryDark,
          fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: strongBorder,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: text,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: muted,
        fontSize: 14,
        height: 1.4,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? elevatedSurface : const Color(0xFF17201C),
      contentTextStyle:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: elevatedSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? elevatedSurface : const Color(0xFF17201C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      textStyle: const TextStyle(
          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
