import 'package:flutter/material.dart';

class AppColors {
  // Default/Fallback Values
  static const Color defaultPrimaryRed = Color(0xFFE53935);
  static const Color defaultSecondaryPurple = Color(0xFF8E24AA);

  // Dynamic values (updated by ThemeProvider)
  static Color primary = defaultPrimaryRed;
  static Color secondary = defaultSecondaryPurple;
  static bool isGradient = true;
  static double gradientAngle = 135.0;
  static double glowIntensity = 0.5;

  static void updateDynamicColors({
    required Color primary,
    required Color secondary,
    required bool isGradient,
    required double angle,
    required double glow,
  }) {
    AppColors.primary = primary;
    AppColors.secondary = secondary;
    AppColors.isGradient = isGradient;
    AppColors.gradientAngle = angle;
    AppColors.glowIntensity = glow;
  }

  // Common UI Colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Colors.white;
  static const Color error = Color(0xFFE53935);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF757575);

  // Compatibility Getters
  static Color get primaryRed => primary;
  static Color get secondaryPurple => secondary;
  static LinearGradient get primaryGradient => dynamicPrimaryGradient;
  static LinearGradient get surfaceGradient => dynamicPrimaryGradient; // Alias for now

  // Helper for dynamic gradients based on the current theme
  static LinearGradient get dynamicPrimaryGradient {
    return LinearGradient(
      colors: isGradient ? [primary, secondary] : [primary, primary],
      begin: _getAlignment(gradientAngle),
      end: _getAlignment(gradientAngle + 180),
    );
  }

  static Alignment _getAlignment(double angle) {
    angle = angle % 360;
    if (angle >= 0 && angle < 45) return Alignment.topCenter;
    if (angle >= 45 && angle < 90) return Alignment.topRight;
    if (angle >= 90 && angle < 135) return Alignment.centerRight;
    if (angle >= 135 && angle < 180) return Alignment.bottomRight;
    if (angle >= 180 && angle < 225) return Alignment.bottomCenter;
    if (angle >= 225 && angle < 270) return Alignment.bottomLeft;
    if (angle >= 270 && angle < 315) return Alignment.centerLeft;
    return Alignment.topLeft;
  }
}
