import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'app_fonts.dart';

class AppThemeBuilder {
  static TextTheme _textTheme(String? font, Color color) => ThemeData.light()
      .textTheme
      .apply(fontFamily: font, bodyColor: color, displayColor: color)
      .copyWith(
        displayLarge: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w800,
          color: color,
        ),
        displayMedium: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w800,
          color: color,
        ),
        displaySmall: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        headlineLarge: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        headlineMedium: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        headlineSmall: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        titleLarge: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: color,
        ),
        titleMedium: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: color,
        ),
        titleSmall: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: color,
        ),
        bodyLarge: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w400,
          fontSize: 16,
          color: color,
        ),
        bodyMedium: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: color,
        ),
        bodySmall: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w400,
          fontSize: 12,
          color: color,
        ),
        labelLarge: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: color,
        ),
        labelMedium: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: color,
        ),
        labelSmall: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w500,
          fontSize: 11,
          color: color,
        ),
      );

  static ThemeData _applyOverrides(ThemeData base, String? font) {
    return base.copyWith(
      textTheme: _textTheme(font, base.colorScheme.onSurface),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: base.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: base.colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  static ThemeData light(FlexScheme scheme, AppFont font) => _applyOverrides(
    FlexColorScheme.light(scheme: scheme, fontFamily: font.family).toTheme,
    font.family,
  );

  static ThemeData dark(FlexScheme scheme, AppFont font) => _applyOverrides(
    FlexColorScheme.dark(scheme: scheme, fontFamily: font.family).toTheme,
    font.family,
  );
}
