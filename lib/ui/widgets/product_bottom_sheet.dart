import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/models.dart';
import '../../core/providers/cart_provider.dart';
import '../screens/login_screen.dart';
import 'animated_discount_badge.dart';

class ProductBottomSheet extends StatefulWidget {
  final Product product;
  final String vendorName;
  const ProductBottomSheet({
    super.key,
    required this.product,
    required this.vendorName,
  });
  @override
  ProductBottomSheetState createState() => ProductBottomSheetState();
}

class ProductBottomSheetState extends State<ProductBottomSheet> {
  int quantity = 1;
  // OptionId -> Map<ValueId, Quantity>
  final Map<String, Map<String, int>> _selectedOptions = {};
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (var opt in widget.product.options) {
      if (opt.isRequired && !opt.isMultiple && opt.values.isNotEmpty) {
        _selectedOptions[opt.id] = {opt.values.first.id: 1};
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double get _totalPrice {
    double total = widget.product.salePrice ?? widget.product.price;
    for (var opt in widget.product.options) {
      if (_selectedOptions.containsKey(opt.id)) {
        _selectedOptions[opt.id]!.forEach((valId, qty) {
          final val = opt.values.firstWhere((v) => v.id == valId);
          total += (val.priceModifier * qty);
        });
      }
    }
    return total * quantity;
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: widget.product.imageUrl ?? '',
                        height: 250,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 20),
                      Text(
                        widget.product.name,
                        style: GoogleFonts.cairo(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.product.salePrice != null)
                            AnimatedDiscountBadge(
                              originalPrice: widget.product.price,
                              salePrice: widget.product.salePrice!,
                              primaryColor: AppColors.primary,
                              salePriceFontSize: 20,
                              originalPriceFontSize: 16,
                            )
                          else
                            Text(
                              "${widget.product.price} ₪",
                              style: GoogleFonts.cairo(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                        ],
                      ),
                    if (widget.product.description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.product.description!,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.cairo(
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ...widget.product.options.map(
                      (opt) => _buildOptionSection(opt),
                    ),
                    const SizedBox(height: 24),
                    // Notes Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                "ملاحظات خاصة (اختياري)",
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.edit_note,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _notesController,
                            textAlign: TextAlign.right,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: "مثال: بدون بصل، إضافة صلصة حارة...",
                              hintStyle: GoogleFonts.cairo(
                                fontSize: 13,
                                color: Colors.grey[400],
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: AppColors.primary,
                                ),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                            style: GoogleFonts.cairo(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
            _buildBottomAction(),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionSection(ProductOption opt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              opt.name,
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...opt.values.map((val) => _buildOptionItem(opt, val)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildOptionItem(ProductOption opt, ProductOptionValue val) {
    final currentQty = _selectedOptions[opt.id]?[val.id] ?? 0;
    final isSelected = currentQty > 0;

    return InkWell(
      onTap: () {
        setState(() {
          if (opt.isMultiple) {
            if (isSelected) {
              _selectedOptions[opt.id]?.remove(val.id);
            } else {
              _selectedOptions.putIfAbsent(opt.id, () => {})[val.id] = 1;
            }
          } else {
            _selectedOptions[opt.id] = {val.id: 1};
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            if (val.priceModifier > 0)
              Text(
                "+${val.priceModifier} ₪",
                style: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 14),
              ),
            const Spacer(),
            Text(val.name, style: GoogleFonts.cairo(fontSize: 15)),
            const SizedBox(width: 12),
            if (opt.isMultiple && isSelected)
              Row(
                children: [
                  _addonQtyBtn(Icons.add, () {
                    setState(() {
                      _selectedOptions[opt.id]![val.id] = currentQty + 1;
                    });
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      "$currentQty",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _addonQtyBtn(Icons.remove, () {
                    setState(() {
                      if (currentQty > 1) {
                        _selectedOptions[opt.id]![val.id] = currentQty - 1;
                      } else {
                        _selectedOptions[opt.id]?.remove(val.id);
                      }
                    });
                  }),
                ],
              )
            else
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: opt.isMultiple ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius:
                      opt.isMultiple ? BorderRadius.circular(4) : null,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.grey[300]!,
                    width: 2,
                  ),
                  color: isSelected ? AppColors.primary : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _addonQtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 55,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(15),
              ),
              child: ElevatedButton(
                onPressed: () {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                    return;
                  }
                  final List<SelectedAddon> selectedAddons = [];
                  for (var opt in widget.product.options) {
                    if (_selectedOptions.containsKey(opt.id)) {
                      _selectedOptions[opt.id]!.forEach((valId, qty) {
                        final val = opt.values.firstWhere((v) => v.id == valId);
                        selectedAddons.add(
                          SelectedAddon(value: val, quantity: qty),
                        );
                      });
                    }
                  }

                  Provider.of<CartProvider>(context, listen: false).addItem(
                    widget.product,
                    quantity,
                    widget.vendorName,
                    notes: _notesController.text.trim().isNotEmpty
                        ? _notesController.text.trim()
                        : null,
                    selectedOptions: selectedAddons,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "تمت الإضافة إلى السلة",
                        style: GoogleFonts.cairo(),
                        textAlign: TextAlign.right,
                      ),
                      duration: const Duration(seconds: 1),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // PRICE WITH AUTO-SCALE
                    Flexible(
                      flex: 2,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "${_totalPrice.toStringAsFixed(1)} ₪",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // SEPARATOR LINE
                    Container(
                      height: 24,
                      width: 1,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // BUTTON TEXT WITH AUTO-SCALE
                    Flexible(
                      flex: 3,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "إضافة للسلة",
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Row(
            children: [
              _qtyBtn(Icons.add, () => setState(() => quantity++)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "$quantity",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _qtyBtn(
                Icons.remove,
                () => setState(() {
                  if (quantity > 1) quantity--;
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}
