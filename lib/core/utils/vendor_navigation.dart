import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart'; // Ensure this is added to pubspec
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../models/models.dart';
import '../../ui/screens/webview_screen.dart';
import '../../ui/screens/vendor_detail_screen.dart';
import '../../ui/screens/market_detail_screen.dart';

class VendorNavigation {
  static Future<void> navigateToVendor(
    BuildContext context,
    Vendor vendor, {
    String? initialCategoryId,
    String? initialProductId,
  }) async {
    // Diagnostic SnackBar (Temporary to verify data flow)
    debugPrint(
      "🚀 [VendorNavigation] Navigating to: ${vendor.name} (isWeb: ${vendor.isExternalWeb})",
    );

    if (!vendor.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("المتجر مغلق حالياً، نعتذر عن استقبال الطلبات"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (vendor.isExternalWeb &&
        vendor.websiteUrl != null &&
        vendor.websiteUrl!.isNotEmpty) {
      String rawUrl = vendor.websiteUrl!.trim();
      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
        rawUrl = 'https://$rawUrl';
      }

      debugPrint("🌐 [VendorNavigation] Opening WebView for: $rawUrl");

      // Check if platform supports WebView (Android/iOS)
      bool useExternalBrowser =
          kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

      if (useExternalBrowser) {
        final uri = Uri.parse(rawUrl);
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint(
            "❌ [VendorNavigation] Failed to launch external browser: $e",
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("تعذر فتح الرابط في المتصفح: $e")),
            );
          }
        }
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WebViewScreen(url: rawUrl, title: vendor.name),
          ),
        );
        // Refresh Cart on Return
        if (context.mounted) {
          debugPrint(
            "🔄 [VendorNavigation] Returned from WebView, refreshing cart...",
          );
          Provider.of<CartProvider>(context, listen: false).loadFromSupabase();
        }
      }
      return;
    }

    // If it reaches here, it either wasn't external web or had no URL
    debugPrint(
      "🏡 [VendorNavigation] Native Detail Screen: isWeb=${vendor.isExternalWeb}, URL=${vendor.websiteUrl}",
    );

    // If it's supposed to be web but URL is missing, show a prominent alert
    if (vendor.isExternalWeb &&
        (vendor.websiteUrl == null || vendor.websiteUrl!.isEmpty)) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("رابط المتجر مفقود"),
            content: Text(
              "هذا المتجر (${vendor.name}) مفعل كمتجر ويب خارجي ولكن لم يتم إضافة رابط الموقع في لوحة التحكم.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text("إغلاق"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => vendor.type == 'supermarket'
                          ? MarketDetailScreen(
                              vendor: vendor,
                              initialProductId: initialProductId,
                            )
                          : VendorDetailScreen(
                              vendor: vendor,
                              initialCategoryId: initialCategoryId,
                              initialProductId: initialProductId,
                            ),
                    ),
                  );
                },
                child: const Text("فتح كنظام داخلي"),
              ),
            ],
          ),
        );
      }
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => vendor.type == 'supermarket'
            ? MarketDetailScreen(
                vendor: vendor,
                initialProductId: initialProductId,
              )
            : VendorDetailScreen(
                vendor: vendor,
                initialCategoryId: initialCategoryId,
                initialProductId: initialProductId,
              ),
      ),
    );
  }
}
