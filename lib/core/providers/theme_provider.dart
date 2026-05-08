import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../theme/app_colors.dart';

class ThemeProvider extends ChangeNotifier {
  final _supabaseService = SupabaseService();
  final SharedPreferences _prefs;
  StreamSubscription? _themeSubscription;
  
  // Theme Data
  Color _primaryColor = AppColors.defaultPrimaryRed;
  Color _secondaryColor = AppColors.defaultSecondaryPurple;
  bool _isGradient = true;
  double _gradientAngle = 135.0;
  double _glowIntensity = 0.5;

  Color get primaryColor => _primaryColor;
  Color get secondaryColor => _secondaryColor;
  bool get isGradient => _isGradient;
  double get gradientAngle => _gradientAngle;
  double get glowIntensity => _glowIntensity;

  ThemeProvider(this._prefs) {
    _loadCachedTheme();
    _listenToThemeChanges();
  }

  void _loadCachedTheme() {
    final primaryHex = _prefs.getString('theme_primary_color');
    final secondaryHex = _prefs.getString('theme_secondary_color');
    final isGradient = _prefs.getBool('theme_is_gradient');
    final angle = _prefs.getDouble('theme_gradient_angle');
    final glow = _prefs.getDouble('theme_glow_intensity');

    if (primaryHex != null && secondaryHex != null) {
      _primaryColor = _colorFromHex(primaryHex);
      _secondaryColor = _colorFromHex(secondaryHex);
      _isGradient = isGradient ?? true;
      _gradientAngle = angle ?? 135.0;
      _glowIntensity = glow ?? 0.5;

      AppColors.updateDynamicColors(
        primary: _primaryColor,
        secondary: _secondaryColor,
        isGradient: _isGradient,
        angle: _gradientAngle,
        glow: _glowIntensity,
      );
    }
  }

  void _listenToThemeChanges() {
    _themeSubscription = _supabaseService.getActiveThemeStream().listen((theme) {
      if (theme != null) {
        _updateTheme(theme);
      } else {
        _resetToDefault();
      }
    });
  }

  void _updateTheme(Map<String, dynamic> theme) {
    final primaryHex = theme['primary_color'] ?? '#E53935';
    final secondaryHex = theme['secondary_color'] ?? '#8E24AA';
    
    _primaryColor = _colorFromHex(primaryHex);
    _secondaryColor = _colorFromHex(secondaryHex);
    _isGradient = theme['is_gradient'] ?? true;
    _gradientAngle = (theme['gradient_angle'] ?? 135.0).toDouble();
    _glowIntensity = (theme['glow_intensity'] ?? 0.5).toDouble();
    
    // Save to Cache
    _prefs.setString('theme_primary_color', primaryHex);
    _prefs.setString('theme_secondary_color', secondaryHex);
    _prefs.setBool('theme_is_gradient', _isGradient);
    _prefs.setDouble('theme_gradient_angle', _gradientAngle);
    _prefs.setDouble('theme_glow_intensity', _glowIntensity);

    // Update the static reference in AppColors
    AppColors.updateDynamicColors(
      primary: _primaryColor,
      secondary: _secondaryColor,
      isGradient: _isGradient,
      angle: _gradientAngle,
      glow: _glowIntensity,
    );
    
    notifyListeners();
  }

  void _resetToDefault() {
    _primaryColor = AppColors.defaultPrimaryRed;
    _secondaryColor = AppColors.defaultSecondaryPurple;
    _isGradient = true;
    _gradientAngle = 135.0;
    _glowIntensity = 0.5;

    // Clear Cache
    _prefs.remove('theme_primary_color');
    _prefs.remove('theme_secondary_color');
    _prefs.remove('theme_is_gradient');
    _prefs.remove('theme_gradient_angle');
    _prefs.remove('theme_glow_intensity');

    AppColors.updateDynamicColors(
      primary: _primaryColor,
      secondary: _secondaryColor,
      isGradient: true,
      angle: 135.0,
      glow: 0.5,
    );

    notifyListeners();
  }

  Color _colorFromHex(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  @override
  void dispose() {
    _themeSubscription?.cancel();
    super.dispose();
  }
}
