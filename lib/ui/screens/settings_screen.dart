import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import 'webview_screen.dart';
import '../widgets/social_media_row.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  String _selectedLanguage = "العربية";
  final _supabaseService = SupabaseService();
  String? _facebookUrl;
  String? _instagramUrl;
  String? _whatsappUrl;

  @override
  void initState() {
    super.initState();
    _loadSocialLinks();
  }

  Future<void> _loadSocialLinks() async {
    try {
      final fb = await _supabaseService.getAppSetting('url_facebook');
      final ig = await _supabaseService.getAppSetting('url_instagram');
      final wa = await _supabaseService.getAppSetting('url_whatsapp');
      if (mounted) {
        setState(() {
          _facebookUrl = fb;
          _instagramUrl = ig;
          _whatsappUrl = wa;
        });
      }
    } catch (e) {
      debugPrint("Error loading social links in settings: $e");
    }
  }


  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "اختر اللغة",
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text("العربية", style: GoogleFonts.cairo()),
              trailing: _selectedLanguage == "العربية"
                  ? Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _selectedLanguage = "العربية");
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text("English", style: GoogleFonts.cairo()),
              trailing: _selectedLanguage == "English"
                  ? Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _selectedLanguage = "English");
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          "الإعدادات",
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingsGroup("العام", [
            _buildSettingsItem(
              Icons.language,
              "اللغة",
              _selectedLanguage,
              _showLanguagePicker,
            ),
            _buildSettingsItem(
              Icons.notifications_outlined,
              "الإشعارات",
              _notificationsEnabled ? "مفعلة" : "معطلة",
              null,
              trailing: Switch(
                value: _notificationsEnabled,
                activeColor: AppColors.primary,
                onChanged: (val) => setState(() => _notificationsEnabled = val),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSettingsGroup("الدعم والقانونية", [
            _buildSettingsItem(
              Icons.privacy_tip_outlined,
              "سياسة الخصوصية",
              null,
              () async {
                final service = Provider.of<SupabaseService>(context, listen: false);
                final url = await service.getAppSetting('url_privacy') ?? 
                           "https://ylpjqejnvhaqbdssjaof.supabase.co/functions/v1/legal?slug=privacy";
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewScreen(
                        url: url,
                        title: "سياسة الخصوصية",
                      ),
                    ),
                  );
                }
              },
            ),
            _buildSettingsItem(
              Icons.description_outlined,
              "شروط الاستخدام",
              null,
              () async {
                final service = Provider.of<SupabaseService>(context, listen: false);
                final url = await service.getAppSetting('url_terms') ?? 
                           "https://ylpjqejnvhaqbdssjaof.supabase.co/functions/v1/legal?slug=terms";
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewScreen(
                        url: url,
                        title: "شروط الاستخدام",
                      ),
                    ),
                  );
                }
              },
            ),
            _buildSettingsItem(
              Icons.info_outline,
              "طلب حذف بيانات الحساب",
              null,
              () async {
                final service = Provider.of<SupabaseService>(context, listen: false);
                final url = await service.getAppSetting('url_delete_account') ?? 
                           "https://ylpjqejnvhaqbdssjaof.supabase.co/functions/v1/legal?slug=delete_account";
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewScreen(
                        url: url,
                        title: "طلب حذف الحساب",
                      ),
                    ),
                  );
                }
              },
            ),
            _buildSettingsItem(
              Icons.star_outline,
              "تقييم التطبيق",
              null,
              () async {
                final user = Supabase.instance.client.auth.currentUser;
                final service = Provider.of<SupabaseService>(context, listen: false);
                
                // Fetch profile to get the full name
                final profile = await service.getUserProfile();
                
                final phone = profile?.phone ?? user?.userMetadata?['phone'] ?? user?.phone ?? user?.id ?? "مستخدم مجهول";
                final name = profile?.fullName ?? user?.userMetadata?['full_name'] ?? "مستخدم مجهول";
                
                final baseUrl = await service.getAppSetting('url_support') ?? "https://talabakps.com/support/";
                // Ensure the base URL ends with a slash or question mark to handle query parameters correctly.
                final String separator = baseUrl.contains('?') ? '&' : '?';
                final url = "$baseUrl$separator" "user_id=${Uri.encodeComponent(phone.toString())}&full_name=${Uri.encodeComponent(name.toString())}";
                
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewScreen(
                        url: url,
                        title: "تقييم التطبيق",
                      ),
                    ),
                  );
                }
              },
            ),
          ]),
          const SizedBox(height: 32),
          const SizedBox(height: 32),
          Center(
            child: FutureBuilder<String>(
              future: Provider.of<SupabaseService>(context, listen: false).getAppVersion(),
              builder: (context, snapshot) {
                final version = snapshot.data ?? '1.0.0';
                return Text(
                  "Talabak PS v$version",
                  style: GoogleFonts.cairo(color: Colors.grey, fontSize: 12),
                );
              },
            ),
          ),
          const SizedBox(height: 40),
          SocialMediaRow(
            facebookUrl: _facebookUrl,
            instagramUrl: _instagramUrl,
            whatsappUrl: _whatsappUrl,
          ),
          const SizedBox(height: 20),
        ],
      ),

    );
  }

  Widget _buildSettingsGroup(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              fontSize: 16,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildSettingsItem(
    IconData icon,
    String title,
    String? trailingText,
    VoidCallback? onTap, {
    Widget? trailing,
    Color? textColor,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.grey[600]),
      title: Text(
        title,
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailingText != null)
                Text(
                  trailingText,
                  style: GoogleFonts.cairo(color: Colors.grey),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
      onTap: onTap,
    );
  }
}
