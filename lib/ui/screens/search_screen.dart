import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../widgets/vendor_card.dart';
import '../widgets/product_bottom_sheet.dart';
import '../../core/utils/vendor_navigation.dart';
import 'vendor_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? areaId;
  const SearchScreen({super.key, required this.areaId});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _supabaseService = SupabaseService();
  final _searchController = TextEditingController();
  late TabController _tabController;
  List<Vendor> _vendorResults = [];
  List<Product> _productResults = [];
  List<Map<String, dynamic>> _areas = [];
  String? _selectedAreaId;
  bool _searching = false;
  bool _loadingAreas = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedAreaId = widget.areaId;
    _fetchAreas();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _fetchAreas() async {
    final areas = await _supabaseService.getDeliveryAreas();
    if (mounted) {
      setState(() {
        _areas = areas;
        _loadingAreas = false;
      });
    }
  }

  void _onSearch(String query) async {
    if (query.isEmpty && _searchController.text.isEmpty) {
      if (mounted)
        setState(() {
          _vendorResults = [];
          _productResults = [];
        });
      return;
    }

    setState(() => _searching = true);
    try {
      final vendors = await _supabaseService.getVendors(
        areaId: _selectedAreaId,
        searchQuery: _searchController.text,
      );

      final products = await _supabaseService.searchProducts(
        areaId: _selectedAreaId,
        query: _searchController.text,
      );

      if (mounted) {
        setState(() {
          _vendorResults = vendors;
          _productResults = products;
          _searching = false;
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Container(
          height: 45,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearch,
            autofocus: true,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              hintText: "ابحث عن مطعم أو محل...",
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildAreaSelector(),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: "المحلات"),
              Tab(text: "المنتجات"),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildVendorsList(), _buildProductsList()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorsList() {
    if (_searching) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_vendorResults.isEmpty && _searchController.text.isNotEmpty) {
      return _buildEmptyState();
    }
    
    final double width = MediaQuery.of(context).size.width;
    final double cardWidth = (width - 32 - 12) / 2; // 32 is horizontal padding (16*2), 12 is spacing
    final double aspectRatio = cardWidth / 205;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: aspectRatio,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: _vendorResults.length,
      itemBuilder: (context, index) {
        final vendor = _vendorResults[index];
        return InkWell(
          onTap: () => VendorNavigation.navigateToVendor(context, vendor),
          child: VendorCard(
            vendor: vendor, 
            isGrid: true,
          ),
        );
      },
    );
  }

  Widget _buildProductsList() {
    if (_searching) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_productResults.isEmpty && _searchController.text.isNotEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _productResults.length,
      itemBuilder: (context, index) {
        final product = _productResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                product.imageUrl ?? '',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey[200],
                  child: iconError(),
                ),
              ),
            ),
            title: Text(
              product.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.salePrice != null)
                  Text(
                    "${product.price} ₪",
                    style: TextStyle(
                      color: Colors.grey,
                      decoration: TextDecoration.lineThrough,
                      fontSize: 12,
                    ),
                  ),
                Text(
                  "${product.salePrice ?? product.price} ₪",
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _showProductDetails(product),
          ),
        );
      },
    );
  }

  Widget iconError() => const Icon(Icons.fastfood, color: Colors.grey);

  void _showProductDetails(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          ProductBottomSheet(product: product, vendorName: "بحث"),
    );
  }

  Widget _buildAreaSelector() {
    if (_loadingAreas) return const SizedBox(height: 50);
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _areas.length + 1,
        itemBuilder: (context, index) {
          final bool isAll = index == 0;
          final area = isAll ? null : _areas[index - 1];
          final String? areaId = isAll ? null : area!['id'];
          final String areaName = isAll ? 'الكل' : area!['name'];
          final bool isSelected = _selectedAreaId == areaId;

          return Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: ChoiceChip(
              label: Text(
                areaName,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedAreaId = areaId;
                  });
                  _onSearch(_searchController.text);
                }
              },
              selectedColor: AppColors.primary,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : Colors.grey[300]!,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            "لم نجد أي نتائج لبحثك",
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
