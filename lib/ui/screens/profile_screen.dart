import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import 'package:share_plus/share_plus.dart';
import 'login_screen.dart';
import 'address_selection_screen.dart';
import 'favorite_vendors_screen.dart';
import 'chat_support_screen.dart';
import 'edit_profile_screen.dart';
import '../../core/models/models.dart';
import 'star_points_history_screen.dart';
import 'game_launch_screen.dart';
import 'webview_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../widgets/social_media_row.dart';



class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final _supabaseService = SupabaseService();
  late AnimationController _animationController;
  String _privacyContent = "جاري التحميل...";
  String _termsContent = "جاري التحميل...";
  bool _isAdmin = false;
  String? _storeUrl;
  
  // Social Media URLs
  String? _facebookUrl;
  String? _instagramUrl;
  String? _whatsappUrl;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = _supabaseService.client.auth.currentUser;
    if (user != null) {
      final appRole = user.appMetadata['role'];
      final userRole = user.userMetadata?['role'];
      final email = user.email?.toLowerCase() ?? '';
      setState(() {
        _isAdmin = appRole == 'admin' || userRole == 'admin' || email.contains('admin');
      });
    }

    try {
      final pContent = await _supabaseService.getAppSetting('privacy_policy_content');
      final tContent = await _supabaseService.getAppSetting('terms_of_use_content');
      final sUrl = await _supabaseService.getAppSetting('store_url');
      
      // Fetch Social URLs
      final fb = await _supabaseService.getAppSetting('url_facebook');
      final ig = await _supabaseService.getAppSetting('url_instagram');
      final wa = await _supabaseService.getAppSetting('url_whatsapp');

      if (mounted) {
        setState(() {
          _privacyContent = (pContent != null && pContent.isNotEmpty) 
              ? pContent 
              : "سياسة الخصوصية\nنحن نهتم بخصوصيتك. يجمع تطبيق طلبك المعلومات الأساسية فقط لتوصيل طلباتك وتحسين الخدمة.";
          
          _termsContent = (tContent != null && tContent.isNotEmpty) 
              ? tContent 
              : "شروط الاستخدام\nباستخدامك لتطبيق طلبك، فإنك توافق على الالتزام بشروط الخدمة والدفع عند الاستلام.";
          
          _storeUrl = sUrl;
          _facebookUrl = fb;
          _instagramUrl = ig;
          _whatsappUrl = wa;
        });
      }
    } catch (e) {
      debugPrint("Error loading profile settings: $e");
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabaseService.client.auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "صفحتي",
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            StreamBuilder<UserProfile?>(
              stream: _supabaseService.streamUserProfile(),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                return Column(
                  children: [
                    _buildHeader(user),
                    if (profile != null) _buildStarPointsCard(profile),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _buildMenuItem(Icons.location_on_outlined, "عناويني", () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddressSelectionScreen(),
                      ),
                    );
                  }),
                  _buildMenuItem(Icons.favorite_border_rounded, "المطاعم المفضلة", () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FavoriteVendorsScreen(),
                      ),
                    );
                  }),
                  _buildMenuItem(
                    Icons.account_balance_wallet_outlined,
                    "وسائل الدفع",
                    () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) => Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(30),
                              topRight: Radius.circular(30),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 12),
                              Container(
                                width: 40,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(height: 30),
                              Text(
                                "وسائل الدفع المتاحة",
                                style: GoogleFonts.cairo(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 20),
                              ListTile(
                                leading: const Icon(Icons.money_outlined, color: Colors.green, size: 30),
                                title: Text(
                                  "الدفع نقدي عند الاستلام",
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text(
                                  "ادفع نقداً عند وصول الطلب إلى باب منزلك",
                                  style: GoogleFonts.cairo(fontSize: 13),
                                ),
                                trailing: const Icon(Icons.check_circle, color: Colors.green),
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  _buildMenuItem(Icons.card_giftcard_rounded, "العروض والكوبونات", () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("العروض والكوبونات قريباً")),
                    );
                  }),
                  _buildGameHubMenuItem(() {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GameLaunchScreen()),
                    );
                  }),
                  _buildMenuItem(Icons.share_outlined, "شارك التطبيق مع أصدقائك", () async {
                    await Share.share(
                      "اكتشف تطبيق طلبك! أسهل طريقة لطلب احتياجاتك في فلسطين.\nحمّل التطبيق الآن: https://talabakps.com",
                    );
                  }),
                  _buildMenuItem(Icons.privacy_tip_outlined, "سياسة الخصوصية", () async {
                    final url = await _supabaseService.getAppSetting('url_privacy') ?? 
                                "https://ylpjqejnvhaqbdssjaof.supabase.co/functions/v1/legal?slug=privacy";
                    if (mounted) {
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
                  }),
                  _buildMenuItem(Icons.description_outlined, "شروط الاستخدام", () async {
                    final url = await _supabaseService.getAppSetting('url_terms') ?? 
                                "https://ylpjqejnvhaqbdssjaof.supabase.co/functions/v1/legal?slug=terms";
                    if (mounted) {
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
                  }),
                  _buildMenuItem(Icons.help_outline_rounded, "مركز المساعدة", () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatSupportScreen()),
                    );
                  }),
                  const SizedBox(height: 30),

                  _buildSocialSection(),
                  const SizedBox(height: 20),
                  _buildLogoutButton(context, _supabaseService),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(dynamic user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[100]!, width: 1),
        ),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.1 + (0.2 * _animationController.value)),
                      blurRadius: 15 + (15 * _animationController.value),
                      spreadRadius: 2 * _animationController.value,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 55,
                  backgroundColor: const Color(0xFFFFF5F5),
                  child: Icon(
                    Icons.person_rounded,
                    size: 60,
                    color: AppColors.primary.withOpacity(0.8),
                  ),
                ),
                Positioned(
                  bottom: 5,
                  right: 5,
                  child: InkWell(
                    onTap: () async {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      );
                      if (updated == true) {
                        setState(() {});
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mode_edit_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            user?.userMetadata?['full_name'] ?? "مستخدم جديد",
            style: GoogleFonts.cairo(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? "",
            style: GoogleFonts.cairo(
              color: Colors.grey[500],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialSection() {

    return SocialMediaRow(
      facebookUrl: _facebookUrl,
      instagramUrl: _instagramUrl,
      whatsappUrl: _whatsappUrl,
    );
  }


  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
        title: Text(
          title,
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Colors.grey[800],
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: Colors.grey[400],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildGameHubMenuItem(VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFD00030), 
            Color(0xFFFF3B30), 
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3B30).withOpacity(0.5),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // النجوم البراقة في الخلفية
            Positioned(
              top: -15,
              right: -10,
              child: Icon(Icons.star_rounded, color: Colors.white.withOpacity(0.15), size: 70),
            ),
            Positioned(
              bottom: -10,
              left: 40,
              child: Icon(Icons.star_rounded, color: Colors.amber.withOpacity(0.25), size: 45),
            ),
            Positioned(
              top: 10,
              left: 120,
              child: Icon(Icons.star_rounded, color: Colors.white.withOpacity(0.2), size: 25),
            ),
            Positioned(
              bottom: 15,
              right: 80,
              child: Icon(Icons.star_rounded, color: Colors.amberAccent.withOpacity(0.3), size: 18),
            ),
            
            // المحتوى الرئيسي للزر
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 28),
              ),
              title: Text(
                "مجمع الألعاب | Game Hub",
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                "العب واربح نجوم ومكافآت!",
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 20,
                  color: Color(0xFFD00030),
                ),
              ),
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarPointsCard(UserProfile profile) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFD00030), // نفس لون البداية لزر الألعاب
            Color(0xFFFF453A), // لون أحمر مشع ومتقارب جداً مع فرق بسيط
          ],
          begin: Alignment.bottomLeft, // عكس الاتجاه ليعطي فرقاً بصرياً خفيفاً
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "نجومك",
                  style: GoogleFonts.cairo(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  "${profile.starPoints} نجمة",
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StarPointsHistoryScreen(),
                ),
              );
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              "التفاصيل",
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(
    BuildContext context,
    SupabaseService supabaseService,
  ) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey[100],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await supabaseService.signOut();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }
          },
          child: Center(
            child: Text(
              "تسجيل الخروج",
              style: GoogleFonts.cairo(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
