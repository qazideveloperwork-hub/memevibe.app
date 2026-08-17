import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography tokens transcribed 1:1 from
/// stitch_dynamic_animated_mobile_ui/vibeshift/DESIGN.md
abstract final class AppTypography {
  static TextStyle get displayLg => GoogleFonts.sora(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    height: 48 / 40,
    letterSpacing: -0.04 * 40,
    color: AppColors.onSurface,
  );

  static TextStyle get headlineLg => GoogleFonts.sora(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 32 / 24,
    letterSpacing: -0.02 * 24,
    color: AppColors.onSurface,
  );

  static TextStyle get headlineLgMobile => GoogleFonts.sora(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 28 / 20,
    color: AppColors.onSurface,
  );

  static TextStyle get bodyMd => GoogleFonts.hankenGrotesk(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppColors.onSurface,
  );

  static TextStyle get labelCaps => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 16 / 12,
    letterSpacing: 0.1 * 12,
    color: AppColors.onSurfaceVariant,
  );

  static TextStyle get buttonText => GoogleFonts.sora(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 20 / 16,
    color: AppColors.onPrimary,
  );

  const AppTypography._();
}
