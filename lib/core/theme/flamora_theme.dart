import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'flamora_colors.dart';

abstract class FlamoraTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: FlamoraColors.flame,
      brightness: Brightness.light,
    ).copyWith(
      surface: FlamoraColors.creamBg,
      surfaceContainerHighest: FlamoraColors.creamCard,
      primary: FlamoraColors.flameDeep,
      secondary: FlamoraColors.leafDeep,
      tertiary: FlamoraColors.aquaDeep,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: FlamoraColors.creamBg,
      textTheme: GoogleFonts.outfitTextTheme(),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: FlamoraColors.creamBg,
        indicatorColor: FlamoraColors.flame.withValues(alpha: 0.18),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: FlamoraColors.flameDeep,
        thumbColor: FlamoraColors.flame,
        overlayColor: FlamoraColors.flame.withValues(alpha: 0.15),
      ),
      cardTheme: CardThemeData(
        color: FlamoraColors.creamCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: FlamoraColors.flame,
      brightness: Brightness.dark,
    ).copyWith(
      surface: FlamoraColors.maroonDeep,
      surfaceContainerHighest: FlamoraColors.maroon,
      primary: FlamoraColors.flameSoft,
      secondary: FlamoraColors.leaf,
      tertiary: FlamoraColors.aqua,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: FlamoraColors.maroonDeep,
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: FlamoraColors.maroonDeep,
        indicatorColor: FlamoraColors.flame.withValues(alpha: 0.28),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: FlamoraColors.flameSoft,
        thumbColor: FlamoraColors.aqua,
        overlayColor: FlamoraColors.aqua.withValues(alpha: 0.18),
      ),
      cardTheme: CardThemeData(
        color: FlamoraColors.maroon,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}
