import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import 'home_screen.dart';
import 'new_password_screen.dart';

// Added recovery and emailChange support
enum OtpVerificationPurpose {
  signup,
  login,
  updatePhone,
  recovery,
  emailChange,
}

class VerifyOtpScreen extends StatefulWidget {
  final String contact; // Changed from phone to contact (email or phone)
  final OtpVerificationPurpose purpose;

  const VerifyOtpScreen({
    super.key,
    required this.contact,
    required this.purpose,
  });

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final _supabaseService = SupabaseService();
  bool _isLoading = false;
  int _timerSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timerSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => _timerSeconds--);
      }
    });
  }

  Future<void> _resendOtp() async {
    if (_timerSeconds > 0) return;

    setState(() => _isLoading = true);
    try {
      if (widget.purpose == OtpVerificationPurpose.login) {
        await _supabaseService.signInWithOtp(widget.contact);
      } else if (widget.purpose == OtpVerificationPurpose.signup) {
        await _supabaseService.resendOtp(widget.contact, type: OtpType.signup);
      } else if (widget.purpose == OtpVerificationPurpose.recovery) {
        // For recovery, we must trigger the reset password email again
        await _supabaseService.resetPasswordForEmail(widget.contact);
      } else if (widget.purpose == OtpVerificationPurpose.emailChange) {
        // Email change resend usually requires re-triggering the update or using specific generic resend if supported
        // Standard resend supports 'emailChange' type
        await _supabaseService.resendOtp(
          widget.contact,
          type: OtpType.emailChange,
        );
      } else if (widget.purpose == OtpVerificationPurpose.updatePhone) {
        await _supabaseService.resendOtp(
          widget.contact,
          type: OtpType.phoneChange,
        );
      }

      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم إعادة إرسال الرمز"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("خطأ في الإرسال: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    String otp = _controllers.map((c) => c.text).join();
    if (otp.length < 6) return;

    setState(() => _isLoading = true);
    try {
      OtpType type = OtpType.signup;
      if (widget.purpose == OtpVerificationPurpose.signup) {
        type = OtpType.signup; // Verifies email signup
      } else if (widget.purpose == OtpVerificationPurpose.recovery) {
        type = OtpType.recovery;
      } else if (widget.purpose == OtpVerificationPurpose.emailChange) {
        type = OtpType.emailChange;
      } else if (widget.purpose == OtpVerificationPurpose.updatePhone) {
        type = OtpType.phoneChange;
      } else {
        type = OtpType.sms; // Fallback or MagicLink
      }

      await _supabaseService.verifyOtp(widget.contact, otp, type: type);

      if (mounted) {
        if (widget.purpose == OtpVerificationPurpose.recovery) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const NewPasswordScreen()),
          );
        } else if (widget.purpose == OtpVerificationPurpose.updatePhone ||
            widget.purpose == OtpVerificationPurpose.emailChange) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("رمز التحقق غير صحيح: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine label based on if contact looks like email
    final isEmail = widget.contact.contains('@');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isEmail ? "التحقق من البريد" : "التحقق من الهاتف",
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              isEmail ? Icons.mark_email_read_outlined : Icons.sms_outlined,
              size: 80,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              "أدخل رمز التحقق الذي تم إرساله إلى ${isEmail ? 'البريد الإلكتروني' : 'رقم الهاتف'}",
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              widget.contact,
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 40),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) => _otpBox(index)),
              ),
            ),
            const SizedBox(height: 40),
            _isLoading
                ? CircularProgressIndicator(color: AppColors.primary)
                : ElevatedButton(
                    onPressed: _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      "تحقق الآن",
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _timerSeconds == 0 ? _resendOtp : null,
                  child: Text(
                    "إعادة إرسال الرمز",
                    style: GoogleFonts.cairo(
                      color: _timerSeconds == 0
                          ? AppColors.primary
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_timerSeconds > 0)
                  Text(
                    "خلال $_timerSeconds ثانية",
                    style: GoogleFonts.cairo(color: Colors.grey),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 45,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: "",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          if (index == 5 && value.isNotEmpty) {
            _verifyOtp();
          }
        },
      ),
    );
  }
}
