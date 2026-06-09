import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemeBuilder {
  static final String _font = GoogleFonts.outfit().fontFamily!;

  static TextTheme _textTheme(Color color) =>
      GoogleFonts.outfitTextTheme().apply(bodyColor: color, displayColor: color).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: color),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: color),
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: color),
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: color),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: color),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: color),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20, color: color),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: color),
        titleSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: color),
        bodyLarge: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 16, color: color),
        bodyMedium: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 14, color: color),
        bodySmall: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 12, color: color),
        labelLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: color),
        labelMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12, color: color),
        labelSmall: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 11, color: color),
      );

  static ThemeData _applyOverrides(ThemeData base) {
    return base.copyWith(
      textTheme: _textTheme(base.colorScheme.onSurface),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: base.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
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
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  static ThemeData light(FlexScheme scheme) =>
      _applyOverrides(FlexColorScheme.light(scheme: scheme, fontFamily: _font).toTheme);

  static ThemeData dark(FlexScheme scheme) =>
      _applyOverrides(FlexColorScheme.dark(scheme: scheme, fontFamily: _font).toTheme);
}
