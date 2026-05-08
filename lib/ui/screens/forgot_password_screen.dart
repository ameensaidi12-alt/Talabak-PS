import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart'; // Ensure SupabaseService is available if needed, though direct client usage is fine.
import 'verify_otp_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _loading = false;
  bool _otpSent = false;

  final _supabase = Supabase.instance.client;

  // إرسال OTP
  Future<void> _sendOtp() async {
    if (_emailController.text.isEmpty) {
      _showSnackBar("الرجاء إدخال البريد الإلكتروني");
      return;
    }

    setState(() => _loading = true);
    try {
      await _supabase.auth.resetPasswordForEmail(_emailController.text.trim());
      setState(() => _otpSent = true);
      _showSnackBar("تم إرسال OTP إلى بريدك الإلكتروني");

      // Navigate to OTP screen like before, or stay here if user wants inline.
      // The user code showed inline logic (if _otpSent ... show fields).
      // However, our previous logic used VerifyOtpScreen.
      // Let's stick to the user's manual change request which implies they wanted to try inline or custom logic.
      // BUT, checking the user snippet, they just copy-pasted ForgotPasswordScreen content INTO LoginScreen file.
      // They probably want this logic inside ForgotPasswordScreen.
    } catch (e) {
      _showSnackBar("خطأ عند إرسال OTP: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  // التحقق من OTP وتغيير كلمة المرور
  Future<void> _verifyOtpAndChangePassword() async {
    if (_otpController.text.isEmpty || _newPasswordController.text.isEmpty) {
      _showSnackBar("الرجاء إدخال OTP وكلمة المرور الجديدة");
      return;
    }

    setState(() => _loading = true);
    try {
      // Use verifyOTP first to get a session
      final response = await _supabase.auth.verifyOTP(
        email: _emailController.text.trim(),
        token: _otpController.text.trim(),
        type: OtpType.recovery,
      );

      if (response.session != null) {
        // Now update password
        await _supabase.auth.updateUser(
          UserAttributes(password: _newPasswordController.text.trim()),
        );
        _showSnackBar("تم تغيير كلمة المرور بنجاح!");
        Navigator.pop(context); // Go back to login
      } else {
        _showSnackBar("رمز OTP غير صحيح");
      }
    } catch (e) {
      _showSnackBar("خطأ عند تغيير كلمة المرور: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("نسيت كلمة المرور"),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              _textField(
                _emailController,
                "البريد الإلكتروني",
                Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              if (_otpSent) ...[
                _textField(_otpController, "أدخل OTP", Icons.lock_clock),
                const SizedBox(height: 16),
                _textField(
                  _newPasswordController,
                  "كلمة المرور الجديدة",
                  Icons.lock_outline,
                  obscure: true,
                ),
                const SizedBox(height: 20),
                _loading
                    ? CircularProgressIndicator(color: AppColors.primary)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: _verifyOtpAndChangePassword,
                        child: const Text(
                          "تغيير كلمة المرور",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
              ] else ...[
                _loading
                    ? CircularProgressIndicator(color: AppColors.primary)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: _sendOtp,
                        child: const Text(
                          "إرسال OTP",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
