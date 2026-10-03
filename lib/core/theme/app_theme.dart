import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

ThemeData appTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['sans-serif', 'Arial'],
      scaffoldBackgroundColor: AppConstants.bgColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppConstants.primaryColor,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppConstants.primaryColor,
        secondary: AppConstants.primaryColor,
        tertiary: AppConstants.primaryColor,
        error: AppConstants.dangerColor,
        surfaceTint: Colors.transparent,
        onPrimary: const Color(0xFF05251A),
        surface: AppConstants.cardColor,
        onSurface: Colors.white,
        outline: AppConstants.borderColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.fieldColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle:
            const TextStyle(color: AppConstants.mutedColor, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: AppConstants.primaryColor),
        hintStyle:
            const TextStyle(color: AppConstants.mutedColor, fontSize: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppConstants.borderColor)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppConstants.borderColor)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppConstants.borderColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppConstants.primaryColor)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: const Color(0xFF05251A),
            disabledBackgroundColor: const Color(0xFF202D28),
            disabledForegroundColor: const Color(0xFF9EAFA7),
            minimumSize: const Size(48, 46),
            textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
      ),
      textButtonTheme: TextButtonThemeData(
          style:
              TextButton.styleFrom(foregroundColor: AppConstants.primaryColor)),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppConstants.primaryColor),
      appBarTheme: const AppBarTheme(
          backgroundColor: AppConstants.bgColor,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent),
      bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppConstants.cardColor,
          modalBackgroundColor: AppConstants.cardColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
      dialogTheme: DialogThemeData(
          backgroundColor: AppConstants.cardColor,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: AppConstants.primaryColor,
              minimumSize: const Size(48, 46),
              side: const BorderSide(color: AppConstants.borderColor),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: const Color(0xFF05251A),
              elevation: 0,
              minimumSize: const Size(48, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: AppConstants.fieldColor,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      popupMenuTheme: const PopupMenuThemeData(
          color: AppConstants.cardColor, surfaceTintColor: Colors.transparent),
    );
