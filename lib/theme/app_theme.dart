import 'package:flutter/material.dart';
import 'package:catppuccin_flutter/catppuccin_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

/// Available theme options for the application.
///
/// [system] follows the platform brightness. The four Catppuccin flavors
/// provide pastel-toned palettes with varying darkness levels.
enum AppTheme {
  system,
  light,
  dark,
  catppuccinLatte,
  catppuccinFrappe,
  catppuccinMacchiato,
  catppuccinMocha,
}

/// Builds [ThemeData] instances for each [AppTheme] variant.
class AppThemeBuilder {
  /// Returns the [ThemeData] for the given [theme] and platform [systemBrightness].
  static ThemeData getTheme(AppTheme theme, Brightness systemBrightness) {
    switch (theme) {
      case AppTheme.system:
        return systemBrightness == Brightness.dark
            ? _buildDarkTheme()
            : _buildLightTheme();
      case AppTheme.light:
        return _buildLightTheme();
      case AppTheme.dark:
        return _buildDarkTheme();
      case AppTheme.catppuccinLatte:
        return _buildCatppuccinTheme(catppuccin.latte);
      case AppTheme.catppuccinFrappe:
        return _buildCatppuccinTheme(catppuccin.frappe);
      case AppTheme.catppuccinMacchiato:
        return _buildCatppuccinTheme(catppuccin.macchiato);
      case AppTheme.catppuccinMocha:
        return _buildCatppuccinTheme(catppuccin.mocha);
    }
  }

  static ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF12A8FF),
        surface: Colors.white,
        secondary: Color(0xFF12A8FF),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF12A8FF),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF12A8FF).withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFF12A8FF));
          }
          return const IconThemeData(color: Colors.grey);
        }),
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.outfitTextTheme(),
    );
  }

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF131c26),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF12A8FF),
        surface: Color(0xFF1a2632),
        secondary: Color(0xFF12A8FF),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF131c26),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF1a2632),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF131c26),
        indicatorColor: const Color(0xFF12A8FF).withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFF12A8FF));
          }
          return const IconThemeData(color: Colors.white54);
        }),
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ),
      useMaterial3: true,
    );
  }

  static ThemeData _buildCatppuccinTheme(Flavor flavor) {
    final isLight = flavor == catppuccin.latte;

    return ThemeData(
      brightness: isLight ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: flavor.crust,
      colorScheme: isLight
          ? ColorScheme.light(
              primary: flavor.sapphire,
              surface: flavor.base,
              secondary: flavor.lavender,
              onSurface: flavor.text,
            )
          : ColorScheme.dark(
              primary: flavor.sapphire,
              surface: flavor.base,
              secondary: flavor.lavender,
              onSurface: flavor.text,
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: flavor.crust,
        foregroundColor: flavor.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: flavor.mantle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isLight
                ? flavor.surface1.withValues(alpha: 0.2)
                : flavor.surface1.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: flavor.crust,
        indicatorColor: flavor.surface1,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: flavor.sapphire,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: flavor.subtext0,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: flavor.sapphire);
          }
          return IconThemeData(color: flavor.subtext0);
        }),
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData(
          brightness: isLight ? Brightness.light : Brightness.dark,
        ).textTheme,
      ).apply(bodyColor: flavor.text, displayColor: flavor.text),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: flavor.sapphire,
        foregroundColor: flavor.base,
      ),
      useMaterial3: true,
    );
  }
}
