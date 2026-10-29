import 'dart:math' as math;

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

  /// Every color comes from tonal palettes of the scheme's own colors, so
  /// text on a colored control is a deep or light tone of that color (never
  /// plain black on amber) and surfaces carry its hue. The chroma tones keep
  /// the brand color as vivid as the scheme defines it.
  // Secondary and tertiary come from the primary hue: some schemes pair
  // their color with an unrelated one (amber with blue), which put a blue
  // tonal button on an amber screen.
  static const _keyColors = FlexKeyColors(useKeyColors: true);

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
    chipSelectedSchemeColor: SchemeColor.primaryContainer,
    // The add button must stand out from the page in every scheme.
    fabSchemeColor: SchemeColor.primary,
    drawerIndicatorSchemeColor: SchemeColor.primary,
    drawerIndicatorOpacity: 0.14,
    popupMenuSchemeColor: SchemeColor.surfaceContainerHigh,
    tooltipRadius: 8,
  );

  static ThemeData light(FlexScheme scheme, AppFont font) =>
      _build(scheme, font, Brightness.light);

  static ThemeData dark(FlexScheme scheme, AppFont font) =>
      _build(scheme, font, Brightness.dark);

  static ThemeData _build(FlexScheme scheme, AppFont font, Brightness b) {
    FlexColorScheme flex({Color? onPrimary}) => b == Brightness.light
        ? FlexColorScheme.light(
            scheme: scheme,
            keyColors: _keyColors,
            tones: FlexTones.chroma(Brightness.light),
            surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
            blendLevel: _lightBlend,
            subThemesData: _subThemes,
            onPrimary: onPrimary,
            fontFamily: font.family,
          )
        : FlexColorScheme.dark(
            scheme: scheme,
            keyColors: _keyColors,
            tones: FlexTones.chroma(Brightness.dark),
            surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
            blendLevel: _darkBlend,
            subThemesData: _subThemes,
            onPrimary: onPrimary,
            fontFamily: font.family,
          );
    var theme = flex();
    // Labels on the theme color (the add button, the reading-mode thumb)
    // must read; a few schemes pair a mid-tone primary with white.
    final primary = theme.toScheme.primary;
    if (_contrast(theme.toScheme.onPrimary, primary) < 4.5) {
      theme = flex(
        onPrimary:
            _contrast(Colors.black, primary) >= _contrast(Colors.white, primary)
            ? Colors.black
            : Colors.white,
      );
    }
    return _applyOverrides(theme.toTheme, font.family);
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [accent] where it reads well on [background], else moved toward
  /// [fallback] until it does: some schemes' brand color is too light for
  /// small text (sakura, amber) or icons (outer space in dark mode).
  static Color readableAccent(
    Color accent, {
    required Color background,
    required Color fallback,
    double minContrast = 4.5,
  }) {
    for (var t = 0.0; t < 1; t += 0.1) {
      final color = Color.lerp(accent, fallback, t)!;
      if (_contrast(color, background) >= minContrast) return color;
    }
    return fallback;
  }
}
