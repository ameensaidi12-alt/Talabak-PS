import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import '../../core/theme/app_colors.dart';
import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import 'address_selection_screen.dart';
import '../../core/utils/vendor_navigation.dart';
import 'package:geolocator/geolocator.dart';

class VendorsMapScreen extends StatefulWidget {
  final String? areaId;
  final bool isSelectionMode;
  const VendorsMapScreen({
    super.key,
    this.areaId,
    this.isSelectionMode = false,
  });

  @override
  State<VendorsMapScreen> createState() => _VendorsMapScreenState();
}

class _VendorsMapScreenState extends State<VendorsMapScreen> {
  final _supabaseService = SupabaseService();
  final Set<gmaps.Marker> _markers = {};
  final Set<gmaps.Circle> _circles = {};
  gmaps.GoogleMapController? _mapController;
  List<Vendor> _vendors = [];
  bool _isLoading = true;
  bool _markersCreated = false;
  Vendor? _selectedVendor;

  @override
  void initState() {
    super.initState();
    _fetchVendors();

    if (widget.isSelectionMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAddressSelectionSheet();
      });
    }
  }

  Future<void> _fetchVendors() async {
    try {
      final vendors = await _supabaseService.getVendors(areaId: widget.areaId);
      if (!mounted) return;
      setState(() {
        _vendors = vendors
            .where((v) => v.latitude != null && v.longitude != null)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching vendors for map: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createMarkers() async {
    gmaps.BitmapDescriptor customIcon;
    gmaps.BitmapDescriptor mainAreaIcon;
    gmaps.BitmapDescriptor subAreaIcon;
    
    try {
      customIcon = await gmaps.BitmapDescriptor.asset(
        createLocalImageConfiguration(context, size: const Size(120, 120)),
        'assets/images/store_pin.png',
      );
      mainAreaIcon = await gmaps.BitmapDescriptor.asset(
        createLocalImageConfiguration(context, size: const Size(140, 140)),
        'assets/images/app_icon_pin.png',
      );
      subAreaIcon = await gmaps.BitmapDescriptor.asset(
        createLocalImageConfiguration(context, size: const Size(90, 90)),
        'assets/images/sub_area_pin_gold.png',
      );
    } catch (e) {
      debugPrint("⚠️ Error loading custom icons: $e");
      customIcon = gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRed);
      mainAreaIcon = gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueRose);
      subAreaIcon = gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueYellow);
    }

    final areas = await _supabaseService.getDeliveryAreas();

    setState(() {
      _markers.clear();
      _circles.clear();

      // 1. Add Service Area markers & Circles
      for (final area in areas) {
        if (area['location'] != null) {
          final lat = _parseLat(area['location']);
          final lng = _parseLng(area['location']);
          final position = gmaps.LatLng(lat, lng);
          final bool isSubArea = area['parent_id'] != null;

          // HIDE Sub-Areas (Villages) from map to keep it clean.
          if (isSubArea) continue;

          _markers.add(
            gmaps.Marker(
              markerId: gmaps.MarkerId("area_${area['id']}"),
              position: position,
              infoWindow: gmaps.InfoWindow(
                title: area['name'],
                snippet: "اضغط لتحديد موقعك هنا",
              ),
              icon: mainAreaIcon,
              onTap: () => _selectAreaAndGoHome(area),
            ),
          );

          _circles.add(
            gmaps.Circle(
              circleId: gmaps.CircleId("circle_${area['id']}"),
              center: position,
              radius: 1200, 
              fillColor: AppColors.primary.withOpacity(0.1),
              strokeColor: AppColors.primary.withOpacity(0.3),
              strokeWidth: 1,
            ),
          );
        }
      }

      // 2. Add Vendor markers
      for (final vendor in _vendors) {
        _markers.add(
          gmaps.Marker(
            markerId: gmaps.MarkerId(vendor.id),
            position: gmaps.LatLng(vendor.latitude!, vendor.longitude!),
            infoWindow: gmaps.InfoWindow(
              title: vendor.name,
              snippet: "اضغط للمزيد",
            ),
            onTap: () {
              setState(() => _selectedVendor = vendor);
              _mapController?.animateCamera(
                gmaps.CameraUpdate.newLatLng(
                  gmaps.LatLng(vendor.latitude! - 0.005, vendor.longitude!),
                ),
              );
            },
            icon: customIcon,
          ),
        );
      }
    });

    if (_mapController != null && (_vendors.isNotEmpty || areas.isNotEmpty)) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _fitBoundsToAll(areas);
        }
      });
    }
  }

  Future<void> _selectAreaAndGoHome(Map<String, dynamic> area) async {
    debugPrint("🗺️ [VendorsMapScreen] _selectAreaAndGoHome: ${area['name']}");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      // Check for sub-areas (villages) under this main area
      final allAreas = await _supabaseService.getDeliveryAreas();
      final children = allAreas.where((a) => a['parent_id'] == area['id']).toList();

      if (children.isNotEmpty) {
        Navigator.pop(context); // Pop loading dialog
        _showSubAreaSelectionSheet(area, children);
        return;
      }

      // No children: Assign directly
      final lat = _parseLat(area['location']);
      final lng = _parseLng(area['location']);
      final user = _supabaseService.client.auth.currentUser;

      // Always save to AppState (in-memory) for instant UI feedback
      await _supabaseService.saveGuestLocation(
        area['id'],
        area['name'],
        lat,
        lng,
      );

      if (user != null) {
        // AUTH MODE: Also save to permanent DB
        debugPrint("🗺️ [VendorsMapScreen] Saving Auth Address Draft...");
        await _supabaseService.saveAddressDraft(area['name'], lat, lng);
        debugPrint("🗺️ [VendorsMapScreen] Finalizing Auth Address...");
        await _supabaseService.finalizeAddress("Auto-Selected", "Ground");
      }

      if (mounted) {
        debugPrint("🗺️ [VendorsMapScreen] Success, popping both Map and Dialog with true");
        Navigator.pop(context); // Pop dialog
        Navigator.pop(context, true); // Return to Home

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("تم تحديث موقعك إلى: ${area['name']}"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stack) {
      if (mounted) Navigator.pop(context); // Pop dialog
      debugPrint("❌ [VendorsMapScreen] Area selection error: $e");
      debugPrint("❌ [VendorsMapScreen] StackTrace: $stack");
    }
  }

  gmaps.LatLng? _parseWKBLocation(dynamic loc) {
    if (loc == null) return null;
    try {
      String hexString = loc.toString();
      hexString = hexString.replaceAll(RegExp(r'\s+'), '').replaceAll('0x', '');

      if (hexString.length < 42) return null;

      String lngHex = hexString.substring(18, 34);
      String latHex = hexString.substring(34, 50);

      double lng = _hexToDouble(lngHex);
      double lat = _hexToDouble(latHex);

      if (lat.abs() > 90 || lng.abs() > 180) return null;
      return gmaps.LatLng(lat, lng);
    } catch (e) {
      return null;
    }
  }

  double _hexToDouble(String hex) {
    String reversed = '';
    for (int i = hex.length - 2; i >= 0; i -= 2) {
      reversed += hex.substring(i, i + 2);
    }
    int intValue = int.parse(reversed, radix: 16);
    var bytes = ByteData(8);
    bytes.setUint64(0, intValue, Endian.big);
    return bytes.getFloat64(0, Endian.big);
  }

  double _parseLat(dynamic loc) => _parseWKBLocation(loc)?.latitude ?? 32.2211;
  double _parseLng(dynamic loc) => _parseWKBLocation(loc)?.longitude ?? 35.2544;

  void _fitBoundsToAll(List<Map<String, dynamic>> areas) {
    if (_vendors.isEmpty && areas.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;

    for (var v in _vendors) {
      if (v.latitude != null && v.longitude != null) {
        minLat = minLat == null
            ? v.latitude!
            : (v.latitude! < minLat ? v.latitude! : minLat);
        maxLat = maxLat == null
            ? v.latitude!
            : (v.latitude! > maxLat ? v.latitude! : maxLat);
        minLng = minLng == null
            ? v.longitude!
            : (v.longitude! < minLng ? v.longitude! : minLng);
        maxLng = maxLng == null
            ? v.longitude!
            : (v.longitude! > maxLng ? v.longitude! : maxLng);
      }
    }

    for (var area in areas) {
      if (area['location'] != null) {
        final lat = _parseLat(area['location']);
        final lng = _parseLng(area['location']);
        minLat = minLat == null ? lat : (lat < minLat ? lat : minLat);
        maxLat = maxLat == null ? lat : (lat > maxLat ? lat : maxLat);
        minLng = minLng == null ? lng : (lng < minLng ? lng : minLng);
        maxLng = maxLng == null ? lng : (lng > maxLng ? lng : maxLng);
      }
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final bounds = gmaps.LatLngBounds(
        southwest: gmaps.LatLng(minLat, minLng),
        northeast: gmaps.LatLng(maxLat, maxLng),
      );
      _mapController?.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(bounds, 80),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "خريطة المحلات",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Builder(
                  builder: (context) {
                    final shouldShowFallback =
                        !Platform.isAndroid && !Platform.isIOS;
                    if (shouldShowFallback) {
                      return _buildWindowsFallback();
                    } else {
                      return gmaps.GoogleMap(
                        initialCameraPosition: const gmaps.CameraPosition(
                          target: gmaps.LatLng(32.2211, 35.2544),
                          zoom: 12,
                        ),
                        markers: _markers,
                        circles: _circles,
                        onMapCreated: (c) async {
                          _mapController = c;
                          if (!_markersCreated) {
                            _markersCreated = true;
                            await _createMarkers();
                          }
                        },
                        onTap: (pos) => setState(() => _selectedVendor = null),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      );
                    }
                  },
                ),
                if (_selectedVendor != null) _buildVendorPreview(),
              ],
            ),
    );
  }

  Widget _buildWindowsFallback() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            "نسخة الويندوز لا تدعم الخرائط حالياً",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            "(${_vendors.length} vendors loaded)",
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorPreview() {
    return Positioned(
      bottom: 30,
      left: 20,
      right: 20,
      child: GestureDetector(
        onTap: () =>
            VendorNavigation.navigateToVendor(context, _selectedVendor!),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _selectedVendor!.logoUrl ?? '',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(
                    color: Colors.grey[100],
                    width: 80,
                    height: 80,
                    child: const Icon(Icons.store),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _selectedVendor!.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          "${_selectedVendor!.deliveryFee} ₪",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Text(
                          "⭐ ${_selectedVendor!.rating}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_back_ios, size: 16, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddressSelectionSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: true, // ✅ Allow user to click outside to close
      enableDrag: true, // ✅ Allow user to swipe down to close
      barrierColor:
          Colors.black12, // Slight dim to show it's modal but dismissible
      backgroundColor: Colors.white.withOpacity(0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Center(
                child: Text(
                  "اختر عنوان التوصيل",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  "يمكنك اختيار منطقة من القائمة أو تحديدها على الخريطة",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),

              // Option 1: Current Location (GPS)
              _buildAddressOption(
                icon: Icons.my_location,
                title: "موقعي الحالي",
                subtitle: "تحديد موقعي التلقائي عبر GPS",
                onTap: () async {
                  Navigator.pop(sheetContext); // Close the sheet!
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddressSelectionScreen(
                        mode: AddressSelectionMode.gps,
                      ),
                    ),
                  );

                  if (!mounted) return;

                  if (result == true) {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context, true); // Return to home
                    }
                  }
                },
              ),

              // Option 2: Explore Areas
              _buildAddressOption(
                icon: Icons.explore_outlined,
                title: "استكشف مناطق خدماتنا",
                subtitle: "اختر من قائمة المدن والقرى المتاحة",
                onTap: () async {
                  Navigator.pop(sheetContext); // Close the sheet!
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddressSelectionScreen(
                        mode: AddressSelectionMode.list,
                      ),
                    ),
                  );

                  if (!mounted) return;

                  if (result == true) {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context, true); // Return to home
                    }
                  }
                },
              ),

              const Divider(height: 32),

              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "اضغط على أي منطقة في الخريطة لتحديد موقعك",
                        ),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                  child: const Text(
                    "الإختيار عبر الخريطة",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == true && mounted) {
      if (context.mounted && Navigator.canPop(context)) {
        debugPrint("🗺️ [VendorsMapScreen] Sheet returned true, popping Map screen with true");
        Navigator.pop(context, true); // Now correctly pop the Map screen
      } else {
        debugPrint("🗺️ [VendorsMapScreen] Sheet returned true, but cannot pop Map screen or already popped");
      }
    }
  }

  Widget _buildAddressOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: Colors.grey,
      ),
    );
  }

  Future<void> _finalizeAreaSelection(Map<String, dynamic> area) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final lat = _parseLat(area['location']);
      final lng = _parseLng(area['location']);
      final user = _supabaseService.client.auth.currentUser;

      await _supabaseService.saveGuestLocation(area['id'], area['name'], lat, lng);

      if (user != null) {
        await _supabaseService.saveAddressDraft(area['name'], lat, lng);
        await _supabaseService.finalizeAddress("Auto-Selected", "Ground");
      }

      if (mounted) {
        Navigator.pop(context); // Pop dialog
        Navigator.pop(context); // Pop BottomSheet
        Navigator.pop(context, true); // Pop Map Screen, return to Home

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("تم تحديث موقعك إلى: ${area['name']}"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop dialog
      }
      debugPrint("❌ [VendorsMapScreen] Finalize Area error: $e");
    }
  }

  void _showSubAreaSelectionSheet(Map<String, dynamic> parentArea, List<Map<String, dynamic>> children) {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black12,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return _SubAreaSelectionWidget(
          parentArea: parentArea,
          childrenAreas: children,
          onSelect: _finalizeAreaSelection,
          supabaseService: _supabaseService,
        );
      },
    );
  }
}

