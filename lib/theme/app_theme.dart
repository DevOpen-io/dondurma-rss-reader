import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemeBuilder {
  static final _font = GoogleFonts.outfit().fontFamily;

  static ThemeData light(FlexScheme scheme) =>
      FlexColorScheme.light(scheme: scheme, fontFamily: _font).toTheme;

  static ThemeData dark(FlexScheme scheme) =>
      FlexColorScheme.dark(scheme: scheme, fontFamily: _font).toTheme;
}
