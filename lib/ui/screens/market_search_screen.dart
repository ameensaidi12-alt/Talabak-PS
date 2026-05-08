import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/product_bottom_sheet.dart';
import '../widgets/animated_discount_badge.dart';

class MarketSearchScreen extends StatefulWidget {
  final String vendorId;
  final String vendorName;
  final Future<List<MenuCategory>> menuFuture;

  const MarketSearchScreen({
    super.key,
    required this.vendorId,
    required this.vendorName,
    required this.menuFuture,
  });

  @override
  State<MarketSearchScreen> createState() => _MarketSearchScreenState();
}

class _MarketSearchScreenState extends State<MarketSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final categories = await widget.menuFuture;
      final products = categories.expand((cat) => cat.products).toList();
      if (mounted) {
        setState(() {
          _allProducts = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterProducts(String query) {
    if (query.isEmpty) {
      setState(() => _filteredProducts = []);
      return;
    }
    setState(() {
      _filteredProducts = _allProducts
          .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            hintText: "ابحث عن منتج...",
            hintStyle: GoogleFonts.cairo(color: Colors.grey[400]),
            border: InputBorder.none,
          ),
          style: GoogleFonts.cairo(color: Colors.black),
          onChanged: _filterProducts,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredProducts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    _searchController.text.isEmpty
                        ? "ابحث في قائمة المطعم"
                        : "لا توجد نتائج",
                    style: GoogleFonts.cairo(
                      color: Colors.grey[500],
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredProducts.length,
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
                return _buildProductItem(product);
              },
            ),
    );
  }

  Widget _buildProductItem(Product product) {
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => ProductBottomSheet(
            product: product,
            vendorName: widget.vendorName,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.name,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  if (product.salePrice != null)
                    AnimatedDiscountBadge(
                      originalPrice: product.price,
                      salePrice: product.salePrice!,
                      primaryColor: AppColors.primary,
                      salePriceFontSize: 14,
                      originalPriceFontSize: 12,
                    )
                  else
                    Text(
                      "${product.price} ₪",
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl ?? '',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey[100],
                  child: const Icon(Icons.fastfood, color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
