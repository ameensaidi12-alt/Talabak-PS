import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../utils/vendor_navigation.dart';
import '../../ui/screens/vendor_detail_screen.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart'; // Import navigatorKey
import '../../ui/screens/single_game_launch_screen.dart';

class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _lastHandledVendorId;
  DateTime? _lastHandleTime;
  bool _initialLinkHandled = false;

  void initialize() {
    // Handle link when app is in background or closed (Cold Start)
    _appLinks.getInitialLink().then((uri) async {
      if (uri != null && !_initialLinkHandled) {
        _initialLinkHandled = true; // Mark early to prevent double-await issues
        // Essential: wait for initial screen (HomeScreen) to be ready
        await Future.delayed(const Duration(milliseconds: 2000));
        handleUri(uri);
      }
    });

    // Handle link when app is running (Warm start / Stream)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _initialLinkHandled = true; // Mark as handled so initial link ignores it
      handleUri(uri);
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  void handleUri(Uri uri) {
    debugPrint('Incoming Deep Link: $uri');
    
    // Check if it's a shop link
    if (uri.path.contains('shop') || uri.host == 'shop') {
      final vendorId = uri.queryParameters['id']?.trim();
      if (vendorId != null && vendorId.isNotEmpty && vendorId != 'null') {
        // Deduplication Logic:
        // Ignore if it's the same ID within the last 5 seconds (to cover Splash + Home transition)
        final now = DateTime.now();
        if (_lastHandledVendorId == vendorId && 
            _lastHandleTime != null && 
            now.difference(_lastHandleTime!) < const Duration(seconds: 5)) {
          debugPrint('Duplicate deep link detected for vendor: $vendorId. Ignoring.');
          return;
        }

        _lastHandledVendorId = vendorId;
        _lastHandleTime = now;
        _navigateToVendor(vendorId);
      }
    }

    // Check if it's a game link
    if (uri.path.contains('game') || uri.host == 'game') {
      final slug = uri.queryParameters['slug']?.trim();
      if (slug != null && slug.isNotEmpty) {
        _navigateToGame(slug);
      }
    }
  }

  Future<void> _navigateToGame(String slug) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final supabaseService = Provider.of<SupabaseService>(context, listen: false);

    try {
      final gameData = await supabaseService.getGameSettings(slug);
      if (gameData != null) {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SingleGameLaunchScreen(gameData: gameData),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to game via deep link: $e');
    }
  }

  Future<void> _navigateToVendor(String vendorId) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final supabaseService = Provider.of<SupabaseService>(context, listen: false);

    try {
      // 1. Fetch vendor data
      final vendor = await supabaseService.getVendorById(vendorId);
      
      // 2. Area Validation
      final userAreaId = await supabaseService.getGuestLocation();
      
      // If user has a selected area, and vendor belongs to a different area
      if (userAreaId != null && vendor.areaId != null && vendor.areaId != userAreaId['area_id']) {
        if (navigatorKey.currentContext != null) {
          _showAreaConflictDialog(navigatorKey.currentContext!, vendor);
        }
        return;
      }

      // 3. Navigate using the central navigation utility
      await VendorNavigation.navigateToVendor(context, vendor);
    } catch (e) {
      debugPrint('Error handling deep link vendor: $e');
      if (navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(
            content: Text(
              "عذراً، لم نتمكن من العثور على هذا المتجر",
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAreaConflictDialog(BuildContext context, Vendor vendor) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "متجر في منطقة أخرى",
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined, size: 60, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              "هذا المتجر (${vendor.name}) يقع في منطقة (${vendor.areaName ?? 'أخرى'}).\n\nهل تريد تحويل منطقتك الحالية لتتمكن من الطلب منه؟",
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    "إلغاء",
                    style: GoogleFonts.cairo(color: Colors.grey),
                  ),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    // Close dialog
                    Navigator.pop(dialogContext);
                    
                    // Switch area logic
                    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
                    await supabaseService.saveGuestLocation(
                      vendor.areaId!,
                      vendor.areaName ?? 'منطقة المتجر',
                      vendor.latitude ?? 32.2211,
                      vendor.longitude ?? 35.2544,
                    );
                    
                    // Proceed to navigate
                    if (context.mounted) {
                      await VendorNavigation.navigateToVendor(context, vendor);
                    }
                  },
                  child: Text(
                    "تحويل وفتح",
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
