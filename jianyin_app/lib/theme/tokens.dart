import 'package:flutter/material.dart';

/// Design tokens aligned with docs/design/客户端APP/ui/css/tokens.css
abstract final class AppTokens {
  // Surfaces
  static const ink = Color(0xFF0B1220);
  static const inkElevated = Color(0xFF141C2E);
  static const paper = Color(0xFFF4F7FB);
  static const paperElevated = Color(0xFFFFFFFF);
  static const muted = Color(0xFFE8EEF6);
  static const border = Color(0xFFD5DEE9);

  // Text
  static const fg = Color(0xFF0F172A);
  static const fgMuted = Color(0xFF475569);
  static const fgOnInk = Color(0xFFF1F5F9);
  static const fgOnInkMuted = Color(0xFF94A3B8);

  // Brand
  static const gold = Color(0xFFD4A017);
  static const goldSoft = Color(0x38D4A017);
  static const teal = Color(0xFF0F766E);
  static const tealSoft = Color(0xFFCCFBF1);
  static const danger = Color(0xFFDC2626);
  static const ring = Color(0xFF0F766E);

  // Camera chrome
  static const topbarBg = Color(0x8C0B1220);
  static const captionGlass = Color(0x6115172A);
  static const hintBg = Color(0xE00F766E);
  static const hintWarn = Color(0xE0D4A017);
  static const hintDanger = Color(0xE0DC2626);
  static const hintMuted = Color(0xE0475569);

  // Runtime status
  static const statusOffline = Color(0xFF94A3B8);
  static const statusIdle = Color(0xFF2DD4BF);
  static const statusRecognizing = Color(0xFFD4A017);
  static const statusTranslating = Color(0xFF38BDF8);

  // Viewpoint frame
  static const vpGreen = Color(0xEB2DD4BF);
  static const vpYellow = Color(0xF2D4A017);
  static const vpRed = Color(0xF2F87171);

  // Type sizes
  static const textXs = 12.0;
  static const textSm = 14.0;
  static const textBase = 16.0;
  static const textLg = 18.0;
  static const textXl = 20.0;
  static const text2xl = 24.0;
  static const text3xl = 30.0;

  // Space (8dp rhythm)
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const space7 = 48.0;

  // Radii
  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;
  static const radiusXl = 28.0;
  static const radiusField = 14.0;
  static const radiusBtn = 14.0;

  static const touchMin = 44.0;
  static const iconMd = 22.0;

  static const durationFast = Duration(milliseconds: 150);
  static const durationOut = Duration(milliseconds: 200);
}
