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
        // Seamless with the page: the bar is part of it, not a band above.
        backgroundColor: base.scaffoldBackgroundColor,
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
      // The selection follows the brand color, not the scheme's secondary.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: base.colorScheme.surfaceContainer,
        indicatorColor: base.colorScheme.primary.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? base.colorScheme.primary
                : base.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  /// Surfaces take a light wash of the theme color: cards and sheets more
  /// than the page behind them, and more in dark mode, where a neutral grey
  /// would read as no theme at all. Text keeps its neutral colors.
  static const _lightBlend = 12;
  static const _darkBlend = 22;

  /// Controls follow the theme color rather than the scheme's secondary, so
  /// a chosen color shows wherever something is selected or switched on.
  static const _subThemes = FlexSubThemesData(
    interactionEffects: true,
    tintedDisabledControls: true,
    useM2StyleDividerInM3: false,
    segmentedButtonSchemeColor: SchemeColor.primary,
    switchSchemeColor: SchemeColor.primary,
    checkboxSchemeColor: SchemeColor.primary,
    radioSchemeColor: SchemeColor.primary,
    sliderBaseSchemeColor: SchemeColor.primary,
    chipSchemeColor: SchemeColor.primary,
    chipSelectedSchemeColor: SchemeColor.primaryContainer,
    fabSchemeColor: SchemeColor.primaryContainer,
    drawerIndicatorSchemeColor: SchemeColor.primary,
    drawerIndicatorOpacity: 0.14,
    popupMenuSchemeColor: SchemeColor.surfaceContainerHigh,
    tooltipRadius: 8,
  );

  static ThemeData light(FlexScheme scheme, AppFont font) => _applyOverrides(
    FlexColorScheme.light(
      scheme: scheme,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: _lightBlend,
      subThemesData: _subThemes,
      fontFamily: font.family,
    ).toTheme,
    font.family,
  );

  static ThemeData dark(FlexScheme scheme, AppFont font) => _applyOverrides(
    FlexColorScheme.dark(
      scheme: scheme,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: _darkBlend,
      subThemesData: _subThemes,
      fontFamily: font.family,
    ).toTheme,
    font.family,
  );
}
