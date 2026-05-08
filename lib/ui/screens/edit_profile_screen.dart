import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import 'login_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isLoading = false;
  String? _initialEmail;
  String? _initialPhone;

  @override
  void initState() {
    super.initState();
    final supabase = SupabaseService();
    final user = supabase.client.auth.currentUser;
    _nameController = TextEditingController(
      text: user?.userMetadata?['full_name'] ?? "",
    );
    _emailController = TextEditingController(text: user?.email ?? "");
    _initialEmail = user?.email;
    _phoneController = TextEditingController();
    _loadPhoneNumber();
  }

  Future<void> _loadPhoneNumber() async {
    try {
      final supabase = SupabaseService();
      final profile = await supabase.getUserProfile();
      final phone = profile?['phone'] as String?;
      if (phone != null && mounted) {
        setState(() {
          _initialPhone = phone;
          _phoneController.text = phone;
        });
      }
    } catch (e) {
      debugPrint("Error loading phone: $e");
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final supabase = SupabaseService();

      // Update Profile (Metadata and Profiles table)
      await supabase.updateUserProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      // 2. Check for Email Change
      final newEmail = _emailController.text.trim();
      if (newEmail != _initialEmail && newEmail.isNotEmpty) {
        await supabase.client.auth.updateUser(UserAttributes(email: newEmail));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "تم إرسال رابط تأكيد إلى البريد الإلكتروني الجديد. يرجى تأكيده لتحديث البريد.",
              ),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم تحديث الملف الشخصي بنجاح"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } on AuthException catch (e) {
      if (mounted) {
        String msg = "خطأ في التحديث";
        if (e.message.contains("already been registered") ||
            e.code == 'phone_exists') {
          msg = "رقم الهاتف هذا مسجل مسبقاً لحساب آخر";
        } else {
          msg = e.message;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("خطأ في التحديث: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showDeleteAccountConfirmation() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "تأكيد حذف الحساب",
          textAlign: TextAlign.right,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        content: Text(
          "هل أنت متأكد من رغبتك في حذف حسابك نهائياً؟ لا يمكن التراجع عن هذا الإجراء وسيتم مسح جميع بياناتك.",
          textAlign: TextAlign.right,
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("إلغاء", style: GoogleFonts.cairo(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                final supabase = SupabaseService();
                await supabase.deleteAccount();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("خطأ في حذف الحساب: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: Text(
              "حذف نهائي",
              style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "تعديل الملف الشخصي",
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: const Color(0xFFFDE8ED),
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                _buildLabel("الاسم الكامل"),
                TextFormField(
                  controller: _nameController,
                  textAlign: TextAlign.right,
                  decoration: _inputDecoration(
                    "أدخل اسمك الكامل",
                    Icons.person_outline,
                  ),
                  validator: (val) =>
                      (val == null || val.isEmpty) ? "يرجى إدخال الاسم" : null,
                ),
                const SizedBox(height: 24),
                _buildLabel("رقم الهاتف"),
                TextFormField(
                  controller: _phoneController,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(
                    "رقم الهاتف",
                    Icons.phone_android_outlined,
                  ),
                ),
                const SizedBox(height: 24),
                _buildLabel("البريد الإلكتروني"),
                TextFormField(
                  controller: _emailController,
                  textAlign: TextAlign.right,
                  readOnly: true,
                  enabled: false,
                  style: GoogleFonts.cairo(color: Colors.grey[600]),
                  decoration: _inputDecoration(
                    "البريد الإلكتروني (غير قابل للتعديل)",
                    Icons.email_outlined,
                  ).copyWith(fillColor: Colors.grey[100], filled: true),
                  validator: (val) => (val == null || !val.contains('@'))
                      ? "بريد إلكتروني غير صحيح"
                      : null,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            "حفظ التغييرات",
                            style: GoogleFonts.cairo(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    onPressed: _showDeleteAccountConfirmation,
                    icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                    label: Text(
                      "حذف الحساب نهائياً",
                      style: GoogleFonts.cairo(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}
