import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../core/services/supabase_service.dart' as supabase_service;
import '../../core/models/models.dart';
import '../widgets/product_bottom_sheet.dart';
import '../widgets/animated_discount_badge.dart';

class CategoryProductsScreen extends StatefulWidget {
  final MenuCategory initialCategory;
  final List<MenuCategory> allCategories;

  final String vendorName;

  const CategoryProductsScreen({
    super.key,
    required this.initialCategory,
    required this.allCategories,
    required this.vendorName,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  late MenuCategory _selectedCategory;
  String? _selectedSubCategoryId;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Pagination State
  final List<Product> _paginatedProducts = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _initializeSubCategories();
    _scrollController.addListener(_onScroll);
    
    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProducts(reset: true);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadProducts();
    }
  }

  Future<void> _loadProducts({bool reset = false}) async {
    if (_isLoading || (_isLoadingMore && !reset)) return;

    if (reset) {
      if (mounted) setState(() => _isLoading = true);
      _offset = 0;
      _hasMore = true;
    } else {
      if (mounted) setState(() => _isLoadingMore = true);
    }

    final supabase = Provider.of<supabase_service.SupabaseService>(
      context,
      listen: false,
    );

    final List<Product> newProducts = await supabase.getPaginatedProducts(
      categoryId: _selectedCategory.id,
      offset: _offset,
      limit: _limit,
      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
    );

    if (mounted) {
      setState(() {
        if (reset) {
          _paginatedProducts.clear();
          _isLoading = false;
        } else {
          _isLoadingMore = false;
        }
        _paginatedProducts.addAll(newProducts);
        _offset += newProducts.length;
        _hasMore = newProducts.length >= _limit;
      });
    }
  }

  void _initializeSubCategories() {
    if (_selectedCategory.subCategories.isNotEmpty) {
      _selectedSubCategoryId = _selectedCategory.subCategories.first.id;
    } else {
      _selectedSubCategoryId = null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _selectedCategory.name,
          style: GoogleFonts.cairo(
            color: const Color(0xFF1F2937),
            fontWeight: FontWeight.w900,
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.grey[100],
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 1. Search Bar & Main Categories (Scrolls away)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                          _loadProducts(reset: true);
                        },
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          hintText: "بحث داخل ${_selectedCategory.name}...",
                          hintStyle: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 20,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Horizontal Filter Tabs (Categories - Level 1)
                  SizedBox(
                    height: 110,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: widget.allCategories.length,
                      itemBuilder: (context, index) {
                        final cat = widget.allCategories[index];
                        return _buildCategoryChip(cat);
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            // 2. Sticky Sub-Categories (Level 2)
            // 2. Sticky Sub-Categories (Level 2)
            if (_selectedCategory.subCategories.isNotEmpty)
              SliverPersistentHeader(
                pinned: true,
                delegate: _SubCategoryHeaderDelegate(
                  subCategories: _selectedCategory.subCategories,
                  selectedSubCategoryId: _selectedSubCategoryId,
                  onSelect: (subId) {
                    setState(() {
                      _selectedSubCategoryId = subId;
                    });
                  },
                ),
              ),

            // 3. Products Grid
            _buildSliverProductsGrid(),

            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverProductsGrid() {
    if (_isLoading && _paginatedProducts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final filteredProducts = _paginatedProducts.where((p) {
      bool matchesSubCategory = true;
      if (_selectedSubCategoryId != null) {
        matchesSubCategory = p.subCategoryId == _selectedSubCategoryId;
      }
      return matchesSubCategory;
    }).toList();

    if (filteredProducts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
              const SizedBox(height: 10),
              Text(
                "لا توجد منتجات مطابقة",
                style: GoogleFonts.cairo(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _buildProductCard(context, filteredProducts[index]),
          childCount: filteredProducts.length,
        ),
      ),
    );
  }

  Widget _buildCategoryChip(MenuCategory cat) {
    final isSelected = cat.id == _selectedCategory.id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = cat;
          _searchQuery = '';
          _searchController.clear();
          _selectedSubCategoryId = null;
          _initializeSubCategories();
        });
        _loadProducts(reset: true);
      },
      child: Container(
        width: 80, // Fixed width for consistent cards
        margin: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: isSelected ? 2 : 0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                child: cat.imageUrl != null && cat.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: cat.imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[100],
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                            size: 30,
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.grey[100], // Placeholder color
                        child: const Center(
                          child: Icon(Icons.store, color: Colors.grey),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6.0),
              child: Text(
                cat.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  color: isSelected ? AppColors.primary : Colors.grey[800],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, Product product) {
    return InkWell(
      onTap: () => _showProductDetails(product),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl ?? '',
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[100],
                    child: Icon(
                      Icons.fastfood,
                      color: Colors.grey[300],
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.name,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1F2937),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (product.salePrice != null)
                              AnimatedDiscountBadge(
                                originalPrice: product.price,
                                salePrice: product.salePrice!,
                                primaryColor: AppColors.primary,
                                salePriceFontSize: 16,
                                originalPriceFontSize: 12,
                              )
                            else
                              Text(
                                "${product.price} ₪",
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductDetails(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ProductBottomSheet(product: product, vendorName: widget.vendorName),
    );
  }
}

class _SubCategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<SubCategory> subCategories;
  final String? selectedSubCategoryId;
  final Function(String?) onSelect;

  _SubCategoryHeaderDelegate({
    required this.subCategories,
    required this.selectedSubCategoryId,
    required this.onSelect,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: const Color(0xFFF8F9FA), // Background color matches scaffold
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: subCategories.length + 1,
        itemBuilder: (context, index) {
          String? subId;
          String label;
          if (index == 0) {
            subId = null;
            label = "الكل";
          } else {
            final sub = subCategories[index - 1];
            subId = sub.id;
            label = sub.name;
          }

          final isSelected = selectedSubCategoryId == subId;
          return InkWell(
            onTap: () => onSelect(subId),
            child: Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1F2937)
                    : Colors.white, // Dark for sub-cat match
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1F2937)
                      : Colors.grey[300]!,
                ),
                boxShadow: [
                  if (!isSelected)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Center(
                child: Text(
                  label,
                  style: GoogleFonts.cairo(
                    color: isSelected ? Colors.white : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  double get maxExtent => 60.0; // Height of the header

  @override
  double get minExtent => 60.0;

  @override
  bool shouldRebuild(covariant _SubCategoryHeaderDelegate oldDelegate) {
    return oldDelegate.selectedSubCategoryId != selectedSubCategoryId ||
        oldDelegate.subCategories != subCategories;
  }
}
