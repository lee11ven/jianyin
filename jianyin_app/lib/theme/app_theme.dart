import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final heading = GoogleFonts.figtreeTextTheme();
    final body = GoogleFonts.notoSansScTextTheme();

    final textTheme = body.copyWith(
      displayLarge: heading.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02 * 30,
        color: AppTokens.fg,
      ),
      headlineMedium: heading.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01 * 18,
        fontSize: AppTokens.textLg,
        color: AppTokens.fg,
      ),
      titleLarge: heading.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: AppTokens.textXl,
        letterSpacing: -0.02 * 20,
        color: AppTokens.fg,
      ),
      titleMedium: heading.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: AppTokens.textBase,
        color: AppTokens.fg,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        fontSize: AppTokens.textBase,
        height: 1.5,
        color: AppTokens.fg,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontSize: AppTokens.textSm,
        height: 1.5,
        color: AppTokens.fgMuted,
      ),
      labelLarge: heading.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: AppTokens.textBase,
      ),
    );

    final scheme = ColorScheme.light(
      primary: AppTokens.teal,
      onPrimary: Colors.white,
      secondary: AppTokens.gold,
      onSecondary: AppTokens.fg,
      surface: AppTokens.paperElevated,
      onSurface: AppTokens.fg,
      error: AppTokens.danger,
      onError: Colors.white,
      outline: AppTokens.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppTokens.paper,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppTokens.paperElevated,
        foregroundColor: AppTokens.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium,
        shape: const Border(
          bottom: BorderSide(color: AppTokens.border),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppTokens.teal,
        inactiveTrackColor: AppTokens.muted,
        thumbColor: AppTokens.teal,
        overlayColor: AppTokens.teal.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTokens.paperElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space4,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusField),
          borderSide: const BorderSide(color: AppTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusField),
          borderSide: const BorderSide(color: AppTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusField),
          borderSide: const BorderSide(color: AppTokens.teal, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppTokens.inkElevated,
        contentTextStyle: textTheme.bodyLarge?.copyWith(
          color: AppTokens.fgOnInk,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    );
  }
}
