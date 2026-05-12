import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_support_screen.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String? orderId;
  final String? batchId;
  const OrderTrackingScreen({super.key, this.orderId, this.batchId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  String status = "جاري التحضير";
  double progress = 0.3;
  Timer? _timer;
  Map<String, dynamic>? latestOrder;
  List<Map<String, dynamic>> allOrders = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLatestOrder();
    // Poll for updates every 10 seconds to keep UI synced
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchLatestOrder();
    });
  }

  Future<void> _fetchLatestOrder() async {
    try {
      final client = SupabaseService().client;
      final user = client.auth.currentUser;
      if (user == null) return;

      List<Map<String, dynamic>> fetchedOrders = [];

      if (widget.batchId != null) {
        final response = await client
            .from('orders')
            .select('*, vendors(name, logo_url)')
            .eq('batch_id', widget.batchId!)
            .eq('source', 'mob_app')
            .order('created_at', ascending: false);
        if (response is List) fetchedOrders = List<Map<String, dynamic>>.from(response);
      } else if (widget.orderId != null) {
        final response = await client
            .from('orders')
            .select('*, vendors(name, logo_url)')
            .eq('id', widget.orderId!)
            .maybeSingle();
        
        if (response != null) {
          final order = Map<String, dynamic>.from(response);
          final bid = order['batch_id']?.toString();
          if (bid != null) {
            final batchResponse = await client
                .from('orders')
                .select('*, vendors(name, logo_url)')
                .eq('batch_id', bid)
                .order('created_at', ascending: false);
            if (batchResponse is List) fetchedOrders = List<Map<String, dynamic>>.from(batchResponse);
          } else {
            fetchedOrders = [order];
          }
        }
      } else {
        final response = await client
            .from('orders')
            .select('*, vendors(name, logo_url)')
            .eq('user_id', user.id)
            .eq('source', 'mob_app')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (response != null) {
          final order = Map<String, dynamic>.from(response);
          final bid = order['batch_id']?.toString();
          if (bid != null) {
             final batchResponse = await client.from('orders').select('*, vendors(name, logo_url)').eq('batch_id', bid);
             if (batchResponse is List) fetchedOrders = List<Map<String, dynamic>>.from(batchResponse);
          } else {
            fetchedOrders = [order];
          }
        }
      }

      if (mounted) {
        setState(() {
          allOrders = fetchedOrders;
          latestOrder = fetchedOrders.isNotEmpty ? fetchedOrders.first : null;
          loading = false;
          if (latestOrder != null) {
            // Use the "most active" status or the first one
            _syncStatus(latestOrder!['status']);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  String description = "نعمل على إيصال طلبك بأسرع وقت";
  Color statusColor = AppColors.primary;

  void _syncStatus(String dbStatus) {
    switch (dbStatus.toLowerCase()) {
      case 'pending':
        status = "انتظار التأكيد";
        description = "بانتظار موافقة المطعم على طلبك";
        progress = 0.15;
        statusColor = Colors.orange;
        break;
      case 'confirmed':
        status = "تم تأكيد الطلب";
        description = "المطعم استلم طلبك وسيبدأ التحضير";
        progress = 0.35;
        statusColor = Colors.cyan;
        break;
      case 'preparing':
        status = "جاري التحضير";
        description = "يتم الآن تجهيز وجبتك بكل حب";
        progress = 0.55;
        statusColor = Colors.blue;
        break;
      case 'out_for_delivery':
        status = "في الطريق إليك";
        description = "السائق استلم الطلب وهو يقترب منك";
        progress = 0.85;
        statusColor = Colors.purple;
        break;
      case 'delivered':
        status = "تم التسليم بنجاح";
        description = "نتمنى أن تستمتع بوجبتك الشهية";
        progress = 1.0;
        statusColor = Colors.green;
        break;
      case 'cancelled':
        status = "طلب ملغي";
        description = "نعتذر، لقد تم إلغاء الطلب";
        progress = 0.0;
        statusColor = Colors.red;
        break;
      default:
        status = dbStatus;
        description = "يتم تحديث الحالة...";
        progress = 0.1;
        statusColor = Colors.grey;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "تتبع الطلب",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : latestOrder == null
          ? _buildNoOrder()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildVendorInfo(),
                  const SizedBox(height: 20),
                  _buildOrderPrice(),
                  const SizedBox(height: 40),
                  _buildStatusCircle(),
                  const SizedBox(height: 30),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 50),
                  _buildTimeline(),
                  const SizedBox(height: 50),
                  _buildSupportTile(),
                ],
              ),
            ),
    );
  }

  Widget _buildOrderPrice() {
    double subtotal = 0;
    double deliveryFee = 0;
    double discount = 0;
    double total = 0;

    for (var order in allOrders) {
      subtotal += (order['subtotal'] ?? 0).toDouble();
      deliveryFee += (order['delivery_fee'] ?? 0).toDouble();
      discount += (order['points_discount'] ?? 0).toDouble();
      total += (order['total_price'] ?? 0).toDouble();
    }

    // If it's a batch, we might have a unified batch_total stored in the first order
    if (allOrders.length > 1 && allOrders.first['batch_total'] != null) {
      total = (allOrders.first['batch_total'] ?? 0).toDouble();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          _buildPriceRow("سعر الأصناف", "${subtotal.toStringAsFixed(1)} ₪"),
          const SizedBox(height: 8),
          _buildPriceRow("رسوم التوصيل", "${deliveryFee.toStringAsFixed(1)} ₪"),
          if (discount > 0) ...[
            const SizedBox(height: 8),
            _buildPriceRow("خصم النجوم", "- ${discount.toStringAsFixed(1)} ₪", isDiscount: true),
          ],
          const Divider(height: 24),
          _buildPriceRow("المجموع الكلي", "${total.toStringAsFixed(1)} ₪", isTotal: true),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isDiscount = false, bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 20 : 15,
            fontWeight: isTotal || isDiscount ? FontWeight.bold : FontWeight.w500,
            color: isTotal ? AppColors.primary : (isDiscount ? Colors.red : Colors.black87),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildNoOrder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delivery_dining_outlined,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 20),
          const Text(
            "لا يوجد طلب نشط حالياً",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorInfo() {
    final names = allOrders.map((o) => o['vendors']?['name'] ?? "").where((n) => n.isNotEmpty).join(" + ");
    return Row(
      children: [
        if (allOrders.length > 1)
          SizedBox(
            width: 60,
            height: 40,
            child: Stack(
              children: allOrders.take(3).toList().asMap().entries.map((entry) {
                return Positioned(
                  left: entry.key * 15.0,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    backgroundImage: entry.value['vendors']?['logo_url'] != null 
                        ? NetworkImage(entry.value['vendors']['logo_url']) 
                        : null,
                    child: entry.value['vendors']?['logo_url'] == null 
                        ? Icon(Icons.store, size: 14, color: AppColors.primary) 
                        : null,
                  ),
                );
              }).toList(),
            ),
          )
        else
          CircleAvatar(
            radius: 25,
            backgroundColor: Color(0xFFFDE8ED),
            child: latestOrder?['vendors']?['logo_url'] != null 
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: CachedNetworkImage(
                      imageUrl: latestOrder!['vendors']['logo_url'],
                      fit: BoxFit.cover,
                      width: 50,
                      height: 50,
                    ),
                  )
                : Icon(Icons.restaurant, color: AppColors.primary),
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                allOrders.length > 1 ? "طلب مجمع من:" : (latestOrder?['vendors']?['name'] ?? "المطعم"),
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              Text(
                allOrders.length > 1 ? names : (latestOrder?['vendors']?['name'] ?? ""),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
              Text(
                "رقم الطلب: #${latestOrder?['id']?.toString().substring(0, 8)}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCircle() {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          height: 180,
          width: 180,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 8,
            backgroundColor: Colors.grey[100],
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
        ),
        Icon(Icons.delivery_dining, size: 70, color: statusColor),
      ],
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: [
        _step("تم تأكيد الطلب", progress >= 0.35),
        _line(progress >= 0.55),
        _step("جاري تحضير الوجبة", progress >= 0.55),
        _line(progress >= 0.85),
        _step("السائق في الطريق", progress >= 0.85),
        _line(progress >= 1.0),
        _step("تم التسليم", progress >= 1.0),
      ],
    );
  }

  Widget _step(String title, bool active) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          title,
          style: TextStyle(
            color: active ? Colors.black : Colors.grey,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 20),
        CircleAvatar(
          radius: 6,
          backgroundColor: active ? statusColor : Colors.grey[300],
        ),
      ],
    );
  }

  Widget _line(bool active) {
    return Container(
      width: 2,
      height: 30,
      margin: const EdgeInsets.only(right: 5),
      color: active ? statusColor : Colors.grey[300],
    );
  }

  Widget _buildSupportTile() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatSupportScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 18),
            SizedBox(width: 10),
            Text(
              "تحتاج مساعدة؟ تواصل مع الدعم",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
