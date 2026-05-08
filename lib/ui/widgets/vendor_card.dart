import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class VendorCard extends StatelessWidget {
  final Vendor vendor;
  final bool isGrid;

  const VendorCard({super.key, required this.vendor, this.isGrid = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: vendor.isPremium
            ? Border.all(color: const Color(0xFFFFD700), width: 2)
            : null,
        boxShadow: [
          if (vendor.isPremium)
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 0),
            ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // COVER IMAGE
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Container(
                  height: isGrid ? 110 : 140,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: (vendor.coverImageUrl != null &&
                                vendor.coverImageUrl!.startsWith('http'))
                            ? Image.network(
                                vendor.coverImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildCoverPlaceholder(),
                              )
                            : _buildCoverPlaceholder(),
                      ),

                      // STRICTLY FIXED STATUS & MAGNET WRAP
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. LEFT SIDE: PREMIUM (Fixed Left)
                            if (vendor.isPremium)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                                  ),
                                  borderRadius: BorderRadius.all(Radius.circular(6)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_rounded, color: Colors.white, size: 10),
                                    SizedBox(width: 2),
                                    Text(
                                      "مميز",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(width: 8),

                            // 2. LEFT SIDE: FIXED STATUS & HIERARCHICAL MAGNET TAGS
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end, // Left edge in RTL
                                children: [
                                  Wrap(
                                    textDirection: TextDirection.ltr, // Ensures Status is the left anchor
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      // 1. STATUS BADGE (Fixed at the top-left edge)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: vendor.isOpen
                                              ? const Color(0xFF10B981).withOpacity(0.9)
                                              : const Color(0xFFEF4444).withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          vendor.isOpen ? "مفتوح" : "مغلق",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),

                                      // 2. NEW BADGE (Follows Status horizontally, or moves under it vertically)
                                      if (vendor.isNew)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.auto_awesome, color: Colors.white, size: 10),
                                              SizedBox(width: 4),
                                              Text(
                                                "جديد",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      // 3. BEST SELLING (Follows New horizontally, or moves under it vertically)
                                      if (vendor.isBestSelling)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFFFF9800), Color(0xFFF44336)],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.trending_up, color: Colors.white, size: 10),
                                              SizedBox(width: 4),
                                              Text(
                                                "الأكثر مبيعاً",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
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
                ),
              ),

              // INFO SECTION
              Padding(
                padding: EdgeInsets.fromLTRB(
                    8, isGrid ? 42 : 50, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // NAME
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vendor.name,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isGrid ? 11 : 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                                if (vendor.areaName != null)
                                  Text(
                                    vendor.areaName!,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: isGrid ? 9 : 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (vendor.isPremium) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.stars_rounded,
                              color: Color(0xFFFFD700),
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),

                    // INFO (WRAP)
                    FutureBuilder<Map<String, dynamic>>(
                      future: SupabaseService().getEffectiveDeliveryFeeInfo(
                        vendor.areaId, 
                        (vendor.useCustomDelivery ? (vendor.customDeliveryFee ?? vendor.deliveryFee) : vendor.deliveryFee).toDouble(),
                      ),
                      builder: (context, snapshot) {
                        final data = snapshot.data;
                        final double originalFee = (data?['originalFee'] ?? (vendor.useCustomDelivery ? (vendor.customDeliveryFee ?? vendor.deliveryFee) : vendor.deliveryFee)).toDouble();
                        final fee = (data?['fee'] ?? originalFee).toDouble();
                        final isDiscounted = data?['hasPromo'] ?? false;

                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (vendor.isFreeDelivery || (vendor.freeDeliveryThreshold != null && vendor.freeDeliveryThreshold! > 0))
                              _buildOldStyleInfoItem(
                                icon: Icons.auto_awesome,
                                label: vendor.isFreeDelivery 
                                    ? "توصيل مجاني" 
                                    : "عرض توصيل ",
                                color: const Color(0xFF8B5CF6),
                                iconColor: const Color(0xFFFFD700),
                              )
                            else
                              _buildOldStyleInfoItem(
                                icon: isDiscounted ? Icons.local_fire_department_rounded : Icons.directions_bike_rounded,
                                label: fee == 0 ? "مجاني" : "${fee.toInt()} ₪",
                                oldLabel: isDiscounted ? "${originalFee.toInt()} ₪" : null,
                                color: isDiscounted ? Colors.deepOrange : Colors.green[700]!,
                                iconColor: isDiscounted ? Colors.orange : Colors.redAccent,
                              ),
                            _buildClassicSeparator(),
                            _buildOldStyleInfoItem(
                              icon: Icons.access_time_rounded,
                              label: vendor.formattedEstimatedTime,
                              color: Colors.grey[700]!,
                            ),
                            _buildClassicSeparator(),
                            _buildOldStyleInfoItem(
                              icon: Icons.location_on_rounded,
                              label: vendor.areaName ?? vendor.address ?? "الموقع",
                              color: Colors.grey[700]!,
                            ),
                            _buildClassicSeparator(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "${vendor.rating}",
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 1),
                                const Icon(Icons.star_rounded,
                                    size: 13,
                                    color: Color(0xFFFFB300)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          // AVATAR
          Positioned(
            top: isGrid ? 80 : 108,
            right: 14,
            child: Container(
              height: isGrid ? 58 : 68,
              width: isGrid ? 58 : 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: (vendor.logoUrl != null &&
                        vendor.logoUrl!.startsWith('http'))
                    ? Image.network(vendor.logoUrl!, fit: BoxFit.cover)
                    : _buildLogoPlaceholder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- HELPERS ----------

  Widget _buildOldStyleInfoItem({
    required IconData icon,
    required String label,
    required Color color,
    Color? iconColor,
    String? oldLabel,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (oldLabel != null) ...[
          Text(
            oldLabel,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 9,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 3),
        Icon(icon, size: 12, color: iconColor ?? Colors.redAccent),
      ],
    );
  }

  Widget _buildClassicSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        height: 10,
        width: 1,
        color: Colors.grey[300],
      ),
    );
  }

  Widget _buildLogoPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: const Icon(Icons.restaurant, color: Colors.grey, size: 20),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey[200]!, Colors.grey[100]!],
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.grey, size: 24),
      ),
    );
  }
}