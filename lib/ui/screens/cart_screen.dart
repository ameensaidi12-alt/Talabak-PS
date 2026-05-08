import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/services/supabase_service.dart';
import 'orders_list_screen.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/models.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isSheetOpen = false; // Guard against double-tap opening sheet twice
  double? _cachedDeliveryFee;
  String? _lastCartIds;

  Future<double> _calculateVendorDeliveryFee(Vendor v, double subtotal) async {
    if (v.isFreeDelivery) return 0.0;
    
    // Check for free delivery threshold
    if (v.freeDeliveryThreshold != null && v.freeDeliveryThreshold! > 0) {
      if (subtotal >= v.freeDeliveryThreshold!) {
        return 0.0;
      }
    }

    // Determine base fee
    if (v.useCustomDelivery) {
      return (v.customDeliveryFee ?? v.deliveryFee).toDouble();
    } else {
      final supabaseService = SupabaseService();
      return await supabaseService.getEffectiveDeliveryFee(
        v.areaId,
        v.deliveryFee,
      );
    }
  }

  Future<double> _getDeliveryTotal(CartProvider cart) async {
    final currentIds = cart.items.map((i) => "${i.id ?? i.product.id}_${i.quantity}").join(',');
    if (_lastCartIds == currentIds && _cachedDeliveryFee != null) {
      return _cachedDeliveryFee!;
    }

    try {
      final supabaseService = SupabaseService();
      double totalDeliveryFee = 0;
      final itemsByVendor = cart.itemsByVendor;
      for (String vendorId in itemsByVendor.keys) {
        final v = await supabaseService.getVendorById(vendorId);
        final vendorItems = itemsByVendor[vendorId]!;
        final subtotal = vendorItems.fold(0.0, (sum, item) => sum + item.totalPrice);
        
        final fee = await _calculateVendorDeliveryFee(v, subtotal);
        totalDeliveryFee += fee;
      }
      _lastCartIds = currentIds;
      _cachedDeliveryFee = totalDeliveryFee;
      return totalDeliveryFee;
    } catch (e) {
      return 0.0;
    }
  }

  void _showCheckoutSheet(BuildContext mainContext, CartProvider cart) async {
    // Prevent double-tap from opening the sheet twice
    if (_isSheetOpen) return;
    setState(() => _isSheetOpen = true);

    final supabaseService = SupabaseService();
    UserProfile? profile = await supabaseService.getUserProfile();
    String? phone = profile?.phone;
    final phoneController = TextEditingController(text: phone);
    final notesController = TextEditingController();
    bool isSubmitting = false;
    int redeemedPoints = 0;
    double pointsDiscount = 0.0;

    final redeemRateStr =
        await supabaseService.getAppSetting('star_points_redeem_rate');
    final double redeemRate = double.tryParse(redeemRateStr ?? '10') ?? 10.0;

    final spendingEnabledStr = await supabaseService.getAppSetting('is_stars_discount_enabled');
    final bool isSpendingEnabled = spendingEnabledStr != 'false'; // Defaults to true

    final minRedeemStr =
        await supabaseService.getAppSetting('star_points_min_redeem');
    final int minRedeem = int.tryParse(minRedeemStr ?? '50') ?? 50;

    // Calculate total possible delivery fee to allow discount to cover it
    double totalDeliveryFee = 0;
    final itemsByVendor = cart.itemsByVendor;
    for (String vendorId in itemsByVendor.keys) {
      final v = await supabaseService.getVendorById(vendorId);
      final vendorItems = itemsByVendor[vendorId]!;
      final subtotal = vendorItems.fold(0.0, (sum, item) => sum + item.totalPrice);
      
      final fee = await _calculateVendorDeliveryFee(v, subtotal);
      totalDeliveryFee += fee;
    }
    final double maxPossibleDiscount = cart.totalPrice + totalDeliveryFee;

    if (mainContext.mounted) {
      showModalBottomSheet(
        context: mainContext,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 30,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 25),
                Text(
                  "تأكيد رقم الهاتف",
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "يرجى التأكد من رقم هاتفك للتواصل معك بخصوص الطلب",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(color: Colors.grey[600]),
                ),
                const SizedBox(height: 25),
                TextField(
                  controller: phoneController,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.phone,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    hintText: "رقم الهاتف",
                    hintStyle: GoogleFonts.cairo(),
                    prefixIcon: Icon(
                      Icons.phone,
                      color: AppColors.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                if (profile != null && profile.starPoints > 0 && isSpendingEnabled) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${profile.starPoints}",
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              "نقاط النجوم المتاحة",
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        if (profile.starPoints < minRedeem)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 16, color: Colors.orange),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "تحتاج على الأقل $minRedeem نقطة لتتمكن من الاستبدال",
                                    style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: Colors.orange[800],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Switch(
                                value: redeemedPoints > 0,
                                activeColor: AppColors.primary,
                                onChanged: (val) {
                                  setSheetState(() {
                                    if (val) {
                                      redeemedPoints = profile.starPoints;
                                      pointsDiscount =
                                          redeemedPoints / redeemRate;
                                      // Don't discount more than total (including delivery)
                                      if (pointsDiscount > maxPossibleDiscount) {
                                        pointsDiscount = maxPossibleDiscount;
                                        redeemedPoints =
                                            (pointsDiscount * redeemRate)
                                                .toInt();
                                      }
                                    } else {
                                      redeemedPoints = 0;
                                      pointsDiscount = 0.0;
                                    }
                                  });
                                },
                              ),
                              Text(
                                "استخدام النقاط للخصم",
                                style: GoogleFonts.cairo(),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 25),
                // Price Breakdown Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      _buildBreakdownRow("مجموع المنتجات", "${cart.totalPrice.toStringAsFixed(cart.totalPrice % 1 == 0 ? 0 : 2)} ₪"),
                      const SizedBox(height: 10),
                        _buildBreakdownRow(
                          "رسوم التوصيل", 
                          totalDeliveryFee == 0 ? "عرض توصيل مجاني ✨" : "${totalDeliveryFee.toStringAsFixed(totalDeliveryFee % 1 == 0 ? 0 : 2)} ₪",
                          valueColor: totalDeliveryFee == 0 ? const Color(0xFF8B5CF6) : null,
                        ),
                      if (pointsDiscount > 0) ...[
                        const SizedBox(height: 10),
                        _buildBreakdownRow(
                          "خصم النقاط", 
                          "- ${pointsDiscount.toStringAsFixed(pointsDiscount % 1 == 0 ? 0 : 2)} ₪",
                          valueColor: Colors.green[700],
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(),
                      ),
                      _buildBreakdownRow(
                        "المجموع النهائي", 
                        "${(cart.totalPrice + totalDeliveryFee - pointsDiscount).toStringAsFixed((cart.totalPrice + totalDeliveryFee - pointsDiscount) % 1 == 0 ? 0 : 2)} ₪",
                        isBold: true,
                        fontSize: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  width: double.infinity,
                  height: 55,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (phoneController.text.isEmpty) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "يرجى إدخال رقم الهاتف",
                                      style: GoogleFonts.cairo(),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                              return;
                            }

                            setSheetState(() => isSubmitting = true);

                            // Update phone if changed
                            if (phoneController.text != phone) {
                              try {
                                await supabaseService.updateUserPhone(
                                  phoneController.text,
                                );
                              } on AuthException catch (e) {
                                setSheetState(() => isSubmitting = false);
                                if (e.message.contains(
                                      "already been registered",
                                    ) ||
                                    e.code == 'phone_exists') {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "رقم الهاتف هذا مسجل مسبقاً لحساب آخر",
                                          style: GoogleFonts.cairo(),
                                          textAlign: TextAlign.right,
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                  return; // Stop checkout if phone update fails due to conflict
                                }
                                debugPrint("Auth Error updating phone: $e");
                                return;
                              } catch (e) {
                                setSheetState(() => isSubmitting = false);
                                debugPrint("Error updating phone: $e");
                                return;
                              }
                            }

                            if (mainContext.mounted) {
                              Navigator.pop(sheetContext); // Close sheet
                              _processCheckout(
                                mainContext,
                                cart,
                                totalRedeemedPoints: redeemedPoints,
                                totalPointsDiscount: pointsDiscount,
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            "تأكيد وإرسال الطلب",
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).whenComplete(() {
        // Reset flag when sheet is closed by any means (swipe, dismiss, button)
        if (mounted) setState(() => _isSheetOpen = false);
      });
    }
  }

  Future<void> _processCheckout(
    BuildContext context,
    CartProvider cart, {
    int totalRedeemedPoints = 0,
    double totalPointsDiscount = 0,
  }) async {
    final supabaseService = SupabaseService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final itemsByVendor = cart.itemsByVendor;
      final String? batchId =
          itemsByVendor.length > 1 ? const Uuid().v4() : null;

      // Fetch current location info to provide better address to partner
      final guestLoc = await supabaseService.getGuestLocation();
      final String? currentAreaId = guestLoc?['area_id'];
      String areaPrefix = "";
      if (guestLoc != null && guestLoc['address_line_1'] != null) {
        areaPrefix = "${guestLoc['address_line_1']} - ";
      }

      int remainingPoints = totalRedeemedPoints;
      double remainingDiscount = totalPointsDiscount;
      int vendorIndex = 0;
      final totalVendors = itemsByVendor.length;

      final double totalDeliveryFee = await _getDeliveryTotal(cart);
      final double batchTotal = cart.totalPrice + totalDeliveryFee - totalPointsDiscount;

      for (String vendorId in itemsByVendor.keys) {
        final vendor = await supabaseService.getVendorById(vendorId);
        final vendorItems = itemsByVendor[vendorId]!;
        
        // Calculate proportional points/discount for this vendor (same as before)
        final subtotal = vendorItems.fold(0.0, (sum, item) => sum + item.totalPrice);
        double weight = cart.totalPrice > 0 ? subtotal / cart.totalPrice : 1.0 / totalVendors;
        
        int pointsUsed;
        if (vendorIndex == totalVendors - 1) {
          pointsUsed = remainingPoints;
        } else {
          pointsUsed = (totalRedeemedPoints * weight).round();
          remainingPoints -= pointsUsed;
        }

        // Format items for the secure RPC
        final secureItems = vendorItems.map((i) => {
          'product_id': i.product.id,
          'quantity': i.quantity,
          'selected_options': i.selectedOptions.map((o) => {
            'value': {
              'id': o.value.id,
              'name': o.value.name,
              'price_modifier': o.value.priceModifier,
            },
            'quantity': o.quantity,
          }).toList(),
          'notes': i.notes, // Important: pass the item-specific notes
        }).toList();

        // Calculate delivery fee for this vendor
        double vendorDeliveryFee = await _calculateVendorDeliveryFee(vendor, subtotal);

        final result = await supabaseService.placeOrderSecurely(
          vendorId: vendorId,
          items: secureItems,
          address: "${areaPrefix}الموقع الحالي",
          redeemedPoints: pointsUsed,
          batchId: batchId,
          batchTotal: batchTotal,
          notes: null,
          areaId: currentAreaId,
          deliveryFee: vendorDeliveryFee,
        );

        if (!(result['success'] ?? false)) {
          throw Exception(result['message'] ?? "فشل إتمام الطلب");
        }
        
        vendorIndex++;
      }

      if (context.mounted) {
        Navigator.pop(context); // Close loading
        cart.clearAll();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OrdersListScreen()),
        );
      }
    } catch (e) {
      debugPrint("Checkout Error: $e");
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ أثناء الطلب: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          "سـلتي",
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body:
          cart.items.isEmpty ? _buildEmpty(context) : _buildList(context, cart),
      bottomNavigationBar:
          cart.items.isEmpty ? null : _buildCheckoutBar(context, cart),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 200,
              width: 200,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: const NetworkImage(
                    'https://img.freepik.com/free-vector/empty-shopping-basket-concept-illustration_114360-17062.jpg',
                  ),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "سلتك فارغة",
              style: GoogleFonts.cairo(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "بعد اضافة منتجات للسلة، عد إلى هذه الصفحة لعرض ملخص الطلبية",
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(color: Colors.grey, height: 1.5),
            ),
            const SizedBox(height: 40),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryRed,
                    AppColors.primaryRed,
                    AppColors.secondaryPurple.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "تصفح المنتجات",
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, CartProvider cart) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: cart.items.length,
      itemBuilder: (context, index) {
        final item = cart.items[index];
        final product = item.product;
        
        // Calculate Base Price (product unit price excluding options)
        double totalOptionsCostPerUnit = 0;
        for (var opt in item.selectedOptions) {
          totalOptionsCostPerUnit += (opt.value.priceModifier * opt.quantity);
        }
        
        // Note: product.salePrice ?? product.price is the base price from the DB
        final double displayBasePrice = product.salePrice ?? product.price;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey[100]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 65,
                      height: 65,
                      color: Colors.grey[50],
                      child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: product.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.grey, size: 25),
                            )
                          : const Icon(Icons.fastfood, color: Colors.grey, size: 25),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Product Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold, 
                            fontSize: 15,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "السعر الأساسي: ${displayBasePrice.toStringAsFixed(2)} ₪",
                          style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 6),
                        
                        // Quantity Controls
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => cart.updateQuantity(item.id ?? item.product.id, item.quantity - 1),
                              child: Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey[400]),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${item.quantity}",
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => cart.updateQuantity(item.id ?? item.product.id, item.quantity + 1),
                              child: Icon(Icons.add_circle, size: 20, color: AppColors.primary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Price on Right
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () => cart.removeItem(item.id ?? item.product.id),
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "${item.totalPrice.toStringAsFixed(2)} ₪",
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold, 
                          color: Colors.black, 
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              // Options Breakdown (if any)
              if (item.selectedOptions.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, thickness: 0.5),
                ),
                ...item.selectedOptions.map((opt) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline, size: 12, color: AppColors.primary.withOpacity(0.5)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  opt.value.name,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12, 
                                    color: Colors.grey[800], 
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (opt.quantity > 1) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "×${opt.quantity}",
                                    style: GoogleFonts.cairo(
                                      fontSize: 10, 
                                      fontWeight: FontWeight.bold, 
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (opt.value.priceModifier > 0)
                          Text(
                            "+ ${(opt.value.priceModifier * opt.quantity).toStringAsFixed(2)} ₪",
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ],
              
              // Notes (if any)
              if (item.notes != null && item.notes!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange[100]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 16, color: Colors.orange[800]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "ملاحظة: ${item.notes}",
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: Colors.orange[900],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckoutBar(BuildContext context, CartProvider cart) {
    return FutureBuilder<double>(
      future: _getDeliveryTotal(cart),
      builder: (context, snapshot) {
        final deliveryFee = snapshot.data ?? _cachedDeliveryFee ?? 0.0;
        final totalWithDelivery = cart.totalPrice + deliveryFee;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 25,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Product subtotal
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${cart.totalPrice.toStringAsFixed(cart.totalPrice % 1 == 0 ? 0 : 2)} ₪",
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  Text(
                    "مجموع المنتجات",
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Delivery fee
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (snapshot.connectionState == ConnectionState.waiting && _cachedDeliveryFee == null)
                    const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Row(
                      children: [
                        if (deliveryFee == 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green[100]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFFFD700)),
                                const SizedBox(width: 4),
                                Text(
                                  "عرض توصيل مجاني✨",
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF8B5CF6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          deliveryFee == 0 ? "0 ₪" : "${deliveryFee.toStringAsFixed(deliveryFee % 1 == 0 ? 0 : 2)} ₪",
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: deliveryFee == 0 ? Colors.green[700] : Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  Text(
                    "رسوم التوصيل",
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              // Grand total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${totalWithDelivery.toStringAsFixed(totalWithDelivery % 1 == 0 ? 0 : 2)} ₪",
                    style: GoogleFonts.cairo(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    "المجموع النهائي",
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () => _showCheckoutSheet(context, cart),
                  child: Text(
                    "إتمام الطلب",
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreakdownRow(String label, String value, {bool isBold = false, double fontSize = 14, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: GoogleFonts.cairo(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: fontSize,
            color: valueColor ?? Colors.black87,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: fontSize,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}
