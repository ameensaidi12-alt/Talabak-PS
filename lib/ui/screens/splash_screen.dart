import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  String? _logoUrl;
  String? _bgImageUrl;
  Color _bgColor = Colors.white;
  Color _textColor = AppColors.primary;
  Color? _gradientStart;
  Color? _gradientEnd;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _controller.forward();
    _initializeApp();
  }

  Color _parseColor(String? colorStr, Color defaultColor) {
    if (colorStr == null || colorStr.isEmpty) return defaultColor;
    try {
      String hex = colorStr.replaceAll("#", "");
      if (hex.length == 6) hex = "FF$hex";
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return defaultColor;
    }
  }

  Future<void> _initializeApp() async {
    // 1. Load from cache first for instant display
    await _loadCachedSettings();
    
    // 2. Start Minimum wait timer
    final minWait = Future.delayed(const Duration(seconds: 3));

    // 3. Fetch fresh settings in background
    _fetchFreshSettings();

    await minWait;

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _loadCachedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          final logo = prefs.getString('splash_logo_url');
          _logoUrl = (logo != null && logo.isNotEmpty) ? logo : null;
          
          final bgImg = prefs.getString('splash_bg_image_url');
          _bgImageUrl = (bgImg != null && bgImg.isNotEmpty) ? bgImg : null;
          
          _bgColor = _parseColor(prefs.getString('splash_bg_color'), Colors.white);
          _textColor = _parseColor(prefs.getString('splash_theme_color'), AppColors.primary);
          
          final gStart = prefs.getString('splash_gradient_start');
          final gEnd = prefs.getString('splash_gradient_end');
          if (gStart != null && gStart.isNotEmpty && gEnd != null && gEnd.isNotEmpty) {
            _gradientStart = _parseColor(gStart, Colors.white);
            _gradientEnd = _parseColor(gEnd, Colors.white);
          } else {
            _gradientStart = null;
            _gradientEnd = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading splash cache: $e");
    }
  }

  Future<void> _fetchFreshSettings() async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    try {
      // 1. Fetch UI Settings and Pre-fetch Main Data concurrently
      final results = await Future.wait([
        supabaseService.getAppSetting('login_logo_url'),
        supabaseService.getAppSetting('splash_bg_color'),
        supabaseService.getAppSetting('splash_theme_color'),
        supabaseService.getAppSetting('splash_full_bg_url'),
        supabaseService.getAppSetting('splash_gradient_start'),
        supabaseService.getAppSetting('splash_gradient_end'),
        
        // --- Pre-fetching Data for Instant Home Screen ---
        supabaseService.getPromotions(),
        supabaseService.getHomeGroupedData('restaurant'),
        supabaseService.getHomeGroupedData('supermarket'),
      ]);

      final prefs = await SharedPreferences.getInstance();

      final loginLogo = results[0] as String?;
      final bgColor = results[1] as String?;
      final themeColor = results[2] as String?;
      final fullBg = results[3] as String?;
      final gStart = results[4] as String?;
      final gEnd = results[5] as String?;
      
      // Save to cache for next time
      if (loginLogo != null) await prefs.setString('splash_logo_url', loginLogo);
      if (bgColor != null) await prefs.setString('splash_bg_color', bgColor);
      if (themeColor != null) await prefs.setString('splash_theme_color', themeColor);
      if (fullBg != null) await prefs.setString('splash_bg_image_url', fullBg);
      if (gStart != null) await prefs.setString('splash_gradient_start', gStart);
      if (gEnd != null) await prefs.setString('splash_gradient_end', gEnd);

      if (mounted) {
        setState(() {
          if (loginLogo != null && loginLogo.isNotEmpty) _logoUrl = loginLogo;
          _bgColor = _parseColor(bgColor, _bgColor);
          _textColor = _parseColor(themeColor, _textColor);
          
          if (fullBg != null && fullBg.isNotEmpty) {
            _bgImageUrl = fullBg;
          } else if (fullBg == "") {
            _bgImageUrl = null;
          }
          
          if (gStart != null && gStart.isNotEmpty && 
              gEnd != null && gEnd.isNotEmpty) {
            _gradientStart = _parseColor(gStart, _gradientStart ?? Colors.white);
            _gradientEnd = _parseColor(gEnd, _gradientEnd ?? Colors.white);
          } else if (gStart == "" || gEnd == "") {
            _gradientStart = null;
            _gradientEnd = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching fresh splash settings: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool hasGradient = _gradientStart != null && _gradientEnd != null;
    
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Layer (Solid, Gradient or Image)
          Container(
            decoration: BoxDecoration(
              color: _bgColor,
              gradient: hasGradient ? LinearGradient(
                colors: [_gradientStart!, _gradientEnd!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ) : null,
              image: _bgImageUrl != null ? DecorationImage(
                image: CachedNetworkImageProvider(_bgImageUrl!),
                fit: BoxFit.cover,
              ) : null,
            ),
          ),
          
          // 2. Overlay removed or adjusted to be optional - User wants image alone
          // if (_bgImageUrl != null)
          //   Container(color: Colors.black.withOpacity(0.1)),

          // 3. Center Content (Logo + Name) - Only if NO full background image
          if (_bgImageUrl == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _opacityAnimation.value,
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _textColor.withOpacity(0.05),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _textColor.withOpacity(0.1),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: _logoUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _logoUrl!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.contain,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, __) => const SizedBox(width: 120, height: 120),
                              errorWidget: (_, __, ___) => Icon(
                                Icons.delivery_dining_rounded,
                                size: 100,
                                color: _textColor,
                              ),
                            )
                          : Icon(
                              Icons.delivery_dining_rounded,
                              size: 100,
                              color: _textColor,
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _opacityAnimation.value,
                        child: child,
                      );
                    },
                    child: Column(
                      children: [
                        Text(
                          "Talabak PS",
                          style: GoogleFonts.cairo(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: _textColor,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          "الجودة تصلك أينما كنت",
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            color: _textColor.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
