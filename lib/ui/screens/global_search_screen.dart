import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../widgets/vendor_card.dart';
import 'vendor_detail_screen.dart';
import 'market_detail_screen.dart';
import '../../core/utils/vendor_navigation.dart';

class GlobalSearchScreen extends StatefulWidget {
  final String? areaId;
  const GlobalSearchScreen({super.key, this.areaId});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _selectedType = 'all'; // 'all', 'restaurant', 'supermarket'
  List<Vendor> _results = [];
  bool _isLoading = false;
  late SupabaseService _supabaseService;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _supabaseService = Provider.of<SupabaseService>(context, listen: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    final vendors = await _supabaseService.getVendorsFiltered(
      searchQuery: query,
      type: _selectedType,
      areaId: widget.areaId,
    );

    if (mounted) {
      setState(() {
        _results = vendors;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 80,
        automaticallyImplyLeading: false,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.arrow_back_ios,
                    color: AppColors.primary,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      textAlign: TextAlign.right,
                      onChanged: _onSearch,
                      style: GoogleFonts.cairo(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: "ابحث عن مطعم أو ماركت...",
                        hintStyle: GoogleFonts.cairo(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearch("");
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _searchController.text.isEmpty
                ? _buildInitialState()
                : _results.isEmpty
                ? _buildEmptyState()
                : _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 60,
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // RTL support
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _filterChip(
              label: "ماركت",
              value: "supermarket",
              icon: Icons.shopping_basket,
            ),
            const SizedBox(width: 8),
            _filterChip(
              label: "مطاعم",
              value: "restaurant",
              icon: Icons.restaurant,
            ),
            const SizedBox(width: 8),
            _filterChip(
              label: "الكل",
              value: "all",
              icon: Icons.grid_view_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final bool isSelected = _selectedType == value;
    return InkWell(
      onTap: () {
        setState(() => _selectedType = value);
        _onSearch(_searchController.text);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.cairo(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey[500],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            "ابدأ بالبحث عن محلك المفضل",
            style: GoogleFonts.cairo(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            "لم نجد نتائج مطابقة لبحثك",
            style: GoogleFonts.cairo(
              color: Colors.grey[600],
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "تأكد من كتابة الاسم بشكل صحيح أو جرب فلتر آخر",
            style: GoogleFonts.cairo(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    final double width = MediaQuery.of(context).size.width;
    // Assuming 2 columns as per crossAxisCount: 2
    final double cardWidth = (width - 32 - 12) / 2; 
    final double aspectRatio = cardWidth / 235;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: aspectRatio,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final vendor = _results[index];
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
}
