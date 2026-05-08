import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import 'login_screen.dart';
import 'verify_otp_screen.dart';
import 'complete_profile_screen.dart';
import 'home_screen.dart';
import '../widgets/social_media_row.dart';
import 'package:flutter/gestures.dart';
import 'webview_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabaseService = SupabaseService();
  bool _loading = false;
  String? _loginLogoUrl;
  String? _facebookUrl;
  String? _instagramUrl;
  String? _whatsappUrl;
  bool _agreedToTerms = false;


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
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || email.isEmpty || phone.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "يرجى تعبئة جميع الحقول (الاسم، البريد، الهاتف، وكلمة المرور 6 أحرف على الأقل)",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("يرجى الموافقة على شروط الاستخدام وسياسة الخصوصية للمتابعة"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("يرجى إدخال بريد إلكتروني صحيح"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _supabaseService.signUp(email, password, name, phone: phone);
      await _supabaseService.syncGuestLocationWithUser();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyOtpScreen(
              contact: email,
              purpose: OtpVerificationPurpose.signup,
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        String msg = "حدث خطأ";
        if (e.message.contains("User already registered")) {
          msg = "البريد الإلكتروني مسجل بالفعل";
        } else if (e.code == 'phone_exists' ||
            e.message.contains("phone number has already been registered")) {
          msg = "رقم الهاتف مسجل بالفعل لحساب آخر";
        } else {
          msg = e.message;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $msg"), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await _supabaseService.signInWithGoogle();
      await _supabaseService.syncGuestLocationWithUser();

      if (!mounted) return;

      final profile = await _supabaseService.getUserProfile();
      final fullName = profile?['full_name'] as String?;
      final phone = profile?['phone'] as String?;

      if (!mounted) return;

      if (fullName == null || fullName.isEmpty || phone == null || phone.isEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CompleteProfileScreen(initialName: fullName),
          ),
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("فشل التسجيل بجوجل: $e"),
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
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
                "أنشئ حسابك الجديد وابدأ تجربة تسوق فريدة",
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),
              
              _refinedTextField(_nameController, "الأسم الكامل", Icons.person_outline_rounded),
              const SizedBox(height: 20),
              _refinedTextField(
                _emailController,
                "البريد الإلكتروني",
                Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              _refinedTextField(
                _phoneController,
                "رقم الهاتف",
                Icons.phone_android_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),
              _refinedTextField(
                _passwordController,
                "كلمة المرور",
                Icons.lock_outline_rounded,
                obscure: true,
              ),
              
              const SizedBox(height: 10),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _agreedToTerms,
                    activeColor: AppColors.primary,
                    onChanged: (value) {
                      setState(() {
                        _agreedToTerms = value ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        text: "أوافق على ",
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(
                            text: "شروط الاستخدام",
                            style: GoogleFonts.cairo(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()..onTap = () async {
                              final url = await _supabaseService.getAppSetting('url_terms') ?? 
                                          "https://ylpjqejnvhaqbdssjaof.supabase.co/functions/v1/legal?slug=terms";
                              if (mounted) {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewScreen(url: url, title: "شروط الاستخدام")));
                              }
                            },
                          ),
                          const TextSpan(text: " و "),
                          TextSpan(
                            text: "سياسة الخصوصية",
                            style: GoogleFonts.cairo(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()..onTap = () async {
                              final url = await _supabaseService.getAppSetting('url_privacy') ?? 
                                          "https://ylpjqejnvhaqbdssjaof.supabase.co/functions/v1/legal?slug=privacy";
                              if (mounted) {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewScreen(url: url, title: "سياسة الخصوصية")));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              if (_loading)
                CircularProgressIndicator(color: AppColors.primary)
              else
                Column(
                  children: [
                    _buildPremiumButton(
                      text: "تسجيل جديد",
                      onPressed: _signUp,
                    ),
                    const SizedBox(height: 16),
                    _buildGoogleSignInButton(),
                    const SizedBox(height: 12),
                    Text(
                      "التسجيل عبر جوجل يعني موافقتك على شروط الاستخدام وسياسة الخصوصية",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.grey[500],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 30),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "لديك حساب بالفعل؟ ",
                    style: GoogleFonts.cairo(color: Colors.grey[600]),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: Text(
                      "سجل دخول الآن",
                      style: GoogleFonts.cairo(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 50),
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
          "التسجيل باستخدام جوجل",
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