class _SubAreaSelectionWidget extends StatefulWidget {
  final Map<String, dynamic> parentArea;
  final List<Map<String, dynamic>> childrenAreas;
  final Function(Map<String, dynamic>) onSelect;
  final SupabaseService supabaseService;

  const _SubAreaSelectionWidget({
    required this.parentArea,
    required this.childrenAreas,
    required this.onSelect,
    required this.supabaseService,
  });

  @override
  State<_SubAreaSelectionWidget> createState() => _SubAreaSelectionWidgetState();
}

class _SubAreaSelectionWidgetState extends State<_SubAreaSelectionWidget> {
  bool _loadingGps = true;
  Map<String, dynamic>? _nearestChild;
  bool _showManualList = false;

  @override
  void initState() {
    super.initState();
    _detectNearestChild();
  }

  Future<void> _detectNearestChild() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Location disabled';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'Permission denied';
      }
      if (permission == LocationPermission.deniedForever) throw 'Permission permanently denied';

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 4),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position != null) {
        double minDistance = double.infinity;
        Map<String, dynamic>? closest;

        for (var child in widget.childrenAreas) {
          if (child['location'] != null) {
            final lat = widget.supabaseService.client.auth.currentUser != null ? 32.0 : 32.0; // Dummy logic to bypass parser directly inside widget, will use manual parser
            final childLat = _parseLatLocal(child['location']);
            final childLng = _parseLngLocal(child['location']);
            
            double dist = Geolocator.distanceBetween(position.latitude, position.longitude, childLat, childLng);
            if (dist < minDistance) {
              minDistance = dist;
              closest = child;
            }
          }
        }

        if (closest != null && minDistance < 15000) { // arbitrary 15km acceptable radius
          if (mounted) {
            setState(() {
              _nearestChild = closest;
              _loadingGps = false;
            });
          }
          return;
        }
      }
      throw 'No close child found';
    } catch (e) {
      debugPrint("Auto GPS Detect skipped: $e");
      if (mounted) {
        setState(() {
          _loadingGps = false;
          _showManualList = true; // Fallback directly to manual
        });
      }
    }
  }

  double _parseLatLocal(dynamic loc) {
    if (loc == null) return 32.2211;
    if (loc is String) {
      try {
        final match = RegExp(r"POINT\s*\(([\d\.-]+)\s+([\d\.-]+)\)", caseSensitive: false).firstMatch(loc);
        if (match != null) return double.parse(match.group(2)!);
      } catch (_) {}
    }
    return 32.2211;
  }

  double _parseLngLocal(dynamic loc) {
    if (loc == null) return 35.2544;
    if (loc is String) {
      try {
        final match = RegExp(r"POINT\s*\(([\d\.-]+)\s+[\d\.-]+\)", caseSensitive: false).firstMatch(loc);
        if (match != null) return double.parse(match.group(1)!);
      } catch (_) {}
    }
    return 35.2544;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(
            widget.parentArea['name'],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loadingGps
                ? _buildLoadingState()
                : (_showManualList ? _buildManualList() : _buildDetectedState()),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 20),
        const Text("جاري تحليل موقعك الدقيق...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildDetectedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.location_on, size: 60, color: Colors.green),
        const SizedBox(height: 16),
        const Text("تم تحديد موقعك في:", style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 8),
        Text(
          "${widget.parentArea['name']} - ${_nearestChild!['name']}",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: () => widget.onSelect(_nearestChild!),
            child: const Text("تأكيد واستمرار", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _showManualList = true),
          child: const Text("تغيير يدوي", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildManualList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Center(
          child: Text("الرجاء تحديد قريتك أو منطقتك الفرعية:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: widget.childrenAreas.length,
            itemBuilder: (context, index) {
              final child = widget.childrenAreas[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: ListTile(
                  onTap: () => widget.onSelect(child),
                  trailing: Icon(Icons.arrow_back_ios, size: 14, color: AppColors.primary),
                  title: Text(child['name'], textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

