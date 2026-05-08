import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/models.dart';
import '../widgets/vendor_card.dart';
import 'cart_screen.dart';
import 'orders_list_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'chat_support_screen.dart';
import 'global_search_screen.dart';
import 'address_selection_screen.dart';
import 'address_details_screen.dart';
import 'vendors_map_screen.dart';
import '../../core/services/supabase_service.dart';
import 'favorite_vendors_screen.dart';
import 'settings_screen.dart';
import 'leaderboard_screen.dart';
import '../../core/utils/vendor_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/media_banner.dart';
import 'game_launch_screen.dart';
import '../../main.dart'; // To access routeObserver
import 'debug/logs_screen.dart';
import '../widgets/social_media_row.dart';
import '../widgets/product_bottom_sheet.dart';




class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final _supabaseService = SupabaseService();
  late Future<List<Vendor>> _vendorsFuture;
  late Future<List<Map<String, dynamic>>>
      _homeDataFuture; // New: Grouped categories and vendors
  int _currentIndex = 0;
  String? _selectedType;
  String? _selectedCategoryId;
  String? _selectedAreaId; // Filter by area
  String _selectedCategoryName = "قريب منك";
  String _currentStreetName = "مركز البلد"; // Specific point
  String _currentAreaName = "الشعراوية"; // General area
  StreamSubscription? _addressSubscription;

  // Banner/Ad state
  late Future<List<PromotionBanner>> _promotionsFuture;
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  bool _isSupportExpanded = false;
  int _unreadCount = 0;
  StreamSubscription? _unreadSub;
  StreamSubscription? _globalSettingsSub;
  bool _isAppClosed = false;
  bool _isUnderMaintenance = false;
  String? _appClosureMessage;
  bool _isScreenOnTop = true; // Track if this screen is currently visible
  bool _isAdminMode = false; // Admins and Supervisors
  bool _isFullAdmin = false; // Only Admins

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void didPushNext() {
    debugPrint("[Banner] Screen covered by next route, pausing auto-scroll and videos");
    setState(() => _isScreenOnTop = false);
    _autoScrollTimer?.cancel();
  }

  @override
  void didPopNext() {
    debugPrint("[Banner] Screen returned to top, resuming auto-scroll and videos");
    setState(() => _isScreenOnTop = true);
    _startAutoScroll();
  }
  String? _maintenanceMessage;
  String? _latestVersion;
  String? _storeUrl;
  String? _iosStoreUrl;
  String _homeGreeting = "شو جاي عبالك اليوم؟ 🤔";
  List<PromotionBanner> _currentAds = [];
  String? _facebookUrl;
  String? _instagramUrl;
  String? _whatsappUrl;
  bool _isUpdateSheetShown = false; // Flag to prevent flickering/re-opening
  bool _isMaintenanceShown = false;
  bool _isClosureShown = false;


  StreamSubscription<AuthState>? _authStateSub;
  bool _isLocationPickerActive = false; // Guard to prevent multiple pushes


  @override
  void initState() {
    super.initState();
    // Initialize with empty futures to avoid 'late initialization' errors
    // but DON'T start fetching until we have the location in _loadInitialData
    _vendorsFuture = Future.value([]);
    _homeDataFuture = Future.value([]);
    _promotionsFuture = Future.value([]);
    
    _loadInitialData();
    _listenToAddressChanges();
    _listenToUnreadMessages();
    _listenToGlobalSettings();
    _listenToAuthChanges(); // New: Update admin status on login
  }

  void _listenToAuthChanges() {
    _authStateSub = _supabaseService.client.auth.onAuthStateChange.listen((data) {
      if (data.session?.user != null) {
        _checkAdminStatus(data.session!.user);
      } else {
        setState(() => _isAdminMode = false);
      }
    });
  }

  Future<void> _checkAdminStatus(User user) async {
    final appRole = user.appMetadata['role'];
    final userRole = user.userMetadata?['role'];
    final email = user.email?.toLowerCase() ?? '';

    debugPrint("🔐 [Auth] Checking Admin Status for: $email");
    debugPrint("🔐 [Auth] Metadata Role: $appRole / $userRole");

    bool isAdm = appRole == 'admin' || userRole == 'admin' || appRole == 'supervisor' || email.contains('admin');
    bool isFull = appRole == 'admin' || userRole == 'admin' || email.contains('admin');

    if (!isAdm) {
      try {
        final profile = await _supabaseService.client.from('profiles').select('role').eq('id', user.id).maybeSingle();
        if (profile != null) {
           if (profile['role'] == 'admin' || profile['role'] == 'supervisor') isAdm = true;
           if (profile['role'] == 'admin') isFull = true;
        }
      } catch (e) {
        debugPrint("Error fetching role: $e");
      }
    }

    if (mounted) {
      if (isAdm != _isAdminMode || isFull != _isFullAdmin) {
        setState(() {
          _isAdminMode = isAdm;
          _isFullAdmin = isFull;
        });
      }

      // If we just became admin and a dialog/sheet was showing, close it
      if (isAdm) {
        // We use a small delay to ensure the navigator is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            debugPrint("🔐 [Auth] Closed block screen for admin");
          }
        });
      }
    }
  }



  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _authStateSub?.cancel();
    _addressSubscription?.cancel();
    _unreadSub?.cancel();
    _globalSettingsSub?.cancel();
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _listenToGlobalSettings() async {
    // 1. Get actual package version
    String versionOnly = "1.0.0";
    String fullVersion = "1.0.0+1";
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      versionOnly = packageInfo.version;
      fullVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      debugPrint("📱 [AppVersion] Current: $fullVersion");
    } catch (e) {
      debugPrint("❌ [AppVersion] Error getting package info: $e");
    }

    // 2. Fetch User Role reliably
    final user = _supabaseService.client.auth.currentUser;
    if (user != null) {
      await _checkAdminStatus(user);
    }

    // 3. Listen to settings
    _globalSettingsSub =
        _supabaseService.getAppSettingsStream().listen((settings) {
      if (!mounted) return;

      final closed = settings['is_app_closed'] == 'true';
      final maintenance = settings['is_under_maintenance'] == 'true';
      final latestVer = settings['latest_version'];

      setState(() {
        _isAppClosed = closed;
        _isUnderMaintenance = maintenance;
        _appClosureMessage = settings['app_closure_message'];
        _maintenanceMessage = settings['maintenance_message'];
        _latestVersion = latestVer;
        _storeUrl = settings['store_url'];
        _iosStoreUrl = settings['ios_store_url'];
        _homeGreeting = settings['home_greeting'] ?? "شو جاي عبالك اليوم؟ 🤔";
      });

      // Show maintenance/closure for non-admins only
      if (!_isAdminMode) {
        if (maintenance && !_isMaintenanceShown) {
          _isMaintenanceShown = true;
          _showMaintenanceSheet();
          return;
        } else if (closed && !_isClosureShown) {
          _isClosureShown = true;
          _showAppClosedDialog();
          return;
        }
      }

      // Show update sheet for EVERYONE if version is different
      if (latestVer != null && latestVer.isNotEmpty && !_isUpdateSheetShown) {
        bool isUpToDate = (latestVer == fullVersion || latestVer == versionOnly);
        
        if (!isUpToDate) {
          _isUpdateSheetShown = true;
          debugPrint("🚀 [AppVersion] Update available: Remote($latestVer) != Local($fullVersion)");
          // Add a tiny delay to ensure navigation/mount is stable
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _showUpdateSheet();
          });
        }
      }
    });
  }

  void _showMaintenanceSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.build_circle_outlined,
                size: 60,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                "التطبيق تحت الصيانة",
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _maintenanceMessage ?? "نحن نحدث النظام، سنعود قريباً!",
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _launchWhatsApp,
                icon: const Icon(Icons.chat),
                label: const Text("تواصل معنا عبر واتساب"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAppClosedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                "التطبيق مغلق",
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.access_time_filled, color: Colors.red),
            ],
          ),
          content: Text(
            _appClosureMessage ?? "نعتذر، نحن خارج ساعات العمل حالياً.",
            textAlign: TextAlign.right,
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => SystemChannels.platform.invokeMethod(
                'SystemNavigator.pop',
              ), // Exit app
              child: Text(
                "إغلاق التطبيق",
                style: GoogleFonts.cairo(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUpdateSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.system_update, size: 60, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              "تحديث جديد متاح",
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "يتوفر إصدار جديد من التطبيق بمميزات أفضل. يرجى التحديث الآن.",
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                String? targetUrl = _storeUrl;
                if (Platform.isIOS && _iosStoreUrl != null && _iosStoreUrl!.isNotEmpty) {
                  targetUrl = _iosStoreUrl;
                }
                
                if (targetUrl != null && targetUrl.isNotEmpty) {
                  final uri = Uri.parse(targetUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("تحديث الآن"),
            ),
          ],
        ),
      ),
    );
  }

  void _listenToUnreadMessages() {
    _unreadSub = _supabaseService.getChatSummaryStream().listen((summary) {
      if (mounted && summary != null) {
        setState(() {
          _unreadCount = summary['unread_count_user'] ?? 0;
        });
      }
    });
  }

  void _listenToAddressChanges() {
    _addressSubscription = _supabaseService.streamUserAddress().listen((
      addr,
    ) async {
      if (addr != null) {
        // Fetch area and its parent if exists
        String areaName = "قريبة مني";
        String parentName = "";
        if (addr['area_id'] != null) {
          final areas = await _supabaseService.getDeliveryAreas();
          final area = areas.firstWhere(
            (a) => a['id'] == addr['area_id'],
            orElse: () => {},
          );
          areaName = area['name'] ?? "قريبة مني";
          
          if (area['parent_id'] != null) {
            final parent = areas.firstWhere(
              (a) => a['id'] == area['parent_id'],
              orElse: () => {},
            );
            parentName = parent['name'] ?? "";
          }
        }

        if (mounted) {
          setState(() {
            _selectedAreaId = addr['area_id'];
            // If parent exists (e.g. Sha'rawiya), set it as currentAreaName
            // and use the village as the street/point name
            if (parentName.isNotEmpty) {
              _currentAreaName = parentName;
              _currentStreetName = areaName;
            } else {
              _currentAreaName = areaName;
              _currentStreetName = addr['address_line_1'] ?? "مركز البلد";
            }
            // Refresh vendors and promotions for the new area
            _vendorsFuture = _supabaseService.getVendors(
              areaId: _selectedAreaId,
            );
            _homeDataFuture = _supabaseService.getHomeGroupedData(
              _selectedType ?? 'restaurant',
              areaId: _selectedAreaId,
            );
            _promotionsFuture = _supabaseService.getPromotions(
              areaId: _selectedAreaId,
            ).then((ads) {
                if (mounted) {
                  setState(() => _currentAds = ads);
                  _startAutoScroll();
                }
                return ads;
            });
          });
        }
      }
    });
  }

  Future<void> _loadInitialData() async {
    // Refresh global settings (like 'New' badge toggle)
    await _supabaseService.initializeSettings();

    final user = _supabaseService.client.auth.currentUser;
    bool hasLocation = false;

    // 1. Try to fetch Auth addresses first
    if (user != null) {
      final addresses = await _supabaseService.getUserAddresses();
      debugPrint("🏠 [HomeScreen] Auth Addresses found: ${addresses.length}");
      if (addresses.isNotEmpty) {
        final defaultAddr = addresses.firstWhere(
          (a) => a['is_default'] == true,
          orElse: () => addresses.first,
        );
        _selectedAreaId = defaultAddr['area_id'];
        
        // Fetch full area info including parent for initial load
        final areas = await _supabaseService.getDeliveryAreas();
        final area = areas.firstWhere(
          (a) => a['id'] == _selectedAreaId,
          orElse: () => {},
        );
        
        if (area.isNotEmpty && area['parent_id'] != null) {
          final parent = areas.firstWhere(
            (a) => a['id'] == area['parent_id'],
            orElse: () => {},
          );
          _currentAreaName = parent['name'] ?? "الشعراوية";
          _currentStreetName = area['name'] ?? "مركز البلد";
        } else {
          _currentAreaName = area['name'] ?? "قريبة مني";
          _currentStreetName = defaultAddr['address_line_1'] ?? "مركز البلد";
        }
        
        hasLocation = true;
        
        // Save to in-memory AppState so if user logs out, they stay in this location seamlessly
        _supabaseService.setAppStateFromAuth(defaultAddr);
      }
    }

    // 2. If no Auth address, try Guest location from AppState (Fallback for everyone)
    if (!hasLocation) {
      final guestLoc = await _supabaseService.getGuestLocation();
      if (guestLoc != null) {
        _selectedAreaId = guestLoc['area_id'];
        _currentAreaName = guestLoc['address_line_1'] ?? "موقع مختار";
        _currentStreetName = "موقع زائر";
        hasLocation = true;
      }
    }

    // Always fetch initial promotions
    _promotionsFuture = _supabaseService.getPromotions(areaId: _selectedAreaId).then((ads) {
      if (mounted) {
        setState(() => _currentAds = ads);
        _startAutoScroll();
      }
      return ads;
    });

    // 3. If STILL no location, enforce selection via VendorsMapScreen
    if (!hasLocation) {
      if (_isLocationPickerActive) {
        debugPrint("🏠 [HomeScreen] Location picker already active, skipping push");
        return;
      }

      _isLocationPickerActive = true;
      debugPrint("🏠 [HomeScreen] No location found, pushing VendorsMapScreen...");
      
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const VendorsMapScreen(isSelectionMode: true),
            ),
          );
          
          debugPrint("🏠 [HomeScreen] Returned from VendorsMapScreen. Result: $result");
          _isLocationPickerActive = false;

          if (mounted) {
            if (result == true) {
              // Short delay to allow route transition to finish
              await Future.delayed(const Duration(milliseconds: 200));
              debugPrint("🏠 [HomeScreen] Re-running _loadInitialData after Map return");
              _loadInitialData();
            } else {
              debugPrint("🏠 [HomeScreen] Map returned null or false. Halting loop.");
            }
          }
        } catch (e) {
          debugPrint("❌ [HomeScreen] Navigation error: $e");
          _isLocationPickerActive = false;
        }
      });
    }

    setState(() {
      _selectedType = _currentIndex == 1 ? 'supermarket' : 'restaurant';

      if (_selectedAreaId != null) {
        _vendorsFuture = _supabaseService.getVendors(
          type: _selectedType,
          areaId: _selectedAreaId,
        );
        _homeDataFuture = _supabaseService.getHomeGroupedData(
          _selectedType ?? 'restaurant',
          areaId: _selectedAreaId,
        );
        _promotionsFuture = _supabaseService.getPromotions(
          areaId: _selectedAreaId,
        ).then((ads) {
          if (mounted) {
            setState(() => _currentAds = ads);
            _startAutoScroll();
          }
          return ads;
        });
      } else {
        _vendorsFuture = Future.value([]);
        _homeDataFuture = Future.value([]);
        _promotionsFuture = Future.value([]);
      }
    });
  }

  void _startAutoScroll() {
    if (!mounted || !_isScreenOnTop) return;
    debugPrint("[Banner] _startAutoScroll: current page $_currentPage, ads count ${_currentAds.length}");
    _autoScrollTimer?.cancel();

    if (_currentAds.isNotEmpty && _currentPage < _currentAds.length) {
      if (_currentAds[_currentPage].isVideo) {
        debugPrint("[Banner] Skipping timer: current banner is video");
        return;
      }
    }

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (
      timer,
    ) {
      debugPrint("[Banner] Timer triggered auto-advance");
      _goToNextBanner();
    });
  }


  void _goToNextBanner() {
    if (!mounted || !_isScreenOnTop || _currentAds.length <= 1) return;

    int nextPage = (_currentPage + 1) % _currentAds.length;
    debugPrint("[Banner] Advancing to page $nextPage");
    
    // Set state immediately to notify potential video players to stop/pause
    setState(() => _currentPage = nextPage);

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutQuart,
      );
    }
  }


  void _handlePageChange(int index) {
    debugPrint("[Banner] Page changed to $index");
    if (_currentAds.isEmpty || index >= _currentAds.length) return;

    final currentAd = _currentAds[index];
    if (currentAd.isVideo) {
      debugPrint("[Banner] Target is video, stopping auto-scroll timer");
      _autoScrollTimer?.cancel();
    } else {
      debugPrint("[Banner] Target is image, restarting auto-scroll timer");
      _startAutoScroll();
    }
  }



  Future<bool> _checkLogin() async {
    if (_supabaseService.client.auth.currentSession == null) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (result == true && mounted) {
        _loadInitialData();
      }
      return false;
    }
    return true;
  }

  void _onTabTapped(int index) async {
    // Protected Tabs: Cart (2), Orders (3), Profile (4)
    if (index >= 2) {
      bool isLoggedIn = await _checkLogin();
      if (!isLoggedIn) return;
    }

    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CartScreen()),
      );
      return;
    }
    setState(() {
      _currentIndex = index;
      _selectedCategoryId = null;
      if (index == 0) {
        _selectedType = 'restaurant';
        _selectedCategoryName = "قريب منك";
      } else if (index == 1) {
        _selectedType = 'supermarket';
        _selectedCategoryName = "سوبر ماركت";
      }

      _vendorsFuture = _supabaseService.getVendors(
        type: _selectedType,
        categoryId: _selectedCategoryId,
        areaId: _selectedAreaId,
      );

      _homeDataFuture = _supabaseService.getHomeGroupedData(
        _selectedType ?? 'restaurant',
        areaId: _selectedAreaId,
      );
    });
  }

  void _filterVendors(String? type, String name, String? id, {bool scrollDown = false}) {
    setState(() {
      if (_selectedCategoryId == id) {
        // De-selecting: Back to tab defaults
        _selectedType = _currentIndex == 1 ? 'supermarket' : 'restaurant';
        _selectedCategoryId = null;
        _selectedCategoryName = "قريب منك";
      } else {
        // Selecting: Specific category
        _selectedType = type;
        _selectedCategoryId = id;
        _selectedCategoryName = name;
      }
      _vendorsFuture = _supabaseService.getVendors(
        type: _selectedType,
        categoryId: _selectedCategoryId,
        areaId: _selectedAreaId,
      );
    });

    if (scrollDown && _scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollController.animateTo(
          400, // Approximate height to clear banners/header
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      drawer: _buildDrawer(),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _buildSupportButton(),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.startFloat, // RTL Support
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadInitialData();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent(); // Restaurants
      case 1:
        return _buildHomeContent(); // Market (could be filtered)
      case 3:
        return const OrdersListScreen();
      case 4:
        return const ProfileScreen();
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildAdminBypassBanner() {
    if (!_isAdminMode || (!_isAppClosed && !_isUnderMaintenance)) {
      return const SliverToBoxAdapter(child: SizedBox());
    }

    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.orange[800],
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.admin_panel_settings,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isUnderMaintenance
                    ? "وضع الإدارة: التطبيق تحت الصيانة (مخفي عن العامة)"
                    : "وضع الإدارة: التطبيق مغلق حالياً (مخفي عن العامة)",
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return SafeArea(
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildAdminBypassBanner(),
          _buildAppBar(),
          _buildSearchBarSection(),
          _buildPromoSlider(),
          _buildCategoryGrid(),
          if (_selectedCategoryId == null) ...[
            _buildDynamicSections(),
          ] else ...[
            _buildSectionHeader(_selectedCategoryName),
            _buildVendorList(),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ],
      ),
    );
  }

  Widget _buildDynamicSections() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _homeDataFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const SliverToBoxAdapter(child: SizedBox());
        if (!snapshot.hasData)
          return const SliverToBoxAdapter(child: SizedBox());
        final categories = snapshot.data!;

        return SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final cat = categories[index];
            return _buildCategorySection(
              cat['name'],
              cat['id'],
              cat['vendors'] as List<Vendor>,
            );
          }, childCount: categories.length),
        );
      },
    );
  }

  Widget _buildCategorySection(String title, String id, List<Vendor> items) {
    if (items.isEmpty) return const SizedBox(); // Hide if no vendors found

    final displayItems = items.take(AppConfig.homeHorizontalLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () => _filterVendors(_selectedType, title, id),
                child: Text(
                  "عرض الكل",
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 235, // Adjusted for updated card dimensions
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final vendor = displayItems[index];
              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () =>
                      VendorNavigation.navigateToVendor(context, vendor),
                  child: VendorCard(vendor: vendor, isGrid: true),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(),
          _drawerItem(
            Icons.home_outlined,
            "الرئيسية",
            () => Navigator.pop(context),
          ),
          _drawerItem(Icons.person_outline, "الملف الشخصي", () {
            Navigator.pop(context);
            _onTabTapped(4);
          }),
          _drawerItem(Icons.receipt_long_outlined, "طلباتي", () {
            Navigator.pop(context);
            _onTabTapped(3);
          }),
          _drawerItem(Icons.location_on_outlined, "عناويني", () {
            Navigator.pop(context);
            _showAddressPicker();
          }),
          _drawerItem(Icons.emoji_events_outlined, "أوسمة الأفضل", () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LeaderboardScreen(areaId: _selectedAreaId),
              ),
            );
          }),
          _drawerItem(Icons.favorite_border, "المفضلة", () async {
            Navigator.pop(context);
            if (await _checkLogin()) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FavoriteVendorsScreen(),
                ),
              );
            }
          }),
          if (_isFullAdmin)
            _drawerItem(Icons.bug_report_outlined, "سجلات النظام (Logs)", () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogsScreen()),
              );
            }),
          _drawerItem(Icons.share_outlined, "شاركه مع أصدقائك", () async {
            Navigator.pop(context);
            if (_storeUrl != null) {
              await Share.share(
                "اكتشف تطبيق طلبك! أسهل طريقة لطلب احتياجاتك في فلسطين.\nحمّل التطبيق الآن:\n$_storeUrl",
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("رابط التطبيق غير متوفر حالياً")),
              );
            }
          }),
          const Divider(),
          _drawerItem(Icons.info_outline, "عن طلبك", () {
            Navigator.pop(context);
            _showAboutDialog();
          }),
          _drawerItem(Icons.settings_outlined, "الإعدادات", () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          }),
          const Divider(),
          if (_supabaseService.client.auth.currentUser == null)
            _drawerItem(Icons.login, "تسجيل الدخول", () async {
              Navigator.pop(context);
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              if (result == true && mounted) {
                _loadInitialData();
              }
            })
          else
            _drawerItem(Icons.logout, "تسجيل الخروج", () async {
              await _supabaseService.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
            }),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    final user = _supabaseService.client.auth.currentUser;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40), // Leaves a white gap on both the left and right sides
      padding: const EdgeInsets.only(top: 60, bottom: 30, left: 20, right: 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white,
            child: Icon(Icons.person, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            user?.userMetadata?['full_name'] ??
                (user == null ? "زائر طلبك" : "مستخدم طلبك"),
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (user != null)
            Text(
              user.email ?? "",
              style: GoogleFonts.cairo(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: onTap,
    );
  }

  Widget _buildSupportButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isSupportExpanded) ...[
          // WhatsApp Option
          _buildSupportSubButton(
            icon: Icons.chat_bubble_outline,
            label: "واتساب",
            color: Colors.green,
            onTap: _launchWhatsApp,
          ),
          const SizedBox(height: 12),
          // In-App Chat Option (With Glow)
          _buildSupportSubButton(
            icon: Icons.headset_mic_outlined,
            label: "محادثة مباشرة",
            color: AppColors.primary,
            onTap: _openInAppChat,
            hasGlow: true,
          ),
          const SizedBox(height: 12),
        ],
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(AppColors.glowIntensity),
                    blurRadius: 10,
                    spreadRadius: 3,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: () =>
                    setState(() => _isSupportExpanded = !_isSupportExpanded),
                backgroundColor: AppColors.primary,
                elevation: 4,
                shape: const CircleBorder(),
                child: AnimatedRotation(
                  duration: const Duration(milliseconds: 300),
                  turns: _isSupportExpanded ? 0.125 : 0, // 45 degrees rotation
                  child: Icon(
                    _isSupportExpanded ? Icons.add : Icons.headset_mic_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
            if (_unreadCount > 0 && !_isSupportExpanded)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 12,
                    minHeight: 12,
                  ),
                  child: Text(
                    '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupportSubButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool hasGlow = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: hasGlow
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(AppColors.glowIntensity),
                      blurRadius: 10,
                      spreadRadius: 3,
                    ),
                  ],
                )
              : null,
          child: FloatingActionButton.small(
            heroTag: label,
            onPressed: onTap,
            backgroundColor: color,
            shape: const CircleBorder(),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Future<void> _launchWhatsApp() async {
    try {
      String rawData = await _supabaseService.getSupportWhatsApp();
      Uri url;

      if (rawData.startsWith('http://') || rawData.startsWith('https://')) {
        // If it's already a full link (wa.me or other)
        url = Uri.parse(rawData);
      } else {
        // If it's just a number, clean it and format it
        String cleanNumber = rawData.replaceAll(RegExp(r'[^0-9]'), '');
        url = Uri.parse("https://wa.me/$cleanNumber");
      }

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // Fallback for cases where wa.me might fail in some browsers/OS
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint("❌ Error launching WhatsApp: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("عذراً، لا يمكن فتح واتساب حالياً")),
        );
      }
    }
  }

  void _openInAppChat() async {
    final user = _supabaseService.client.auth.currentUser;
    if (user == null) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (result == true && mounted) {
        _loadInitialData();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatSupportScreen()),
        );
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatSupportScreen()),
      );
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "عن طلبك",
          textAlign: TextAlign.right,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "طلبك - تطبيق التوصيل الأول في منطقتك",
              textAlign: TextAlign.right,
              style: GoogleFonts.cairo(),
            ),
            const SizedBox(height: 12),
            FutureBuilder<String>(
              future: Provider.of<SupabaseService>(context, listen: false).getAppVersion(),
              builder: (context, snapshot) {
                final version = snapshot.data ?? '1.0.0';
                return Text(
                  "الإصدار: $version",
                  textAlign: TextAlign.right,
                  style: GoogleFonts.cairo(),
                );
              },
            ),
            const SizedBox(height: 24),
            SocialMediaRow(
              facebookUrl: _facebookUrl,
              instagramUrl: _instagramUrl,
              whatsappUrl: _whatsappUrl,
            ),
          ],
        ),


        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "إغلاق",
              style: GoogleFonts.cairo(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, size: 28),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showAddressPicker(isMandatory: false),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.expand_more,
                            size: 20,
                            color: Colors.grey,
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _currentAreaName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  _currentStreetName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final shouldRefresh = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            VendorsMapScreen(areaId: _selectedAreaId),
                      ),
                    );
                    if (shouldRefresh == true && mounted) {
                      _loadInitialData();
                    }
                  },
                  icon: Icon(
                    Icons.map_outlined,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoSlider() {
    return SliverToBoxAdapter(
      child: FutureBuilder<List<PromotionBanner>>(
        future: _promotionsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            // Fallback to static if no ads found
            return _buildStaticPlaceholder();
          }
          final ads = snapshot.data!;


          return Column(
            children: [
              SizedBox(
                height: 220,
                width: double.infinity,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: ads.length,

                  itemBuilder: (context, index) {
                    final ad = ads[index];
                    return GestureDetector(
                      onTap: () => _handleBannerClick(ad),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: MediaBanner(
                          key: ValueKey(ad.id),
                          ad: ad,
                          isActive: _isScreenOnTop && _currentPage == index,
                          onVideoEnd: _goToNextBanner,
                        ),



                      ),

                    );
                  },
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                    _handlePageChange(index);
                  },
                ),
              ),
              const SizedBox(height: 6),
              _buildDotsIndicator(ads.length),
              const SizedBox(height: 4),
            ],

          );
        },
      ),
    );
  }

  Widget _buildDotsIndicator(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: _currentPage == index ? 24 : 8,
          decoration: BoxDecoration(
            color: _currentPage == index ? AppColors.primary : Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _buildStaticPlaceholder() {
    return Container(
      height: 220,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: const DecorationImage(
          image: NetworkImage(
            'https://images.unsplash.com/photo-1549488344-1f9b8d2bd1f3?auto=format&fit=crop&q=80&w=1000',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.4), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            Text(
              "ادعوا الأصدقاء واربحوا!",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "خدمة جديدة في طلبك",
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 8),
            child: Text(
              _homeGreeting,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _homeDataFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const SizedBox();
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 140,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              var cats = snapshot.data ?? [];

              if (cats.isEmpty) {
                cats = [
                  {
                    'name': 'ترند طلبك',
                    'image_url':
                        'https://cdn-icons-png.flaticon.com/512/737/737967.png',
                    'vendor_type': 'restaurant',
                  },
                  {
                    'name': 'كتب وقرطاسيات',
                    'image_url':
                        'https://cdn-icons-png.flaticon.com/512/3389/3389081.png',
                    'vendor_type': 'retail',
                  },
                  {
                    'name': 'صيدليات',
                    'image_url':
                        'https://cdn-icons-png.flaticon.com/512/3024/3024844.png',
                    'vendor_type': 'pharmacy',
                  },
                  {
                    'name': 'ديكور المنزل',
                    'image_url':
                        'https://cdn-icons-png.flaticon.com/512/2163/2163350.png',
                    'vendor_type': 'retail',
                  },
                ];
              }

              return SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: cats.length,
                  itemBuilder: (context, index) {
                    final cat = cats[index];
                    final String catId = cat['id']?.toString() ?? cat['name'];
                    final bool isActive = _selectedCategoryId == catId;

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        onTap: () =>
                            _filterVendors(_selectedType, cat['name'], catId),
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isActive
                                    ? AppColors.primary.withOpacity(0.1)
                                    : Colors.black.withOpacity(0.04),
                                blurRadius: isActive ? 15 : 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.network(
                                  cat['image_url'] ?? '',
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.contain,
                                  errorBuilder: (c, e, s) => const Icon(
                                    Icons.category,
                                    size: 30,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                cat['name'],
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight:
                                      isActive ? FontWeight.bold : FontWeight.normal,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddressPicker({bool isMandatory = false}) {
    showModalBottomSheet(
      context: context,
      isDismissible: !isMandatory,
      enableDrag: !isMandatory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return WillPopScope(
          onWillPop: () async => !isMandatory,
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Center(
                  child: Text(
                    "اختر عنوان التوصيل",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 24),

                // Option 1: Current Location (GPS)
                _addressOption(
                  icon: Icons.my_location,
                  title: "موقعي الحالي",
                  subtitle: "تحديد موقعي التلقائي عبر GPS",
                  onTap: () async {
                    Navigator.pop(sheetContext); // Close the bottom sheet!
                    debugPrint("🏠 [HomeScreen] Pushed GPS AddressSelectionScreen");
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddressSelectionScreen(
                          mode: AddressSelectionMode.gps,
                        ),
                      ),
                    );
                    debugPrint("🏠 [HomeScreen] GPS Result: $result");
                    if (result == true && mounted) {
                      _loadInitialData();
                    } else if (result == false && mounted) {
                      final mapResult = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VendorsMapScreen(isSelectionMode: true),
                        ),
                      );
                      if (mapResult == true && mounted) {
                        _loadInitialData();
                      }
                    }
                  },
                ),

                // Option 2: Explore Areas (City List)
                _addressOption(
                  icon: Icons.explore_outlined,
                  title: "استكشف مناطق خدماتنا",
                  subtitle: "اختر من قائمة المدن والقرى المتاحة",
                  onTap: () async {
                    Navigator.pop(sheetContext); // Close the bottom sheet!
                    debugPrint("🏠 [HomeScreen] Pushed List AddressSelectionScreen");
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddressSelectionScreen(
                          mode: AddressSelectionMode.list,
                        ),
                      ),
                    );
                    debugPrint("🏠 [HomeScreen] List Result: $result");
                    if (result == true && mounted) {
                      _loadInitialData();
                    }
                  },
                ),

                const Divider(height: 32),

                // Option 3: Manual Add
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(sheetContext); // Close the bottom sheet!
                    debugPrint("🏠 [HomeScreen] Pushed AddressDetailsScreen");
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddressDetailsScreen(),
                      ),
                    );
                    debugPrint("🏠 [HomeScreen] Manual Details Result: $result");
                    _loadInitialData(); // Refresh home state on return
                  },
                  child: const Text(
                    "إضافة موقع جديد ويدوي",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      // Ensure we re-enforce if mandatory and no location selected
      if (isMandatory) {
        // Double check if location was actually selected
        final user = _supabaseService.client.auth.currentUser;
        if (user == null && _selectedAreaId == null) {
          // For simple enforcement, we can just show it again or do nothing if
          // we assume the user can't close it anyway.
          // Since isDismissible is false, whenComplete only fires if pop() is called programmatically
          // or if the cheat gesture works.
          // Ideally we check here if we have a location now.
          if (_selectedAreaId == null) {
            // _showAddressPicker(isMandatory: true); // Potential loop if not careful
          }
        }
      }
    });
  }

  Widget _addressOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildVendorList() {
    final double width = MediaQuery.of(context).size.width;
    final int crossAxisCount =
        width > 1200 ? 5 : (width > 900 ? 4 : (width > 600 ? 3 : 2));

    return FutureBuilder<List<Vendor>>(
      future: _vendorsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: Center(child: Text("Error: ${snapshot.error}")),
          );
        }
        final vendors = snapshot.data ?? [];
        if (vendors.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.store_mall_directory_outlined,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "سيتوفر قريباً",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "نحن نعمل على إضافة متاجر جديدة في هذا القسم",
                    style: TextStyle(color: Colors.grey[600], fontSize: 15),
                  ),
                ],
              ),
            ),
          );
        }

        // Calculate aspect ratio to maintain exactly 235px height (updated for larger card layout)
        final double cardWidth = (width - 32 - (crossAxisCount - 1) * 16) / crossAxisCount;
        final double aspectRatio = cardWidth / 235;

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: aspectRatio,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final vendor = vendors[index];
              return InkWell(
                onTap: () => VendorNavigation.navigateToVendor(context, vendor),
                child: VendorCard(vendor: vendor, isGrid: true),
              );
            }, childCount: vendors.length),
          ),
        );
      },
    );
  }

  Widget _buildSearchBarSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GlobalSearchScreen(areaId: _selectedAreaId),
              ),
            );
          },
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    "عن ماذا تبحث اليوم؟",
                    textAlign: TextAlign.right,
                    style: GoogleFonts.cairo(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.search, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.restaurant_outlined, Icons.restaurant, "مطاعم"),
            _buildNavItem(1, Icons.shopping_basket_outlined, Icons.shopping_basket, "ماركت"),
            _buildCartItem(),
            _buildNavItem(3, Icons.receipt_long_outlined, Icons.receipt_long, "طلباتي"),
            _buildNavItem(4, Icons.person_outline, Icons.person, "صفحتي"),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    bool isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => _onTabTapped(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppColors.primary : Colors.grey[400],
              size: 24,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.primary : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem() {
    return InkWell(
      onTap: () => _onTabTapped(2),
      child: Transform.translate(
        offset: const Offset(0, -15),
        child: Container(
          width: 55,
          height: 55,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryRed,
                AppColors.primaryRed,
                AppColors.secondaryPurple.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.shopping_cart_outlined,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  Future<void> _handleBannerClick(PromotionBanner ad) async {
    final dealUrl = ad.dealUrl?.trim() ?? "";
    if (dealUrl.isEmpty) return;
    
    // Better parsing for 'type:value'
    String type = 'vendor';
    String value = dealUrl;

    if (dealUrl.contains(':')) {
      final parts = dealUrl.split(':');
      type = parts[0].toLowerCase();
      // Combine the rest in case the value itself contains colons (like a URL)
      value = parts.sublist(1).join(':').trim();
    }

    try {
      if (type == 'game') {
        // If value is empty, it opens the games hub (GameLaunchScreen)
        // If value has a slug (e.g., game:fast-delivery), it could potentially pass it
        Navigator.push(
          context, 
          MaterialPageRoute(
            builder: (_) => GameLaunchScreen(initialGameSlug: value.isEmpty ? null : value)
          )
        );
      } else if (type == 'category' || type == 'global_category') {
        final categories = await _supabaseService.getGlobalCategories();
        final targetCat = categories.firstWhere(
          (c) => c['id']?.toString() == value,
          orElse: () => {},
        );
        if (targetCat.isNotEmpty && mounted) {
          _filterVendors(targetCat['vendor_type'], targetCat['name'], targetCat['id'], scrollDown: true);
        }
      } else if (type == 'product') {
        final productRes = await _supabaseService.client
            .from('products')
            .select('*, vendors(*)')
            .eq('id', value)
            .maybeSingle();
        
        if (productRes != null) {
          final vendor = Vendor.fromJson(productRes['vendors']);
          
          if (mounted) {
            await VendorNavigation.navigateToVendor(
              context, 
              vendor, 
              initialProductId: value,
            );
          }
        }
      } else if (type == 'url' || type == 'web') {
        final uri = Uri.parse(value.startsWith('http') ? value : 'https://$value');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        // Default: Vendor
        String vendorId = value;
        String? initialCategoryId;

        if (vendorId.contains('#')) {
          final subParts = vendorId.split('#');
          vendorId = subParts[0].trim();
          initialCategoryId = subParts[1].trim();
        }

        final vendor = await _supabaseService.getVendorById(vendorId);
        if (vendor != null && mounted) {
          VendorNavigation.navigateToVendor(
            context,
            vendor,
            initialCategoryId: initialCategoryId,
          );
        }
      }
    } catch (e) {
      debugPrint("Error handling banner click: $e");
    }
  }
}

class VendorCardMock extends StatelessWidget {
  const VendorCardMock({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: Image.network(
                'https://as1.ftcdn.net/v2/jpg/02/75/39/23/1000_F_275392381_9up6qY5qS0OnVIdT97zT6ZIn7Xp9InS9.jpg',
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  "مطعم شاورما الفوال",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "⭐ 4.8 (200+)",
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      "5 ₪",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
