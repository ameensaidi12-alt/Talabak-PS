import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/vendor_navigation.dart';

class LeaderboardScreen extends StatefulWidget {
  final String? areaId;
  const LeaderboardScreen({super.key, this.areaId});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _types = ['all', 'restaurant', 'supermarket'];
  final List<String> _typeLabels = ['الكل', 'المطاعم', 'الماركات'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _types.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          "أوسمة الأفضل",
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          tabs: _typeLabels.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _types.map((type) => _LeaderboardList(type: type, areaId: widget.areaId)).toList(),
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  final String type;
  final String? areaId;
  const _LeaderboardList({required this.type, this.areaId});

  @override
  Widget build(BuildContext context) {
    final supabase = Provider.of<SupabaseService>(context, listen: false);

    return FutureBuilder<List<Vendor>>(
      future: supabase.getTopRatedVendors(
        type: type == 'all' ? null : type,
        areaId: areaId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("خطأ في تحميل البيانات: ${snapshot.error}"));
        }
        final vendors = snapshot.data ?? [];
        if (vendors.isEmpty) {
          return const Center(child: Text("لا يوجد تقييمات حالياً"));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: vendors.length,
          itemBuilder: (context, index) {
            final vendor = vendors[index];
            return _LeaderboardItem(vendor: vendor, rank: index + 1);
          },
        );
      },
    );
  }
}

class _LeaderboardItem extends StatelessWidget {
  final Vendor vendor;
  final int rank;

  const _LeaderboardItem({required this.vendor, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => VendorNavigation.navigateToVendor(context, vendor),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Rank Badge
              _buildRankBadge(rank),
              const SizedBox(width: 12),
              // Vendor Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  vendor.logoUrl ?? 'https://via.placeholder.com/150',
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 60,
                    height: 60,
                    color: Colors.grey[200],
                    child: const Icon(Icons.store),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          vendor.rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "(${vendor.reviewCount} تقييم)",
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action Icon
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank <= 3) {
      String icon = rank == 1 ? "🥇" : (rank == 2 ? "🥈" : "🥉");
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: rank == 1 ? Colors.amber.withOpacity(0.1) : (rank == 2 ? Colors.grey[200] : Colors.orange.withOpacity(0.1)),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            icon,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          "#$rank",
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
      ),
    );
  }
}
