import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'complete_profile_screen.dart';
import 'home_screen.dart';
import '../widgets/social_media_row.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabaseService = SupabaseService();
   bool _loading = false;
  String? _loginLogoUrl;
  String? _facebookUrl;
  String? _instagramUrl;
  String? _whatsappUrl;
  bool _obscurePassword = true;


  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    try {
      final logo = await _supabaseService.getAppSetting('login_logo_url');
      final fb = await _supabaseService.getAppSetting('url_facebook');
      final ig = await _supabaseService.getAppSetting('url_instagram');
      final wa = await _supabaseService.getAppSetting('url_whatsapp');
      
      if (mounted) {
        setState(() {
          _loginLogoUrl = logo;
          _facebookUrl = fb;
          _instagramUrl = ig;
          _whatsappUrl = wa;
        });
      }
    } catch (e) {
      debugPrint("Error fetching settings: $e");
    }

  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);

    try {
      await _supabaseService.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      // Sync guest location with user profile
      await _supabaseService.syncGuestLocationWithUser();

      if (!mounted) return;

      // Check if profile is complete
      final profile = await _supabaseService.getUserProfile();
      final fullName = profile?['full_name'] as String?;
      final phone = profile?['phone'] as String?;

      if (!mounted) return;

      if (fullName == null ||
          fullName.isEmpty ||
          phone == null ||
          phone.isEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CompleteProfileScreen(initialName: fullName),
          ),
        );
      } else {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true); // Return to previous screen
        } else {
          // If this is the root (e.g. after logout), go to HomeScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } on AuthException catch (e) {
      if (!mounted) return;

      String msg = "حدث خطأ";
      if (e.message.contains("Invalid login credentials")) {
        msg = "البريد الإلكتروني أو كلمة المرور غير صحيحة";
      } else if (e.message.contains("Email not confirmed")) {
        msg = "يرجى تفعيل حسابك من البريد الإلكتروني أولاً";
      } else {
        msg = e.message;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ غير متوقع: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);

    try {
      await _supabaseService.signInWithGoogle();

      // Sync guest location with user profile
      await _supabaseService.syncGuestLocationWithUser();

      if (!mounted) return;

      // Check if profile is complete
      final profile = await _supabaseService.getUserProfile();
      final fullName = profile?['full_name'] as String?;
      final phone = profile?['phone'] as String?;

      if (!mounted) return;

      if (fullName == null ||
          fullName.isEmpty ||
          phone == null ||
          phone.isEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CompleteProfileScreen(initialName: fullName),
          ),
        );
      } else {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("فشل تسجيل الدخول بجوجل: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Animated Premium Logo
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5F5),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.1 + (0.3 * _animationController.value)),
                          blurRadius: 20 + (20 * _animationController.value),
                          spreadRadius: 4 * _animationController.value,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: _loginLogoUrl != null
                    ? Image.network(
                        _loginLogoUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.delivery_dining_rounded,
                          size: 80,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(
                        Icons.delivery_dining_rounded,
                        size: 80,
                        color: AppColors.primary,
                      ),
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Text(
                    "Talabak PS",
                    style: GoogleFonts.cairo(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      letterSpacing: 1,
                      shadows: [
                        Shadow(
                          color: AppColors.primary.withOpacity(0.2 + (0.2 * _animationController.value)),
                          blurRadius: 10 * _animationController.value,
                          offset: Offset(0, 4 * _animationController.value),
                        ),
                        Shadow(
                          color: AppColors.primary.withOpacity(0.1 * _animationController.value),
                          blurRadius: 20 * _animationController.value,
                          offset: Offset(0, 8 * _animationController.value),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                "أهلاً بك في طلبك - الجودة تصلك أينما كنت",
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 30),
              
              // Input Section
              _refinedTextField(
                _emailController,
                "البريد الإلكتروني",
                Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _refinedTextField(
                _passwordController,
                "كلمة المرور",
                Icons.lock_outline_rounded,
                obscure: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  ),
                  child: Text(
                    "نسيت كلمة المرور؟",
                    style: GoogleFonts.cairo(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 15),
              
              if (_loading)
                CircularProgressIndicator(color: AppColors.primary)
              else
                Column(
                  children: [
                    _buildPremiumButton(
                      text: "تسجيل الدخول",
                      onPressed: _signIn,
                    ),
                    const SizedBox(height: 16),
                    _buildGoogleSignInButton(),
                    const SizedBox(height: 12),
                    Text(
                      "تسجيلك للدخول يعني موافقتك على شروط الاستخدام وسياسة الخصوصية",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.grey[500],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "ليس لديك حساب؟ ",
                    style: GoogleFonts.cairo(color: Colors.grey[600]),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text(
                      "سجل الآن مجاناً",
                      style: GoogleFonts.cairo(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              SocialMediaRow(
                facebookUrl: _facebookUrl,
                instagramUrl: _instagramUrl,
                whatsappUrl: _whatsappUrl,
              ),
            ],
          ),

        ),
      ),
    );
  }

  Widget _refinedTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(color: Colors.grey[500], fontSize: 14),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 22),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          floatingLabelStyle: GoogleFonts.cairo(color: AppColors.primary, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPremiumButton({required String text, required VoidCallback onPressed}) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSignInButton() {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: OutlinedButton.icon(
        icon: Image.network(
          'https://www.gstatic.com/images/branding/product/1x/googleg_48dp.png',
          height: 24,
        ),
        label: Text(
          "تسجيل الدخول باستخدام جوجل",
          style: GoogleFonts.cairo(
            color: Colors.grey[800],
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _signInWithGoogle,
      ),
    );
  }
}
