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
import '../../core/utils/vendor_navigation.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isSheetOpen = false; 
  double? _cachedDeliveryFee;
  String? _lastCartIds;

  Future<double> _calculateVendorDeliveryFee(Vendor v, double subtotal) async {
    if (v.isFreeDelivery) return 0.0;
    if (v.freeDeliveryThreshold != null && v.freeDeliveryThreshold! > 0) {
      if (subtotal >= v.freeDeliveryThreshold!) return 0.0;
    }
    if (v.useCustomDelivery) {
      return (v.customDeliveryFee ?? v.deliveryFee).toDouble();
    } else {
      final supabaseService = SupabaseService();
      return await supabaseService.getEffectiveDeliveryFee(v.areaId, v.deliveryFee, subtotal: subtotal);
    }
  }

  Future<double> _getDeliveryTotal(CartProvider cart) async {
    final currentIds = cart.items.map((i) => "${i.id ?? i.product.id}_${i.quantity}").join(',');
    if (_lastCartIds == currentIds && _cachedDeliveryFee != null) return _cachedDeliveryFee!;

    try {
      final supabaseService = SupabaseService();
      double totalDeliveryFee = 0;
      final itemsByVendor = cart.itemsByVendor;
      for (String vendorId in itemsByVendor.keys) {
        final v = await supabaseService.getVendorById(vendorId);
        final vendorItems = itemsByVendor[vendorId]!;
        final subtotal = vendorItems.fold(0.0, (sum, item) => sum + item.totalPrice);
        totalDeliveryFee += await _calculateVendorDeliveryFee(v, subtotal);
      }
      _lastCartIds = currentIds;
      _cachedDeliveryFee = totalDeliveryFee;
      return totalDeliveryFee;
    } catch (e) {
      return 0.0;
    }
  }

  void _showCheckoutSheet(BuildContext mainContext, CartProvider cart) async {
    if (_isSheetOpen) return;
    setState(() => _isSheetOpen = true);

    final supabaseService = SupabaseService();
    UserProfile? profile = await supabaseService.getUserProfile();
    final phoneController = TextEditingController(text: profile?.phone);
    final notesController = TextEditingController();
    bool isSubmitting = false;
    int redeemedPoints = 0;
    double pointsDiscount = 0.0;

    final redeemRate = double.tryParse(await supabaseService.getAppSetting('star_points_redeem_rate') ?? '10') ?? 10.0;
    final isSpendingEnabled = await supabaseService.getAppSetting('is_stars_discount_enabled') != 'false';
    final minRedeem = int.tryParse(await supabaseService.getAppSetting('star_points_min_redeem') ?? '50') ?? 50;

    double totalDeliveryFee = await _getDeliveryTotal(cart);
    final double maxPossibleDiscount = cart.totalPrice + totalDeliveryFee;

    if (mainContext.mounted) {
      showModalBottomSheet(
        context: mainContext,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 30, left: 20, right: 20),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 25),
                Text("تأكيد رقم الهاتف", style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text("يرجى التأكد من رقم هاتفك للتواصل معك بخصوص الطلب", textAlign: TextAlign.center, style: GoogleFonts.cairo(color: Colors.grey[600])),
                const SizedBox(height: 25),
                TextField(controller: phoneController, textAlign: TextAlign.right, keyboardType: TextInputType.phone, enabled: !isSubmitting, decoration: InputDecoration(hintText: "رقم الهاتف", prefixIcon: Icon(Icons.phone, color: AppColors.primary), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey[50])),
                if (profile != null && profile.starPoints > 0 && isSpendingEnabled) ...[
                  const SizedBox(height: 20),
                  Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.primary.withOpacity(0.1))), child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${profile.starPoints}", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: AppColors.primary)), Text("نقاط النجوم المتاحة", style: GoogleFonts.cairo(fontWeight: FontWeight.w600))]),
                    const Divider(height: 20),
                    if (profile.starPoints < minRedeem) Row(children: [const Icon(Icons.info_outline, size: 16, color: Colors.orange), const SizedBox(width: 8), Expanded(child: Text("تحتاج على الأقل $minRedeem نقطة للاستبدال", style: GoogleFonts.cairo(fontSize: 12, color: Colors.orange[800])))])
                    else Row(children: [
                      Switch(value: redeemedPoints > 0, activeColor: AppColors.primary, onChanged: (val) {
                        setSheetState(() {
                          if (val) {
                            redeemedPoints = profile.starPoints;
                            pointsDiscount = redeemedPoints / redeemRate;
                            if (pointsDiscount > maxPossibleDiscount) {
                              pointsDiscount = maxPossibleDiscount;
                              redeemedPoints = (pointsDiscount * redeemRate).toInt();
                            }
                          } else {
                            redeemedPoints = 0;
                            pointsDiscount = 0.0;
                          }
                        });
                      }),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          redeemedPoints > 0 ? "سيتم خصم $redeemedPoints نجمة" : "استخدام النقاط للخصم",
                          style: GoogleFonts.cairo(
                            color: redeemedPoints > 0 ? AppColors.primary : Colors.black87,
                            fontWeight: redeemedPoints > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ]),
                  ])),
                ],
                const SizedBox(height: 25),
                Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)), child: Column(children: [
                  _buildBreakdownRow("مجموع المنتجات", "${cart.totalPrice.toStringAsFixed(2)} ₪"),
                  const SizedBox(height: 10),
                  _buildBreakdownRow("رسوم التوصيل", totalDeliveryFee == 0 ? "عرض توصيل مجاني ✨" : "${totalDeliveryFee.toStringAsFixed(2)} ₪", valueColor: totalDeliveryFee == 0 ? const Color(0xFF8B5CF6) : null),
                  if (pointsDiscount > 0) ...[const SizedBox(height: 10), _buildBreakdownRow("خصم النقاط", "- ${pointsDiscount.toStringAsFixed(2)} ₪", valueColor: Colors.green[700])],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                  _buildBreakdownRow("المجموع النهائي", "${(cart.totalPrice + totalDeliveryFee - pointsDiscount).toStringAsFixed(2)} ₪", isBold: true, fontSize: 18),
                ])),
                const SizedBox(height: 30),
                Container(width: double.infinity, height: 55, decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]), child: ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    if (phoneController.text.length < 9) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال رقم هاتف صحيح"))); return; }
                    setSheetState(() => isSubmitting = true);
                    if (phoneController.text != (profile?.phone ?? "")) { try { await supabaseService.updateUserPhone(phoneController.text); } catch (e) { debugPrint("Phone update error: $e"); } }
                    try {
                      final bool success = await _processCheckout(mainContext, cart, totalRedeemedPoints: redeemedPoints, totalPointsDiscount: pointsDiscount, redeemRate: redeemRate);
                      if (success && context.mounted) {
                        Navigator.pop(sheetContext); // Close the checkout sheet
                        Navigator.pushReplacement(mainContext, MaterialPageRoute(builder: (_) => const OrdersListScreen()));
                      }
                    } catch (e) { 
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e"))); 
                    } finally { 
                      if (mounted) setSheetState(() => isSubmitting = false); 
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: isSubmitting ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text("تأكيد وإرسال الطلب", style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                )),
              ]),
            ),
          ),
        ),
      ).whenComplete(() { if (mounted) setState(() => _isSheetOpen = false); });
    }
  }

  Future<bool> _processCheckout(BuildContext context, CartProvider cart, {int totalRedeemedPoints = 0, double totalPointsDiscount = 0, double redeemRate = 10.0}) async {
    final supabaseService = SupabaseService();
    showDialog(context: context, barrierDismissible: false, builder: (context) => Center(child: CircularProgressIndicator(color: AppColors.primary)));
    try {
      final itemsByVendor = cart.itemsByVendor;
      final String batchId = const Uuid().v4();
      final guestLoc = await supabaseService.getGuestLocation();
      final String currentAreaId = guestLoc?['area_id']?.toString() ?? "";
      final String areaPrefix = guestLoc?['address_line_1'] != null ? "${guestLoc!['address_line_1']} - " : "";
      double totalDeliveryFee = await _getDeliveryTotal(cart);
      double batchTotal = cart.totalPrice + totalDeliveryFee - totalPointsDiscount;
      int remainingPoints = totalRedeemedPoints;
      int vendorIndex = 0;
      for (String vendorId in itemsByVendor.keys) {
        final vendor = await supabaseService.getVendorById(vendorId);
        final vendorItems = itemsByVendor[vendorId]!;
        final subtotal = vendorItems.fold(0.0, (sum, item) => sum + item.totalPrice);
        int pointsUsed = (vendorIndex == itemsByVendor.length - 1) ? remainingPoints : (totalRedeemedPoints * (subtotal / cart.totalPrice)).round();
        remainingPoints -= pointsUsed;
        final secureItems = vendorItems.map((i) => {
          'product_id': i.product.id, 'quantity': i.quantity,
          'selected_options': i.selectedOptions.map((o) => {'value': {'id': o.value.id, 'name': o.value.name, 'price_modifier': o.value.priceModifier}, 'quantity': o.quantity}).toList(),
          'notes': i.notes,
        }).toList();
        
        final response = await supabaseService.placeOrderSecurely(
          vendorId: vendorId, items: secureItems, address: "${areaPrefix}الموقع الحالي",
          redeemedPoints: pointsUsed, batchId: batchId, batchTotal: batchTotal, areaId: currentAreaId,
          deliveryFee: await _calculateVendorDeliveryFee(vendor, subtotal),
        );

        if (response['success'] != true) {
          throw response['message'] ?? "فشل إرسال الطلب لمتجر ${vendor.name}";
        }
        
        vendorIndex++;
      }
      
      if (context.mounted) { 
        Navigator.pop(context); // Close loading dialog
        cart.clearAll(); 
      }
      return true;
    } catch (e) { 
      if (context.mounted) { 
        Navigator.pop(context); // Close loading dialog
        rethrow;
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, title: Text("سـلتي", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.black)), centerTitle: true),
      body: cart.items.isEmpty ? _buildEmpty(context) : _buildList(context, cart),
      bottomNavigationBar: cart.items.isEmpty ? null : _buildCheckoutBar(context, cart),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(height: 200, width: 200, decoration: const BoxDecoration(image: DecorationImage(image: NetworkImage('https://img.freepik.com/free-vector/empty-shopping-basket-concept-illustration_114360-17062.jpg'), fit: BoxFit.contain))),
      const SizedBox(height: 20),
      Text("سلتك فارغة", style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text("بعد اضافة منتجات للسلة، عد إلى هذه الصفحة لعرض ملخص الطلبية", textAlign: TextAlign.center, style: GoogleFonts.cairo(color: Colors.grey, height: 1.5)),
      const SizedBox(height: 40),
      Container(decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(16)), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: () => Navigator.pop(context), child: Text("تصفح المنتجات", style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
    ])));
  }

  Widget _buildList(BuildContext context, CartProvider cart) {
    final itemsByVendor = cart.itemsByVendor;
    final supabaseService = SupabaseService();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: itemsByVendor.entries.map((entry) {
        final vendorId = entry.key;
        final vendorItems = entry.value;
        return FutureBuilder<Vendor>(
          future: supabaseService.getVendorById(vendorId),
          builder: (context, snapshot) {
            final vendor = snapshot.data;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () { if (vendor != null) VendorNavigation.navigateToVendor(context, vendor); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12), margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    if (vendor?.logoUrl != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: vendor!.logoUrl!, width: 32, height: 32, fit: BoxFit.cover))
                    else Icon(Icons.storefront_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(vendor?.name ?? "جاري التحميل...", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87))),
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Colors.grey),
                  ]),
                ),
              ),
              ...vendorItems.map((item) => _buildCartItem(context, cart, item)),
            ]);
          },
        );
      }).toList(),
    );
  }

  Widget _buildCartItem(BuildContext context, CartProvider cart, CartItem item) {
    final product = item.product;
    final double displayBasePrice = product.salePrice ?? product.price;
    return Container(
      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[100]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(width: 65, height: 65, color: Colors.grey[50], child: (product.imageUrl != null && product.imageUrl!.isNotEmpty) ? CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.grey, size: 25)) : const Icon(Icons.fastfood, color: Colors.grey, size: 25))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text("السعر الأساسي: ${displayBasePrice.toStringAsFixed(2)} ₪", style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 6),
            Row(children: [
              GestureDetector(onTap: () => cart.updateQuantity(item.id ?? item.product.id, item.quantity - 1), child: Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey[400])),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text("${item.quantity}", style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary))),
              const SizedBox(width: 8),
              GestureDetector(onTap: () => cart.updateQuantity(item.id ?? item.product.id, item.quantity + 1), child: Icon(Icons.add_circle, size: 20, color: AppColors.primary)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(onPressed: () => cart.removeItem(item.id ?? item.product.id), icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            const SizedBox(height: 10),
            Text("${item.totalPrice.toStringAsFixed(2)} ₪", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16)),
          ]),
        ]),
        if (item.selectedOptions.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, thickness: 0.5)),
          ...item.selectedOptions.map((opt) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Row(children: [Icon(Icons.add_circle_outline, size: 12, color: AppColors.primary.withOpacity(0.5)), const SizedBox(width: 8), Flexible(child: Text(opt.value.name, style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)), if (opt.quantity > 1) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)), child: Text("×${opt.quantity}", style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700])))]])),
            if (opt.value.priceModifier > 0) Text("+ ${(opt.value.priceModifier * opt.quantity).toStringAsFixed(2)} ₪", style: GoogleFonts.cairo(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.bold)),
          ]))),
        ],
        if (item.notes != null && item.notes!.isNotEmpty) Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange[100]!)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.edit_note_rounded, size: 16, color: Colors.orange[800]), const SizedBox(width: 8), Expanded(child: Text("ملاحظة: ${item.notes}", style: GoogleFonts.cairo(fontSize: 11, color: Colors.orange[900], fontStyle: FontStyle.italic)))]))
      ]),
    );
  }

  Widget _buildCheckoutBar(BuildContext context, CartProvider cart) {
    return FutureBuilder<double>(
      future: _getDeliveryTotal(cart),
      builder: (context, snapshot) {
        final deliveryFee = snapshot.data ?? _cachedDeliveryFee ?? 0.0;
        final totalWithDelivery = cart.totalPrice + deliveryFee;
        return Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 25, offset: Offset(0, -5))]), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${cart.totalPrice.toStringAsFixed(2)} ₪", style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])), Text("مجموع المنتجات", style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600]))]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            if (snapshot.connectionState == ConnectionState.waiting && _cachedDeliveryFee == null) const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else Row(children: [if (deliveryFee == 0) ...[Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green[100]!)), child: Row(children: [const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFFFD700)), const SizedBox(width: 4), Text("عرض توصيل مجاني✨", style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF8B5CF6)))]))], const SizedBox(width: 8), Text(deliveryFee == 0 ? "0 ₪" : "${deliveryFee.toStringAsFixed(2)} ₪", style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: deliveryFee == 0 ? Colors.green[700] : Colors.grey[800]))]),
            Text("رسوم التوصيل", style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600])),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${totalWithDelivery.toStringAsFixed(2)} ₪", style: GoogleFonts.cairo(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primary)), Text("المجموع النهائي", style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87))]),
          const SizedBox(height: 20),
          Container(height: 60, width: double.infinity, decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), onPressed: () => _showCheckoutSheet(context, cart), child: Text("إتمام الطلب", style: GoogleFonts.cairo(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
        ]));
      },
    );
  }

  Widget _buildBreakdownRow(String label, String value, {bool isBold = false, double fontSize = 14, Color? valueColor}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(value, textDirection: TextDirection.ltr, style: GoogleFonts.cairo(fontWeight: isBold ? FontWeight.bold : FontWeight.w500, fontSize: fontSize, color: valueColor ?? Colors.black87)),
      Text(label, style: GoogleFonts.cairo(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: fontSize, color: Colors.grey[700])),
    ]);
  }
}
