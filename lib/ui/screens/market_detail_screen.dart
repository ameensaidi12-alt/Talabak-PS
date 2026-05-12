import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../../core/models/models.dart';
import 'market_search_screen.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/services/supabase_service.dart';
import 'category_products_screen.dart';
import '../widgets/product_bottom_sheet.dart';
import 'cart_screen.dart';
import '../../core/theme/app_colors.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/animated_discount_badge.dart';

class MarketDetailScreen extends StatefulWidget {
  final Vendor vendor;
  final String? initialProductId;
  const MarketDetailScreen({super.key, required this.vendor, this.initialProductId});

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  late SupabaseService _supabaseService;
  late Vendor _vendor;
  late Future<List<MenuCategory>> _menuFuture;
  bool _isFavorite = false;
  final ScrollController _scrollController = ScrollController();
  bool _isInitialized = false;
  double _cardOpacity = 1.0;
  double _effectiveDeliveryFee = 0.0;
  
  // Pagination State
  final List<Product> _allProductsBatch = [];
  bool _isLoadingProducts = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _batchSize = 20;


  @override
  void initState() {
    super.initState();
    _vendor = widget.vendor;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _supabaseService = Provider.of<SupabaseService>(context, listen: false);
      _checkIfOpeningTimeMissing();
      _menuFuture = _supabaseService.getVendorMenu(
        _vendor.id,
        vendorType: _vendor.type,
      );
      _checkFavorite();

      _scrollController.addListener(_onScroll);
      _fetchEffectiveDeliveryFee();
      _loadInitialProducts();
      _isInitialized = true;

      if (widget.initialProductId != null) {
        _loadAndShowProduct(widget.initialProductId!);
      }
    }
  }

  Future<void> _loadAndShowProduct(String productId) async {
    try {
      final productRes = await _supabaseService.client
          .from('products')
          .select()
          .eq('id', productId)
          .maybeSingle();
      if (productRes != null && mounted) {
        final product = Product.fromJson(productRes);
        _showProductDetails(product);
      }
    } catch (e) {
      debugPrint("Error auto-loading product: $e");
    }
  }

  Future<void> _fetchEffectiveDeliveryFee() async {
    double fee;
    if (_vendor.useCustomDelivery) {
      fee = (_vendor.customDeliveryFee ?? _vendor.deliveryFee).toDouble();
    } else {
      final cart = Provider.of<CartProvider>(context, listen: false);
      final vendorSubtotal = cart.items
          .where((item) => item.product.vendorId == _vendor.id)
          .fold(0.0, (sum, item) => sum + item.totalPrice);

      fee = await _supabaseService.getEffectiveDeliveryFee(
        _vendor.areaId,
        _vendor.deliveryFee,
        subtotal: vendorSubtotal,
        vendorThreshold: _vendor.freeDeliveryThreshold,
      );
    }
    
    if (mounted) {
      setState(() {
        _effectiveDeliveryFee = fee;
      });
    }
  }

  Future<void> _checkIfOpeningTimeMissing() async {
    if (_vendor.openingTime == null) {
      try {
        final fullVendor = await _supabaseService.getVendorById(_vendor.id);
        if (mounted) {
          setState(() {
            _vendor = fullVendor;
          });
        }
      } catch (e) {
        debugPrint("Error fetching full vendor data: $e");
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkFavorite() async {
    final status = await _supabaseService.isFavorite(_vendor.id);
    if (mounted) setState(() => _isFavorite = status);
  }

  Future<void> _toggleFavorite() async {
    await _supabaseService.toggleFavorite(_vendor.id, _isFavorite);
    setState(() => _isFavorite = !_isFavorite);
  }

  void _onScroll() {
    final scrollOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    
    // 1. Handle Card Opacity
    double newOpacity = 1.0 - (scrollOffset / 100.0).clamp(0.0, 1.0);
    if (newOpacity != _cardOpacity) {
      setState(() => _cardOpacity = newOpacity);
    }

    // 2. Handle Pagination Trigger
    if (scrollOffset >= maxScroll - 400 && !_isLoadingMore && _hasMore) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadInitialProducts() async {
    if (_isLoadingProducts) return;
    setState(() => _isLoadingProducts = true);
    
    final List<Product> products = await _supabaseService.getPaginatedProducts(
      vendorId: _vendor.id,
      offset: 0,
      limit: _batchSize,
    );

    if (mounted) {
      setState(() {
        _allProductsBatch.clear();
        _allProductsBatch.addAll(products);
        _offset = products.length;
        _hasMore = products.length >= _batchSize;
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final List<Product> products = await _supabaseService.getPaginatedProducts(
      vendorId: _vendor.id,
      offset: _offset,
      limit: _batchSize,
    );

    if (mounted) {
      setState(() {
        _allProductsBatch.addAll(products);
        _offset += products.length;
        _hasMore = products.length >= _batchSize;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardTop = screenWidth > 600 ? 240.0 : 220.0;
    final spacingHeight = screenWidth > 600 ? 230.0 : 250.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              _buildHeader(),
              SliverToBoxAdapter(
                child: SizedBox(height: spacingHeight),
              ), // Increased space
              _buildCategoryGridHeader(),
              _buildCategoriesGrid(),
              _buildProductsHeader(),
              _buildProductsGrid(),
            ],
          ),
          // Vendor Info Card positioned over the header
          Positioned(
            top: cardTop,
            left: 20,
            right: 20,
            child: IgnorePointer(
              ignoring: _cardOpacity < 0.2, // Allow scrolling through if almost hidden
              child: Opacity(
                opacity: _cardOpacity,
                child: _buildVendorInfoCardOverlay(),
              ),
            ),
          ),
          if (Provider.of<CartProvider>(context).items.isNotEmpty)
            Positioned(bottom: 20, left: 20, child: _buildFloatingCart()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.white,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.black.withOpacity(0.35),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.black.withOpacity(0.35),
            child: IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 20),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MarketSearchScreen(
                      vendorId: _vendor.id,
                      vendorName: _vendor.name,
                      menuFuture: _menuFuture,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.black.withOpacity(0.35),
            child: IconButton(
              icon: const Icon(Icons.share, color: Colors.white, size: 20),
              onPressed: () async {
                final String vendorId = _vendor.id;
                final String vendorName = _vendor.name;
                
                // Create the deep link
                final String shareText = 
                  "اطلب الآن من متجر ($vendorName) عبر تطبيق طلبك!\n"
                  "https://talabakps.com/shop?id=$vendorId";
                
                await Share.share(shareText);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: (_vendor.coverImageUrl != null &&
                      _vendor.coverImageUrl!.isNotEmpty)
                  ? _vendor.coverImageUrl!
                  : (_vendor.logoUrl ?? 'https://via.placeholder.com/800x400'),
              fit: BoxFit.cover,
            ),
            // Semi-transparent overlay for better visibility of back/search/share buttons
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorInfoCardOverlay() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _toggleFavorite,
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? AppColors.primary : Colors.grey[400],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Text(
                          _vendor.name,
                          style: GoogleFonts.cairo(
                            fontSize: MediaQuery.of(context).size.width < 400
                                ? 18
                                : 22, // Smaller font for mobile
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF2D2D2D),
                            height: 1.2,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 2, // Allow 2 lines
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min, // Hug content
                      children: [
                        Flexible(
                          child: Text(
                            (_vendor.address != null && _vendor.address!.isNotEmpty)
                                ? _vendor.address!
                                : (_vendor.areaName ?? "موقع غير محدد"),
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _vendor.isOpen ? "مفتوح الآن" : "مغلق حالياً",
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            color: _vendor.isOpen
                                ? const Color(0xFF10B981)
                                : const Color(0xFFDC2626),
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.circle,
                          color: _vendor.isOpen
                              ? const Color(0xFF10B981)
                              : const Color(0xFFDC2626),
                          size: 8,
                        ),
                      ],
                    ),
                    if (_vendor.isBestSelling) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFFFB300).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              size: 14,
                              color: Color(0xFFFFB300),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "الأكثر مبيعاً",
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_vendor.freeDeliveryThreshold != null && _vendor.freeDeliveryThreshold! > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: Color(0xFF059669),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "توصيل مجاني فوق ${_vendor.freeDeliveryThreshold!.toInt()} ₪",
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF065F46),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Service Badges (Active Services)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_vendor.hasPickup)
                          _buildServiceIcon(
                            Icons.shopping_bag,
                            iconColor: const Color(0xFF3B82F6),
                            bgColor: const Color(0xFFEFF6FF),
                          ),
                        if (_vendor.hasDelivery)
                          _buildServiceIcon(
                            _vendor.isFreeDelivery
                                ? Icons.local_offer
                                : Icons.directions_bike,
                            iconColor: const Color(0xFF10B981),
                            bgColor: const Color(0xFFECFDF5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[100]!, width: 2),
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: _vendor.logoUrl ?? '',
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.store, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Logic for Delivery Icons (3 Cases) with Colors
              if (_effectiveDeliveryFee == 0 && _vendor.hasDelivery)
                _buildStatItem(
                  icon: Icons.local_offer,
                  iconColor: const Color(0xFF10B981), // Green for Free
                  bgColor: const Color(0xFFECFDF5),
                  title: "توصيل مجاني",
                  subtitle: "0 ₪",
                )
              else if (_vendor.hasDelivery)
                _buildStatItem(
                  icon: Icons.delivery_dining,
                  iconColor: const Color(0xFF10B981), // Green as requested
                  bgColor: const Color(0xFFECFDF5),
                  title: "توصيل",
                  subtitle: "${_effectiveDeliveryFee.toInt()} ₪",
                )
              else
                _buildStatItem(
                  icon: Icons
                      .store, // Store icon for Pickup Only (Clearer than cancel)
                  iconColor: Colors.orange,
                  bgColor: Colors.orange.withOpacity(0.1),
                  title: "استلام فقط", // Changed text to be more positive
                  subtitle: "لا يوجد توصيل",
                ),
              _buildStatItem(
                icon: Icons.access_time,
                iconColor: _vendor.isOpen
                    ? const Color(0xFF10B981)
                    : Colors.red,
                bgColor: _vendor.isOpen
                    ? const Color(0xFFECFDF5)
                    : Colors.red.withOpacity(0.1),
                title: _vendor.isOpen ? "مفتوح" : "مغلق",
                subtitle:
                    "${_vendor.openingTime ?? '09:00'} - ${_vendor.closingTime ?? '22:00'}",
              ),
              _buildStatItem(
                icon: Icons.timer,
                title: "وقت التوصيل",
                subtitle: _vendor.formattedEstimatedTime,
              ),
              InkWell(
                onTap: _handleRatingTap,
                borderRadius: BorderRadius.circular(12),
                child: _buildStatItem(
                  icon: Icons.star_border,
                  title: _vendor.rating > 0
                      ? _vendor.rating.toStringAsFixed(1)
                      : "-",
                  subtitle: "لا يوجد تقييم",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
    Color? bgColor,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bgColor ?? const Color(0xFFF3F4F6),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: iconColor ?? const Color(0xFF1F2937),
            size: 20,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1F2937),
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          subtitle,
          style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[500]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCategoryGridHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
        child: Text(
          "الفئات المتاحة",
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1F2937),
          ),
          textAlign: TextAlign.right,
        ),
      ),
    );
  }

  Widget _buildCategoriesGrid() {
    return FutureBuilder<List<MenuCategory>>(
      future: _menuFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverToBoxAdapter(
            child: Center(
              child: SpinKitPulse(color: AppColors.primary, size: 40),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text("لا توجد فئات متاحة", style: GoogleFonts.cairo()),
              ),
            ),
          );
        }

        final categories = snapshot.data!;
        final screenWidth = MediaQuery.of(context).size.width;
        final crossAxisCount = screenWidth > 600 ? 3 : 2;

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 1.1,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final cat = categories[index];
              return _buildCategoryCard(cat, categories);
            }, childCount: categories.length),
          ),
        );
      },
    );
  }

  Widget _buildCategoryCard(
    MenuCategory cat,
    List<MenuCategory> allCategories,
  ) {
    // Use category image if available, otherwise fallback to first product image
    final imageUrl = cat.imageUrl != null && cat.imageUrl!.isNotEmpty
        ? cat.imageUrl
        : (cat.products.isNotEmpty ? cat.products.first.imageUrl : '');

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CategoryProductsScreen(
              initialCategory: cat,
              allCategories: allCategories,
              vendorName: _vendor.name,
            ),
          ),
        );
      },
      child: Container(
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
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: imageUrl ?? '',
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[100],
                        child: Icon(Icons.category, color: Colors.grey[300]),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.6),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              width: double.infinity,
              child: Text(
                cat.name,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingCart() {
    final cart = Provider.of<CartProvider>(context);
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CartScreen()),
      ),
      backgroundColor: AppColors.primary,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      label: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.white,
            child: Text(
              "${cart.totalItemsCount}",
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "عرض السلة",
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "${cart.totalPrice} ₪",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 15),
        child: Text(
          "جميع المنتجات",
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1F2937),
          ),
          textAlign: TextAlign.right,
        ),
      ),
    );
  }

  Widget _buildProductsGrid() {
    if (_isLoadingProducts && _allProductsBatch.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: SpinKitPulse(color: AppColors.primary, size: 40),
          ),
        ),
      );
    }

    if (_allProductsBatch.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              "لا توجد منتجات متاحة حالياً",
              style: GoogleFonts.cairo(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 3 : 2;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 0.75,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return _buildProductCard(_allProductsBatch[index]);
              },
              childCount: _allProductsBatch.length,
            ),
          ),
          if (_hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: SpinKitThreeBounce(
                    color: AppColors.primary.withOpacity(0.5),
                    size: 25,
                  ),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(
              child: SizedBox(height: 100), // Bottom padding
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return InkWell(
      onTap: () => _showProductDetails(product),
      borderRadius: BorderRadius.circular(15),
      child: Container(
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.name,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1F2937),
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
                        if (product.salePrice != null)
                          AnimatedDiscountBadge(
                            originalPrice: product.price,
                            salePrice: product.salePrice!,
                            primaryColor: AppColors.primary,
                            salePriceFontSize: 16,
                            originalPriceFontSize: 12,
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
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

  Widget _buildServiceIcon(IconData icon, {Color? iconColor, Color? bgColor}) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor ?? Colors.grey[100],
        shape: BoxShape.circle,
        border: Border.all(
          color: (iconColor ?? AppColors.primary).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Icon(icon, color: iconColor ?? AppColors.primary, size: 16),
    );
  }


  void _showProductDetails(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ProductBottomSheet(product: product, vendorName: _vendor.name),
    );
  }

  Future<void> _handleRatingTap() async {
    final supabase = Provider.of<SupabaseService>(context, listen: false);
    final user = supabase.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يرجى تسجيل الدخول للتقييم")),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final orderId = await supabase.getRateableOrderId(_vendor.id);
    
    if (mounted) Navigator.pop(context); // Remove loading

    if (orderId != null) {
      _showRatingDialog(orderId);
    } else {
      _showLuxuriousMessage();
    }
  }

  void _showLuxuriousMessage() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
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
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.stars_rounded, color: AppColors.primary, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              "حضرة العميل الراقي",
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "لضمان مصداقية التقييمات، يرجى التكرم بالطلب أولاً من هذا المتجر. بمجرد استلام طلبك، سيفتح لك باب التقييم بكل حب ومصداقية لتعبر عن رأيك الرائع.",
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 15,
                color: Colors.grey[700],
                height: 1.6,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  "فهمت ذلك",
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showRatingDialog(String orderId) {
    int selectedRating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "تقييم المتجر",
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "كيف كانت تجربتك مع ${_vendor.name}؟",
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < selectedRating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFFFC107),
                      size: 30,
                    ),
                    onPressed: () => setDialogState(() => selectedRating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "أضف تعليقك (اختياري)...",
                  hintStyle: GoogleFonts.cairo(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("إلغاء", style: GoogleFonts.cairo(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final supabase = Provider.of<SupabaseService>(context, listen: false);
                try {
                  await supabase.submitRating(
                    vendorId: _vendor.id,
                    orderId: orderId,
                    rating: selectedRating,
                    comment: commentController.text.trim(),
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("شكرًا لتقييمك!")),
                    );
                    setState(() {});
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("خطأ: $e")),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text("إرسال", style: GoogleFonts.cairo(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
