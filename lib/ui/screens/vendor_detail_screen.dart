import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'category_products_screen.dart';
import '../../core/models/models.dart';
import '../../core/providers/cart_provider.dart';
import '../../core/services/supabase_service.dart';
import '../widgets/product_bottom_sheet.dart';
import 'market_search_screen.dart';
import 'cart_screen.dart';
import '../../core/theme/app_colors.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/animated_discount_badge.dart';

class VendorDetailScreen extends StatefulWidget {
  final Vendor vendor;
  final String? initialCategoryId;
  final String? initialProductId;
  const VendorDetailScreen({super.key, required this.vendor, this.initialCategoryId, this.initialProductId});

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen>
    with TickerProviderStateMixin {
  late SupabaseService _supabaseService;
  late Vendor _vendor;
  late Future<List<MenuCategory>> _menuFuture;
  bool _isFavorite = false;
  final ScrollController _scrollController = ScrollController();
  double _logoOpacity = 1.0;
  bool _isInitialized = false;
  double _effectiveDeliveryFee = 0.0;

  late AnimationController _shimmerController;
  late AnimationController _glowController;
  final Map<String, GlobalKey> _categoryKeys = {};
  int _activeCategoryIndex = 0;
  bool _hasAutoScrolled = false;
  bool _showScrollHint = true;

  void _scrollToCategory(String categoryId) {
    if (!mounted) return;
    final key = _categoryKeys[categoryId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.1, // Slight offset
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _vendor = widget.vendor;
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showScrollHint = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _supabaseService = Provider.of<SupabaseService>(context, listen: false);
      _checkIfOpeningTimeMissing();
      _menuFuture = _supabaseService.getVendorMenu(
        _vendor.id,
        vendorType: _vendor.id == '99' ? 'all' : _vendor.type,
      ).then((cats) {
        for (var cat in cats) {
          _categoryKeys[cat.id] = GlobalKey();
        }
        return cats;
      });
      _checkFavorite();
      _fetchDeliveryFee();
      _scrollController.addListener(_onScroll);
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

  Future<void> _fetchDeliveryFee() async {
    double fee;
    if (_vendor.useCustomDelivery) {
      fee = (_vendor.customDeliveryFee ?? _vendor.deliveryFee).toDouble();
    } else {
      fee = await _supabaseService.getEffectiveDeliveryFee(
        _vendor.areaId,
        _vendor.deliveryFee,
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

  void _onScroll() {
    final scrollOffset = _scrollController.offset;
    double newOpacity = 1.0 - (scrollOffset / 40.0).clamp(0.0, 1.0);
    if (newOpacity != _logoOpacity) {
      setState(() => _logoOpacity = newOpacity);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _shimmerController.dispose();
    _glowController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildHero(context),
              _buildCenteredHeader(),
              _buildStickyCategoryBar(),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              _buildMenuSections(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          /// اللوقو العائم
          Positioned(
            top: 265,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _logoOpacity,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                        colors: [
                          Color(0xFF833AB4), // Purple
                          Color(0xFFFD1D1D), // Pink/Red
                          Color(0xFFFCAF45), // Orange
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3.5), // Thickness of the gradient ring
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white, // Inner white ring
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3.0), // Thickness of the white ring
                          child: ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: _vendor.logoUrl ?? '',
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.restaurant,
                                size: 40,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (Provider.of<CartProvider>(context).items.isNotEmpty)
            Positioned(bottom: 20, left: 20, child: _buildFloatingCart()),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: CircleAvatar(
              backgroundColor: Colors.black.withOpacity(0.3),
              child: IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.3),
                child: IconButton(
                  icon: const Icon(Icons.search, color: Colors.white, size: 20),
                  onPressed: () {
                    // Navigate to search screen for this vendor
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
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.3),
                child: IconButton(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? AppColors.primary : Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.blurBackground,
          StretchMode.zoomBackground,
        ],
        background: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: (_vendor.coverImageUrl != null &&
                      _vendor.coverImageUrl!.isNotEmpty)
                  ? _vendor.coverImageUrl!
                  : (_vendor.logoUrl ??
                      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?q=80&w=1000'),
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenteredHeader() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85), // More transparency for glass effect
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(40), // Softer corners
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(40),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // Stronger blur
            child: Column(
              children: [
                const SizedBox(height: 75),
                Text(
                  _vendor.name,
                  style: GoogleFonts.cairo(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          (_vendor.address != null && _vendor.address!.isNotEmpty)
                              ? _vendor.address!
                              : (_vendor.areaName ?? "عتيل - الشارع الرئيسي"),
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.location_on,
                          color: AppColors.primary, size: 14),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _handleRatingTap,
                          borderRadius: BorderRadius.circular(12),
                          child: _buildInfoItem(
                            icon: Icons.star,
                            iconColor: const Color(0xFFFFC107),
                            text: _vendor.rating.toStringAsFixed(1),
                            label: '(${_vendor.reviewCount}+)',
                          ),
                        ),
                      ),
                      Container(height: 40, width: 1, color: Colors.grey.withOpacity(0.2)),

                      // Delivery Info Item
                      Expanded(
                        flex: 2,
                        child: _vendor.hasDelivery
                            ? _buildInfoItem(
                                icon: Icons.delivery_dining,
                                iconColor: _vendor.isFreeDelivery
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF4AC3E1),
                                text: _vendor.isFreeDelivery
                                    ? 'مجاني'
                                    : '${_effectiveDeliveryFee.toInt()} ₪',
                                label: 'توصيل',
                              )
                            : _vendor.hasPickup
                                ? _buildInfoItem(
                                    icon: Icons.shopping_bag,
                                    iconColor: const Color(0xFF3B82F6),
                                    text: 'متاح',
                                    label: 'استلام',
                                  )
                                : const SizedBox(),
                      ),

                      Container(height: 40, width: 1, color: Colors.grey.withOpacity(0.2)),
                      Expanded(
                        child: _buildInfoItem(
                          icon: Icons.access_time,
                          iconColor: const Color(0xFF8DC63F),
                          text: _vendor.formattedEstimatedTime,
                          label: 'دقيقة',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_vendor.isBestSelling) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFFB300).withOpacity(0.15),
                          const Color(0xFFFF8C00).withOpacity(0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFFFB300).withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          size: 16,
                          color: Color(0xFFFF8C00),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "هذا المتجر من الأكثر مبيعاً حالياً",
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!_vendor.isFreeDelivery && _vendor.freeDeliveryThreshold != null && _vendor.freeDeliveryThreshold! > 0) ...[
                  const SizedBox(height: 12),
                  _buildFreeDeliveryPromotion(),
                ],
                const SizedBox(height: 20),
                // Work Hours Element & Status (With Pulse Glow)
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: _vendor.isOpen
                            ? const Color(0xFFF0FDF4).withOpacity(0.8)
                            : const Color(0xFFFEF2F2).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _vendor.isOpen
                              ? const Color(0xFFBBF7D0).withOpacity(
                                  0.5 + (_glowController.value * 0.5))
                              : const Color(0xFFFECACA),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _vendor.isOpen
                                ? Icons.check_circle
                                : Icons.do_not_disturb_on_outlined,
                            size: 16,
                            color: _vendor.isOpen
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _vendor.isOpen ? "مفتوح الآن" : "مغلق حالياً",
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _vendor.isOpen
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                              width: 1, height: 14, color: Colors.grey.withOpacity(0.3)),
                          const SizedBox(width: 12),
                          Text(
                            "يفتح ${_vendor.openingTime ?? '09:00'} - ${_vendor.closingTime ?? '23:00'}",
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                // Integrated Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9F9),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white,
                          radius: 18,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.share,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            onPressed: () async {
                              final String vendorId = _vendor.id;
                              final String vendorName = _vendor.name;
                              
                              // Create the deep link
                              // Using custom scheme for app-to-app and https for universal/web fallback
                              final String shareText = 
                                "اطلب الآن من متجر ($vendorName) عبر تطبيق طلبك!\n"
                                "https://talabakps.com/shop?id=$vendorId";
                              
                              await Share.share(shareText);
                            },
                          ),
                        ),
                        Row(
                          children: [
                            if (_vendor.hasPickup)
                              _serviceBadge(
                                Icons.shopping_bag_outlined,
                                const Color(0xFF3B82F6),
                              ),
                            if (_vendor.hasDelivery)
                              _serviceBadge(
                                _vendor.isFreeDelivery
                                    ? Icons.local_offer
                                    : Icons.directions_bike,
                                const Color(0xFF10B981),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required Color iconColor,
    required String text,
    required String label,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF2D2D2D),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildFreeDeliveryPromotion() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
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
            size: 16,
            color: Color(0xFF059669),
          ),
          const SizedBox(width: 8),
          Text(
            "توصيل مجاني للطلبات فوق ${_vendor.freeDeliveryThreshold!.toInt()} ₪",
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF065F46),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceBadge(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: color.withOpacity(0.8), size: 24),
          Positioned(
            right: -4,
            bottom: -4,
            child: Icon(Icons.check_circle, color: color, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSections() {
    return FutureBuilder<List<MenuCategory>>(
      future: _menuFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverFillRemaining(
            child: Center(
              child: SpinKitDoubleBounce(color: AppColors.primary, size: 50.0),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SliverFillRemaining(
            child: Center(child: Text("لا توجد منتجات حالياً")),
          );
        }
        final categories = snapshot.data!;
        
        if (widget.initialCategoryId != null && !_hasAutoScrolled) {
          _hasAutoScrolled = true;
          String targetId = widget.initialCategoryId!;
          if (targetId == 'trending') {
            try {
              final trendingCat = categories.firstWhere((c) => c.isTrending);
              targetId = trendingCat.id;
            } catch (e) {
              // Ignore if no trending
            }
          }
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Delay to allow SliverList to build item contexts
            Future.delayed(const Duration(milliseconds: 300), () {
              _scrollToCategory(targetId);
            });
          });
        }
        
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) =>
                _buildCategorySection(categories[index], categories),
            childCount: categories.length,
          ),
        );
      },
    );
  }

  Widget _buildCategorySection(
    MenuCategory cat,
    List<MenuCategory> allCategories,
  ) {
    if (cat.products.isEmpty) return const SizedBox.shrink();
    return Column(
      key: _categoryKeys[cat.id],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            // Back to default RTL: Name on Right, Button on Left
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: cat.isTrending
                    ? AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          return ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: [
                                  AppColors.primaryRed,
                                  AppColors.secondaryPurple,
                                  AppColors.primaryRed,
                                ],
                                stops: [
                                  _shimmerController.value - 0.3,
                                  _shimmerController.value,
                                  _shimmerController.value + 0.3,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                tileMode: TileMode.clamp,
                              ).createShader(
                                Rect.fromLTWH(
                                  0,
                                  0,
                                  bounds.width,
                                  bounds.height,
                                ),
                              );
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Text(
                                    cat.name,
                                    style: GoogleFonts.cairo(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFF8C00,
                                        ).withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "الأكثر طلباً",
                                        style: GoogleFonts.cairo(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.local_fire_department,
                                        color: Colors.white,
                                        size: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : Text(
                        cat.name,
                        style: GoogleFonts.cairo(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF2D2D2D), // Neutral but strong
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),

              // Show All Button (Left in RTL)
              TextButton(
                onPressed: () {
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
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new, // Arrow pointing left
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "عرض الكل",
                      style: GoogleFonts.cairo(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Stack(
          children: [
            SizedBox(
              height: 240,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: cat.products.length,
                itemBuilder: (context, index) =>
                    _buildProductCard(cat.products[index]),
              ),
            ),
            if (_showScrollHint && cat.products.length > 2)
              Positioned(
                left: 20,
                bottom: 100,
                child: AnimatedOpacity(
                  opacity: _showScrollHint ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chevron_left, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          "اسحب للمزيد",
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildStickyCategoryBar() {
    return FutureBuilder<List<MenuCategory>>(
      future: _menuFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final categories = snapshot.data!;
        return SliverPersistentHeader(
          pinned: true,
          delegate: CategoryHeaderDelegate(
            categories: categories,
            activeIndex: _activeCategoryIndex,
            onCategoryTap: (cat) {
              final key = _categoryKeys[cat.id];
              if (key != null && key.currentContext != null) {
                Scrollable.ensureVisible(
                  key.currentContext!,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                );
                setState(() {
                  _activeCategoryIndex = categories.indexOf(cat);
                });
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildProductCard(Product product) {
    return Container(
      width: 170,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () => _showProductDetails(product),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: product.imageUrl ??
                            'https://via.placeholder.com/150',
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 35,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.25),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Quick Add Button (Now shows details sheet)
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _showProductDetails(product),
                                borderRadius: BorderRadius.circular(10),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child:
                                      Icon(Icons.add, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ),
                          if (product.salePrice != null)
                            AnimatedDiscountBadge(
                              originalPrice: product.price,
                              salePrice: product.salePrice!,
                              primaryColor: AppColors.primary,
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "${product.price.toStringAsFixed(product.price % 1 == 0 ? 0 : 2)} ₪",
                                  style: GoogleFonts.cairo(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
              "${cart.items.length}",
              style: TextStyle(color: AppColors.primary, fontSize: 12),
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
            "${cart.totalPrice.toStringAsFixed(2)} ₪",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
                    // Refresh data if needed
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

class CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<MenuCategory> categories;
  final int activeIndex;
  final Function(MenuCategory) onCategoryTap;

  CategoryHeaderDelegate({
    required this.categories,
    required this.activeIndex,
    required this.onCategoryTap,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Colors.white,
      height: 60,
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              reverse: true, // RTL support
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isActive = index == activeIndex;
                return Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Center(
                    child: InkWell(
                      onTap: () => onCategoryTap(cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive
                                ? AppColors.primary
                                : Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          cat.name,
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isActive ? AppColors.primary : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 60;

  @override
  double get minExtent => 60;

  @override
  bool shouldRebuild(covariant CategoryHeaderDelegate oldDelegate) {
    return oldDelegate.categories != categories ||
        oldDelegate.activeIndex != activeIndex;
  }
}
