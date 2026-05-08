import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import 'order_tracking_screen.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  Key _refreshKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          "طلباتي",
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<dynamic>>(
        key: _refreshKey,
        future: _fetchOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("خطأ: ${snapshot.error}"));
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return _buildEmptyState();
          }

          // Grouping logic
          final grouped = <String, List<Map<String, dynamic>>>{};
          for (var o in orders) {
            if (o is! Map) continue;
            final map = Map<String, dynamic>.from(o);
            final batchId = map['batch_id']?.toString();
            if (batchId != null) {
              grouped.putIfAbsent(batchId, () => []).add(map);
            }
          }

          final List<dynamic> displayList = [];
          final processedBatches = <String>{};

          for (var o in orders) {
            if (o is! Map) continue;
            final map = Map<String, dynamic>.from(o);
            final batchId = map['batch_id']?.toString();
            if (batchId == null) {
              displayList.add(map);
            } else if (!processedBatches.contains(batchId)) {
              displayList.add({'type': 'batch', 'items': grouped[batchId]});
              processedBatches.add(batchId);
            }
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              final item = displayList[index];
              if (item is Map && item['type'] == 'batch') {
                return _buildBatchOrderCard(context, List<Map<String, dynamic>>.from(item['items']));
              } else {
                return _buildOrderCard(context, Map<String, dynamic>.from(item));
              }
            },
          );
        },
      ),
    );
  }

  Future<List<dynamic>> _fetchOrders() async {
    final client = SupabaseService().client;
    final user = client.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await client
          .from('orders')
          .select(
            '*, vendors(name, logo_url, is_best_selling), order_items(*, products(name, image_url)), reviews(id)',
          )
          .eq('user_id', user.id)
          .eq('source', 'mob_app')
          .order('created_at', ascending: false);
      
      if (response is List) {
        return response;
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching orders: $e");
      return [];
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text(
            "لا توجد طلبات سابقة",
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  bool _isRated(dynamic reviews) {
    if (reviews == null) return false;
    if (reviews is List) return reviews.isNotEmpty;
    if (reviews is Map) return true; // Single object case from Supabase
    return false;
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return {
          'label': 'انتظار التأكيد',
          'color': Colors.orange,
          'bg': Colors.orange[50],
        };
      case 'confirmed':
        return {
          'label': 'تم التأكيد',
          'color': Colors.cyan,
          'bg': Colors.cyan[50],
        };
      case 'preparing':
        return {
          'label': 'جاري التحضير',
          'color': Colors.blue,
          'bg': Colors.blue[50],
        };
      case 'out_for_delivery':
        return {
          'label': 'في الطريق إليك',
          'color': Colors.purple,
          'bg': Colors.purple[50],
        };
      case 'delivered':
        return {
          'label': 'تم التسليم',
          'color': Colors.green,
          'bg': Colors.green[50],
        };
      case 'cancelled':
        return {'label': 'ملغي', 'color': Colors.red, 'bg': Colors.red[50]};
      default:
        return {'label': status, 'color': Colors.grey, 'bg': Colors.grey[50]};
    }
  }

  Widget _buildBatchOrderCard(BuildContext context, List<Map<String, dynamic>> orders) {
    final firstOrder = orders.first;
    final total = orders.fold(0.0, (sum, o) => sum + (double.tryParse(o['total_price'].toString()) ?? 0.0));
    final date = DateTime.parse(firstOrder['created_at']).toLocal();
    final vendorNames = orders.map((o) => o['vendors']?['name'] ?? '').join(' ، ');
    final statusInfo = _getStatusInfo(firstOrder['status']?.toString() ?? 'pending');
    final isPending = firstOrder['status']?.toString().toLowerCase() == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.1), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 48,
                child: Stack(
                  children: orders.take(3).toList().asMap().entries.map((entry) {
                    final idx = entry.key;
                    final logo = entry.value['vendors']?['logo_url'];
                    return Positioned(
                      left: idx * 15.0,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          image: logo != null ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover) : null,
                        ),
                        child: logo == null ? const Icon(Icons.store, size: 20, color: Colors.grey) : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "طلب مشترك (${orders.length} متاجر)",
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      vendorNames,
                      style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      "مجمّع",
                      style: GoogleFonts.cairo(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusInfo['bg'],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusInfo['label'],
                      style: GoogleFonts.cairo(
                        color: statusInfo['color'],
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "المجموع الكلي",
                    style: GoogleFonts.cairo(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    "${total.toStringAsFixed(2)} ₪",
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 22, color: AppColors.primary),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateFormat('yyyy-MM-dd').format(date),
                    style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  ElevatedButton(
                    onPressed: () => _showGroupedOrderDetails(context, orders),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFDE8ED),
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text("التفاصيل", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
          if (isPending && total == 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.orange[800]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "سعر التوصيل يتم تحديده بعد التأكيد الهاتفي للمجموعة",
                      style: GoogleFonts.cairo(fontSize: 10, color: Colors.orange[800], fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.local_shipping_outlined, size: 18, color: Colors.white),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(double.infinity, 45),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderTrackingScreen(orderId: firstOrder['id']),
                        ),
                      );
                    },
                    label: Text(
                      "تتبع الطلب",
                      style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              if (firstOrder['status']?.toString().toLowerCase() == 'delivered') ...[
                const SizedBox(width: 12),
                Builder(
                  builder: (context) {
                    final int totalToRate = orders.length;
                    final int ratedCount = orders.where((o) {
                      return _isRated(o['reviews']);
                    }).length;
                    
                    final bool fullyRated = ratedCount == totalToRate;
                    final bool partiallyRated = ratedCount > 0 && ratedCount < totalToRate;
                    
                    return Expanded(
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: fullyRated ? Colors.green.withOpacity(0.5) : AppColors.primary,
                            width: 1.5,
                          ),
                          color: fullyRated ? Colors.green.withOpacity(0.05) : Colors.transparent,
                        ),
                        child: ElevatedButton.icon(
                          icon: Icon(
                            fullyRated ? Icons.check_circle : (partiallyRated ? Icons.star_half : Icons.star_outline),
                            size: 18,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: fullyRated ? Colors.green[700] : AppColors.primary,
                            minimumSize: const Size(double.infinity, 45),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: fullyRated ? null : () => _showMultiVendorRatingSelection(context, orders),
                          label: Text(
                            fullyRated 
                              ? "تم التقييم بالكامل" 
                              : (partiallyRated ? "أكمل تقييم المتاجر" : "تقييم المتاجر"),
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  }
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order) {
    final statusInfo = _getStatusInfo(order['status']?.toString() ?? 'pending');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  image: order['vendors']?['logo_url'] != null
                      ? DecorationImage(
                          image: NetworkImage(order['vendors']['logo_url']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: order['vendors']?['logo_url'] == null
                    ? const Icon(Icons.store, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['vendors']?['name'] ?? "متجر غير معروف",
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: const Color(0xFF2D2D2D),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          DateFormat('yyyy-MM-dd hh:mm a').format(
                            DateTime.parse(order['created_at']).toLocal(),
                          ),
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "#${order['id'].toString().substring(0, 8)}",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusInfo['bg'],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusInfo['label'],
                  style: GoogleFonts.cairo(
                    color: statusInfo['color'],
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "${order['total_price'] is num ? (order['total_price'] as num).toStringAsFixed(2) : order['total_price']} ₪",
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      "إجمالي الطلب",
                      style: GoogleFonts.cairo(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 30, color: Colors.grey[300]),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE8ED),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: () => _showOrderDetails(context, order),
                  icon: Icon(Icons.visibility_outlined, color: AppColors.primary),
                  tooltip: "تفاصيل الطلب",
                ),
              ),
            ],
          ),
          if (order['status']?.toString().toLowerCase() == 'pending' && (double.tryParse(order['delivery_fee']?.toString() ?? '0') ?? 0) == 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFFFD700)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "عرض توصيل مجاني🎁🎊",
                      style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(double.infinity, 45),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderTrackingScreen(orderId: order['id']),
                        ),
                      );
                    },
                    child: Text(
                      "تتبع الطلب",
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              if (order['status']?.toString().toLowerCase() == 'delivered') ...[
                const SizedBox(width: 12),
                Builder(
                  builder: (context) {
                    final bool hasBeenRated = _isRated(order['reviews']);
                    
                    return Expanded(
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasBeenRated ? Colors.green.withOpacity(0.5) : AppColors.primary,
                            width: 1.5,
                          ),
                          color: hasBeenRated ? Colors.green.withOpacity(0.05) : Colors.transparent,
                        ),
                        child: ElevatedButton.icon(
                          icon: hasBeenRated ? const Icon(Icons.check_circle, size: 18) : const Icon(Icons.star_outline, size: 18),
                          label: Text(
                            hasBeenRated ? "تم التقييم بنجاح" : "تقييم الطلب",
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: hasBeenRated ? Colors.green[700] : AppColors.primary,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: hasBeenRated
                              ? null
                              : () => _showRatingDialog(context, order),
                        ),
                      ),
                    );
                  }
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
    _showDetailsModal(context, [order], order['vendors']?['name'] ?? "تفاصيل الطلب");
  }

  void _showGroupedOrderDetails(BuildContext context, List<Map<String, dynamic>> orders) {
    _showDetailsModal(context, orders, "تفاصيل الطلب المشترك");
  }

  void _showDetailsModal(BuildContext context, List<Map<String, dynamic>> orders, String title) {
    final grandTotal = orders.fold(0.0, (sum, o) => sum + (double.tryParse(o['total_price'].toString()) ?? 0.0));
    final subtotalTotal = orders.fold(0.0, (sum, o) => sum + (double.tryParse(o['subtotal'].toString()) ?? 0.0));
    final anyPending = orders.any((o) => o['status']?.toString().toLowerCase() == 'pending');
    final deliveryTotal = orders.fold(0.0, (sum, o) => sum + (double.tryParse(o['delivery_fee'].toString()) ?? 0.0));
    final discountTotal = orders.fold(0.0, (sum, o) => sum + (double.tryParse(o['points_discount']?.toString() ?? '0') ?? 0.0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text(title, style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(height: 32),
              Expanded(
                child: ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, vIdx) {
                    final order = orders[vIdx];
                    final rawItems = order['order_items'];
                    final items = rawItems is List ? rawItems : [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Icon(Icons.store, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  order['vendors']?['name'] ?? "متجر",
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (order['status']?.toString().toLowerCase() == 'delivered')
                                Builder(
                                  builder: (context) {
                                    final bool hasBeenRated = _isRated(order['reviews']);
                                    
                                    return TextButton(
                                      onPressed: hasBeenRated
                                          ? null
                                          : () {
                                              Navigator.pop(context); // Close modal
                                              _showRatingDialog(context, order);
                                            },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        backgroundColor: hasBeenRated
                                            ? Colors.green.withOpacity(0.1)
                                            : AppColors.primary.withOpacity(0.1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (hasBeenRated) 
                                            const Padding(
                                              padding: EdgeInsets.only(left: 4.0),
                                              child: Icon(Icons.check, size: 12, color: Colors.green),
                                            ),
                                          Text(
                                            hasBeenRated ? "تم التقييم" : "تقييم",
                                            style: GoogleFonts.cairo(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: hasBeenRated ? Colors.green : AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                ),
                              const SizedBox(width: 8),
                              Text("#${order['id'].toString().substring(0, 8)}", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...items.map((item) {
                          final prod = item['products'];
                          final price = item['price_at_time'] ?? 0;
                          final qty = item['quantity'] ?? 1;
                          final rawOptions = item['selected_options'];
                          final selectedOptions = rawOptions is List ? rawOptions : [];

                          // Calculate Base Price (product price alone)
                          double totalOptionsCostPerUnit = 0;
                          for (var rawOpt in selectedOptions) {
                            if (rawOpt is Map) {
                              final opt = Map<String, dynamic>.from(rawOpt);
                              final valueMap = opt['value'] is Map ? Map<String, dynamic>.from(opt['value'] as Map) : null;
                              double optPrice = double.tryParse((opt['price_modifier'] ?? valueMap?['price_modifier'] ?? 0).toString()) ?? 0;
                              int q = int.tryParse(opt['quantity']?.toString() ?? '1') ?? 1;
                              totalOptionsCostPerUnit += (optPrice * q);
                            }
                          }
                          double basePrice = (price is num ? price.toDouble() : 0.0) - totalOptionsCostPerUnit;
                          if (basePrice < 0) basePrice = (price is num ? price.toDouble() : 0.0);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.grey[100]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 55,
                                        height: 55,
                                        color: Colors.grey[50],
                                        child: (prod?['image_url'] != null && prod!['image_url'].toString().isNotEmpty)
                                            ? Image.network(
                                                prod['image_url'],
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const Icon(Icons.fastfood, color: Colors.grey, size: 20),
                                              )
                                            : const Icon(Icons.fastfood, color: Colors.grey, size: 20),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['name']?.toString() ?? prod?['name']?.toString() ?? "منتج",
                                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          Text(
                                            "السعر الأساسي: ${basePrice.toStringAsFixed(2)} ₪",
                                            style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[600]),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              "الكمية: $qty",
                                              style: GoogleFonts.cairo(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${((price is num ? price.toDouble() : 0.0) * (qty is num ? qty.toDouble() : 1.0)).toStringAsFixed(2)} ₪",
                                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
                                    ),
                                  ],
                                ),
                                if (selectedOptions.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Divider(height: 1, thickness: 0.5),
                                  ),
                                  ...selectedOptions.map((rawOpt) {
                                    String name = "";
                                    int q = 1;
                                    double optPrice = 0;

                                    if (rawOpt is String) {
                                      name = rawOpt;
                                    } else if (rawOpt is Map) {
                                      final opt = Map<String, dynamic>.from(rawOpt);
                                      final valueMap = opt['value'] is Map ? Map<String, dynamic>.from(opt['value'] as Map) : null;
                                      
                                      name = (opt['name']?.toString()) ?? (valueMap?['name']?.toString()) ?? "إضافة";
                                      q = int.tryParse(opt['quantity']?.toString() ?? '1') ?? 1;
                                      optPrice = double.tryParse((opt['price_modifier'] ?? valueMap?['price_modifier'] ?? 0).toString()) ?? 0;
                                    }

                                    if (name.isEmpty) return const SizedBox.shrink();
                                    
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Icon(Icons.add_circle_outline, size: 12, color: AppColors.primary.withOpacity(0.5)),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    name,
                                                    style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (q > 1) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[200],
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      "×$q",
                                                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (optPrice > 0)
                                            Text(
                                              "+ ${(optPrice * q).toStringAsFixed(2)} ₪",
                                              style: GoogleFonts.cairo(
                                                fontSize: 11,
                                                color: Colors.green[700],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                                if (item['notes'] != null && item['notes'].toString().isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.edit_note_rounded, size: 14, color: Colors.orange[800]),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            "ملاحظة: ${item['notes']}",
                                            style: GoogleFonts.cairo(
                                              fontSize: 10,
                                              color: Colors.orange[900],
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _buildSummaryRow("المجموع الفرعي", "${subtotalTotal.toStringAsFixed(2)} ₪"),
              const SizedBox(height: 8),
              _buildSummaryRow(
                "سعر التوصيل", 
                deliveryTotal == 0 ? "عرض توصيل مجاني✨" : "${deliveryTotal.toStringAsFixed(2)} ₪",
                color: deliveryTotal == 0 ? const Color(0xFF8B5CF6) : (anyPending ? Colors.orange[800] : null),
                fontSize: deliveryTotal == 0 ? 14 : (anyPending ? 12 : 14),
              ),
              if (discountTotal > 0) ...[
                const SizedBox(height: 8),
                _buildSummaryRow("خصم النجوم", "- ${discountTotal.toStringAsFixed(2)} ₪", color: Colors.green),
              ],
              const Divider(height: 16),
               _buildSummaryRow("الإجمالي الكلي", "${grandTotal.toStringAsFixed(2)} ₪", isBold: true, color: AppColors.primary, fontSize: 20),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showRatingDialog(BuildContext context, Map<String, dynamic> order) {
    int selectedRating = 0;
    final TextEditingController commentController = TextEditingController();
    final supabase = SupabaseService();

    // Safety check: Don't allow if already rated
    if (_isRated(order['reviews'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("هذا الطلب تم تقييمه بالفعل", style: GoogleFonts.cairo(), textAlign: TextAlign.right),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "تقييم طلبك",
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "كيف كانت تجربتك مع ${order['vendors']?['name']}؟",
                style: GoogleFonts.cairo(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    onPressed: () =>
                        setModalState(() => selectedRating = index + 1),
                    icon: Icon(
                      index < selectedRating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFFFC107),
                      size: 40,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: commentController,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: "أضف تعليقاً (اختياري)",
                  hintStyle: GoogleFonts.cairo(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: selectedRating == 0
                      ? null
                      : () async {
                          try {
                            await supabase.submitRating(
                              vendorId: order['vendor_id'],
                              orderId: order['id'],
                              rating: selectedRating,
                              comment: commentController.text,
                            );
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "شكراً لتقييمك!",
                                    style: GoogleFonts.cairo(),
                                    textAlign: TextAlign.right,
                                  ),
                                  backgroundColor: const Color(0xFF10B981),
                                ),
                              );
                                setState(() {
                                  _refreshKey = UniqueKey();
                                });
                              }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "فشل إرسال التقييم: $e",
                                  style: GoogleFonts.cairo(),
                                  textAlign: TextAlign.right,
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    "إرسال التقييم",
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMultiVendorRatingSelection(BuildContext context, List<Map<String, dynamic>> orders) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "تقييم المتاجر",
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Text(
                "يرجى اختيار المتجر الذي ترغب في تقييمه من هذا الطلب",
                style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final vendor = order['vendors'];
                    final bool hasBeenRated = _isRated(order['reviews']);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: hasBeenRated ? Colors.green.withOpacity(0.3) : Colors.grey[200]!,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            image: vendor?['logo_url'] != null
                                ? DecorationImage(
                                    image: NetworkImage(vendor['logo_url']),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: vendor?['logo_url'] == null
                              ? const Icon(Icons.store, color: Colors.grey)
                              : null,
                        ),
                        title: Row(
                          children: [
                            Text(
                              vendor?['name'] ?? "متجر",
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                            if (vendor?['is_best_selling'] == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber[100],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.stars_rounded, size: 10, color: Colors.amber),
                                    const SizedBox(width: 2),
                                    Text(
                                      "الأكثر مبيعاً",
                                      style: GoogleFonts.cairo(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber[900],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          hasBeenRated ? "تم التقييم بنجاح" : "لم يتم التقييم بعد",
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: hasBeenRated ? Colors.green : Colors.grey,
                          ),
                        ),
                        trailing: Container(
                          decoration: BoxDecoration(
                            color: hasBeenRated ? Colors.green.withOpacity(0.1) : AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Icon(
                            hasBeenRated ? Icons.check : Icons.chevron_left,
                            color: hasBeenRated ? Colors.green : AppColors.primary,
                            size: 20,
                          ),
                        ),
                        onTap: hasBeenRated
                            ? null
                            : () {
                                Navigator.pop(context);
                                _showRatingDialog(context, order);
                              },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isBold = false, Color? color, double fontSize = 14}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.cairo(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: fontSize)),
        Text(value,
            style: GoogleFonts.cairo(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: fontSize,
                color: color)),
      ],
    );
  }
}

