import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/services/supabase_service.dart';
import 'address_details_screen.dart';

enum AddressSelectionMode { gps, list, manual }

class AddressSelectionScreen extends StatefulWidget {
  final AddressSelectionMode mode;
  const AddressSelectionScreen(
      {super.key, this.mode = AddressSelectionMode.list});

  @override
  State<AddressSelectionScreen> createState() => _AddressSelectionScreenState();
}

class _AddressSelectionScreenState extends State<AddressSelectionScreen> {
  final _supabaseService = SupabaseService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == AddressSelectionMode.gps) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _getCurrentLocation());
    } else if (widget.mode == AddressSelectionMode.manual) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AddressDetailsScreen()),
        );
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    debugPrint("📍 [_getCurrentLocation] Started");
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint("📍 [_getCurrentLocation] Service Enabled: $serviceEnabled");
      if (!serviceEnabled) throw 'خدمات الموقع غير مفعلة في هاتفك';

      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint("📍 [_getCurrentLocation] Initial Permission: $permission");
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint("📍 [_getCurrentLocation] Requested Permission: $permission");
        if (permission == LocationPermission.denied)
          throw 'تم رفض إذن الوصول للموقع';
      }

      if (permission == LocationPermission.deniedForever)
        throw 'إذن الموقع مرفوض بشكل دائم، يرجى تفعيله من الإعدادات';

      debugPrint("📍 [_getCurrentLocation] Fetching position...");
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        debugPrint("📍 [_getCurrentLocation] High accuracy timeout/error, trying last known position...");
        position = await Geolocator.getLastKnownPosition();
      }
      
      if (position == null) {
        throw 'تعذر الحصول على الموقع، يرجى تفعيل الـ GPS والوقوف في مكان مكشوف.';
      }
      debugPrint("📍 [_getCurrentLocation] Position: ${position.latitude}, ${position.longitude}");

      String addressName = "موقع مجهول";
      String? areaId;

      // 1. Get Geocoded Info first to help identify the town
      List<String> possibleNames = [];
      try {
        debugPrint("📍 [_getCurrentLocation] Fetching geocoded names...");
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude).timeout(const Duration(seconds: 5));
        
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          
          // Use a safer way to access properties that might throw if internal package logic fails
          void addIfNotNull(String? value) {
            if (value != null && value.isNotEmpty) {
              possibleNames.add(value);
            }
          }

          try { addIfNotNull(place.locality); } catch(_) {}
          try { addIfNotNull(place.subLocality); } catch(_) {}
          try { addIfNotNull(place.administrativeArea); } catch(_) {}
          try { addIfNotNull(place.name); } catch(_) {}
          try { addIfNotNull(place.street); } catch(_) {}
          
          debugPrint("📍 [_getCurrentLocation] Possible names: $possibleNames");
        }
      } catch (e) {
        debugPrint("📍 [_getCurrentLocation] Geocoding warning: $e");
      }

      // 2. Get Nearest Service Area (with name priority)
      debugPrint("📍 [_getCurrentLocation] Fetching nearest area with name priority...");
      final nearestArea = await _supabaseService.getNearestArea(
          position.latitude, position.longitude, possibleNames: possibleNames);
      debugPrint("📍 [_getCurrentLocation] Nearest Area: ${nearestArea?['name']} (ID: ${nearestArea?['id']})");
      
      if (nearestArea != null) {
        addressName = nearestArea['name'];
        areaId = nearestArea['id'];
      }

      // Auto-save as default address and return to home
      final user = _supabaseService.client.auth.currentUser;
      debugPrint("📍 [_getCurrentLocation] Current User: ${user?.id}");
      
      // Always update AppState (in-memory) for instant UI feedback
      if (areaId != null) {
        debugPrint("📍 [_getCurrentLocation] Updating AppState...");
        await _supabaseService.saveGuestLocation(
            areaId, addressName, position.latitude, position.longitude);
      }

      if (user != null) {
        debugPrint("📍 [_getCurrentLocation] Saving User Address to DB...");
        await _supabaseService.saveUserAddress({
          'area_id': areaId,
          'address_line_1': addressName, // Area name
          'location': 'POINT(${position.longitude} ${position.latitude})',
          'is_default': true,
        });
      }

      if (mounted) {
        if (areaId != null) {
          debugPrint("📍 [_getCurrentLocation] Success, popping AddressSelectionScreen with true");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("تم تحديد موقعك وحفظه بنجاح"),
                backgroundColor: Colors.green),
          );
          // Navigate back to Home
          Navigator.pop(context, true);
        } else {
          debugPrint("📍 [_getCurrentLocation] Outside service area");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("عذراً، هذا الموقع خارج مناطق الخدمة حالياً"),
                backgroundColor: Color(0xFFD00030)),
          );
          if (widget.mode == AddressSelectionMode.gps) Navigator.pop(context);
        }
      }
    } catch (e, stack) {
      debugPrint("❌ [_getCurrentLocation] Error: $e");
      debugPrint("❌ [_getCurrentLocation] StackTrace: $stack");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFD00030)),
      );
      if (widget.mode == AddressSelectionMode.gps) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode != AddressSelectionMode.list || _loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFD00030)),
              SizedBox(height: 20),
              Text("جاري معالجة طلبك...",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("تفاصيل الموقع",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFFD00030)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildGpsButton(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("اختر منطقة",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text("اختاروا منطقة للمتابعة",
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildAreasList()),
        ],
      ),
    );
  }

  Widget _buildGpsButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _getCurrentLocation,
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location, color: Color(0xFFD00030)),
        label: const Text("استخدم موقعي الحالي",
            style:
                TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: Colors.grey.withOpacity(0.2)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildAreasList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _supabaseService.getDeliveryAreas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final areas = snapshot.data ?? [];

        return ListView.builder(
          itemCount: areas.length,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemBuilder: (context, index) {
            final area = areas[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.01), blurRadius: 10)
                ],
              ),
              child: ListTile(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddressDetailsScreen(
                          areaName: area['name'], areaId: area['id']),
                    ),
                  );
                  // If result is true, it means location was saved, so pop back to home
                  if (result == true && mounted) {
                    Navigator.pop(context, true);
                  }
                },
                leading: const Icon(Icons.arrow_back_ios,
                    size: 14, color: Color(0xFFD00030)),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.location_city, color: Colors.grey),
                ),
                title: Text(
                  area['name'],
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            );
          },
        );
      },
    );
  }

}
