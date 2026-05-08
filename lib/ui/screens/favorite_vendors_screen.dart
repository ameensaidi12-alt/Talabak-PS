import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/models.dart';
import '../widgets/vendor_card.dart';
import 'vendor_detail_screen.dart';
import 'market_detail_screen.dart';
import '../../core/utils/vendor_navigation.dart';
import '../../core/theme/app_colors.dart';

class FavoriteVendorsScreen extends StatefulWidget {
  const FavoriteVendorsScreen({super.key});

  @override
  State<FavoriteVendorsScreen> createState() => _FavoriteVendorsScreenState();
}

class _FavoriteVendorsScreenState extends State<FavoriteVendorsScreen> {
  late Future<List<Vendor>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() {
    final supabase = Provider.of<SupabaseService>(context, listen: false);
    _favoritesFuture = _fetchFavorites(supabase);
  }

  Future<List<Vendor>> _fetchFavorites(SupabaseService supabase) async {
    final user = supabase.client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await supabase.client
          .from('favorite_vendors')
          .select('*, vendors(*, delivery_areas(name))')
          .eq('user_id', user.id);

      if (response is List) {
        return response.map((item) => Vendor.fromJson(item['vendors'])).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching favorites: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          "المفضلة",
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<List<Vendor>>(
        future: _favoritesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError ||
              !snapshot.hasData ||
              snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "لا يوجد متاجر في المفضلة بعد",
                    style: GoogleFonts.cairo(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final favorites = snapshot.data!;

          final double width = MediaQuery.of(context).size.width;
          final double cardWidth = (width - 32 - 12) / 2; // 32 is horizontal padding (16*2), 12 is spacing
          final double aspectRatio = cardWidth / 205;

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: aspectRatio,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final vendor = favorites[index];
              return InkWell(
                onTap: () async {
                  await VendorNavigation.navigateToVendor(context, vendor);
                  // Refresh on return in case favorite was removed
                  setState(() {
                    _loadFavorites();
                  });
                },
                child: VendorCard(vendor: vendor, isGrid: true),
              );
            },
          );
        },
      ),
    );
  }
}
