import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';

class AddressDetailsScreen extends StatefulWidget {
  final String? areaName;
  final String? areaId;
  final double? latitude;
  final double? longitude;

  const AddressDetailsScreen({
    super.key,
    this.areaName,
    this.areaId,
    this.latitude,
    this.longitude,
  });

  @override
  State<AddressDetailsScreen> createState() => _AddressDetailsScreenState();
}

class _AddressDetailsScreenState extends State<AddressDetailsScreen> {
  final _supabaseService = SupabaseService();
  final _streetController = TextEditingController();
  final _buildingController = TextEditingController();
  final _floorController = TextEditingController();
  final _searchController = TextEditingController();
  final _areaController = TextEditingController();

  String? _selectedAreaId;
  LatLng? _selectedLocation;
  bool _submitting = false;
  GoogleMapController? _mapController;

  // Track requests and debounce
  int _geocodingRequestId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initializeSession();
  }

  @override
  void dispose() {
    _debounce?.cancel();

    _streetController.dispose();
    _buildingController.dispose();
    _floorController.dispose();
    _searchController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _initializeSession() async {
    try {
      // 1. Clear old temporary addresses for this session
      await _supabaseService.deleteTemporaryAddresses();
    } catch (e) {
      debugPrint("Error clearing session addresses: $e");
    }

    // 2. Initial state from widget
    _areaController.text = widget.areaName ?? "";
    _searchController.text = widget.areaName ?? "";
    _selectedAreaId = widget.areaId;

    // 3. Determine initial location
    if (widget.latitude != null && widget.longitude != null) {
      _selectedLocation = LatLng(widget.latitude!, widget.longitude!);
      _updateAddressDetails(_selectedLocation!);
    } else {
      // Default fallback location (Palestine/West Bank center)
      _selectedLocation = const LatLng(32.2211, 35.2544);
      _getCurrentLocation();
    }

    if (mounted) setState(() {});
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
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

        if (position != null) {
          LatLng newPos = LatLng(position.latitude, position.longitude);

          setState(() => _selectedLocation = newPos);

          // Wait briefly for map controller to be ready if it's the first load
          if (_mapController == null) {
            await Future.delayed(const Duration(milliseconds: 500));
          }

          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newPos, 16));
          _updateAddressDetails(newPos);
        }
      }
    } catch (e) {
      debugPrint("Error getting GPS: $e");
    }
  }

  void _onCameraMove(CameraPosition pos) {
    _selectedLocation = pos.target;
    _debounceUpdate(pos.target);
  }

  void _debounceUpdate(LatLng location) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _updateAddressDetails(location);
    });
  }

  void _updateAddressDetails(LatLng location) {
    _geocodingRequestId++;
    final currentId = _geocodingRequestId;

    _fetchStreetName(location, currentId);
    _fetchNearestArea(location, currentId);
  }

  Future<void> _fetchStreetName(LatLng location, int requestId) async {
    debugPrint("🔍 [_fetchStreetName] Request $requestId for ${location.latitude}, ${location.longitude}");
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      ).timeout(const Duration(seconds: 5));

      if (!mounted || requestId != _geocodingRequestId) return;

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        String street = place.street?.trim() ?? "";

        if (street.isEmpty || RegExp(r'^\d+$').hasMatch(street)) {
          street = place.subLocality?.trim() ??
              place.locality?.trim() ??
              place.name?.trim() ??
              "";
        }

        debugPrint("🔍 [_fetchStreetName] Resolved Street: $street");
        if (street.isNotEmpty) {
          setState(() {
            _streetController.text = street;
            _searchController.text = street;
          });

          // Server-Side Orchestration: Save to DRAFT table
          try {
            debugPrint("🔍 [_fetchStreetName] Saving draft...");
            final result = await _supabaseService.saveAddressDraft(
              street,
              location.latitude,
              location.longitude,
            );
            debugPrint("🔍 [_fetchStreetName] Draft Result: ${result['area_id']}");

            if (mounted && result['area_id'] != null) {
              setState(() {
                _selectedAreaId = result['area_id'];
                _areaController.text = result['area_name'] ?? "";
              });
            }
          } catch (e) {
            debugPrint("⚠️ [_fetchStreetName] Draft-orchestration error: $e");
            // Fallback to client-side area matching
            _fetchNearestArea(location, requestId);
          }
        }
      }
    } catch (e, stack) {
      debugPrint("❌ [_fetchStreetName] Geocoding error: $e");
      debugPrint("❌ [_fetchStreetName] StackTrace: $stack");
    }
  }

  Future<void> _fetchNearestArea(LatLng location, int requestId) async {
    debugPrint("🔍 [_fetchNearestArea] Request $requestId");
    try {
      final nearest = await _supabaseService.getNearestArea(
        location.latitude,
        location.longitude,
      );
      debugPrint("🔍 [_fetchNearestArea] Result: ${nearest?['name']}");

      if (!mounted || requestId != _geocodingRequestId) return;

      if (nearest != null) {
        setState(() {
          _selectedAreaId = nearest['id'];
          _areaController.text = nearest['name'];
        });
      }
    } catch (e, stack) {
      debugPrint("❌ [_fetchNearestArea] Nearest area error: $e");
      debugPrint("❌ [_fetchNearestArea] StackTrace: $stack");
    }
  }

  Future<void> _saveAddress() async {
    debugPrint("💾 [_saveAddress] Started");
    if (_streetController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("يرجى إدخال اسم الشارع")));
      return;
    }

    setState(() => _submitting = true);
    try {
      final user = _supabaseService.client.auth.currentUser;
      debugPrint("💾 [_saveAddress] User: ${user?.id}");

      // Always update AppState (in-memory) for instant UI feedback in Home
      if (_selectedAreaId != null && _selectedLocation != null) {
        await _supabaseService.saveGuestLocation(
          _selectedAreaId!,
          _areaController.text.isNotEmpty ? _areaController.text : "موقع مختار",
          _selectedLocation!.latitude,
          _selectedLocation!.longitude,
        );
      }

      if (user != null) {
        // 1. Finalize from Draft to Main Table (UPSERT) for logged-in users
        debugPrint("💾 [_saveAddress] Finalizing address...");
        await _supabaseService.finalizeAddress(
          _buildingController.text,
          _floorController.text,
        );
      } else {
        // Guest mode already handled by AppState update above
        debugPrint("💾 [_saveAddress] Guest Mode logic completed via AppState.");
      }

      if (mounted) {
        debugPrint("💾 [_saveAddress] Success, popping with true");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم حفظ الموقع بنجاح"),
            backgroundColor: Colors.green,
          ),
        );
        // Use pop with return value to notify caller
        Navigator.pop(context, true);
      }
    } catch (e, stack) {
      debugPrint("❌ [_saveAddress] Error: $e");
      debugPrint("❌ [_saveAddress] StackTrace: $stack");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.primary,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "تفاصيل الموقع",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(children: [_buildMapContainer(), _buildAddressForm()]),
      ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }

  Widget _buildMapContainer() {
    return Stack(
      children: [
        Container(
          height: 320,
          color: Colors.grey[200],
          child: (_selectedLocation == null)
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : (!Platform.isAndroid && !Platform.isIOS)
                  ? const Center(child: Text("الخريطة متاحة فقط على الهاتف"))
                  : GoogleMap(
                      gestureRecognizers: <Factory<
                          OneSequenceGestureRecognizer>>{
                        Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                        ),
                      },
                      initialCameraPosition: CameraPosition(
                        target: _selectedLocation!,
                        zoom: 15,
                      ),
                      onMapCreated: (c) => _mapController = c,
                      onCameraMove: _onCameraMove,
                      onCameraIdle: () {
                        if (_selectedLocation != null) {
                          _debounceUpdate(_selectedLocation!);
                        }
                      },
                      onTap: (LatLng pos) {
                        setState(() => _selectedLocation = pos);
                        _mapController
                            ?.animateCamera(CameraUpdate.newLatLng(pos));
                        _debounceUpdate(pos);
                      },
                      markers: {
                        Marker(
                          markerId: const MarkerId("selected"),
                          position: _selectedLocation!,
                          draggable: true,
                          onDragEnd: (newPos) {
                            setState(() => _selectedLocation = newPos);
                            _debounceUpdate(newPos);
                          },
                        ),
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      scrollGesturesEnabled: true,
                      zoomGesturesEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                    ),
        ),
        Positioned(
          top: 20,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(27),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1), // Fixed withOpacity
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.my_location, color: AppColors.primary),
                  onPressed: _getCurrentLocation,
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: "ابحث عن موقعك...",
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const Icon(Icons.search, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            "تفاصيل العنوان",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            "املأ تفاصيل عنوانك لخدمة أسرع",
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          _formField(
            "المنطقة",
            _areaController,
            isReadOnly: true,
            onTap: _showAreaPicker,
            isDropdown: true,
          ),
          _formField(
            "اسم الشارع",
            _streetController,
            hint: "مثال: الشارع الرئيسي",
          ),
          _formField("رقم المبنى", _buildingController, hint: "بناية رقم 4"),
          _formField("رقم الطابق / الشقة", _floorController, hint: "اختياري"),
        ],
      ),
    );
  }

  Widget _formField(
    String label,
    TextEditingController controller, {
    bool isReadOnly = false,
    String? hint,
    VoidCallback? onTap,
    bool isDropdown = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            readOnly: isReadOnly,
            onTap: onTap,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[50],
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[300], fontSize: 13),
              suffixIcon: isDropdown
                  ? Icon(Icons.arrow_drop_down, color: AppColors.primary)
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.grey[100]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.grey[100]!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({double lat, double lng})? _parseHexEWKB(String hex) {
    try {
      if (hex.length < 42) return null;
      final byteOrder = int.parse(hex.substring(0, 2), radix: 16);
      if (byteOrder != 1) return null;
      final typeHigh = int.parse(hex.substring(8, 10), radix: 16);
      final hasSrid = (typeHigh & 0x20) != 0;
      // xOffset = hex char position: no SRID=10, with SRID=18
      final xOffset = hasSrid ? 18 : 10;
      if (hex.length < xOffset + 32) return null;
      final xHex = hex.substring(xOffset, xOffset + 16);
      final yHex = hex.substring(xOffset + 16, xOffset + 32);
      final bytes8 = (String h) {
        final b = Uint8List(8);
        for (int i = 0; i < 8; i++) b[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
        return ByteData.view(b.buffer).getFloat64(0, Endian.little);
      };
      final lng = bytes8(xHex);
      final lat = bytes8(yHex);
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
      return (lat: lat, lng: lng);
    } catch (_) { return null; }
  }

  double _parseLat(dynamic loc) {
    if (loc is String) {
      final wkb = _parseHexEWKB(loc);
      if (wkb != null) return wkb.lat;
      try {
        final match = RegExp(r"POINT\s*\(([\d\.-]+)\s+([\d\.-]+)\)").firstMatch(loc);
        if (match != null) return double.parse(match.group(2)!);
      } catch (e) {
        debugPrint("Parse Lat error: $e");
      }
    }
    return 32.2211;
  }

  double _parseLng(dynamic loc) {
    if (loc is String) {
      final wkb = _parseHexEWKB(loc);
      if (wkb != null) return wkb.lng;
      try {
        final match = RegExp(r"POINT\s*\(([\d\.-]+)\s+[\d\.-]+\)").firstMatch(loc);
        if (match != null) return double.parse(match.group(1)!);
      } catch (e) {
        debugPrint("Parse Lng error: $e");
      }
    }
    return 35.2544;
  }

  void _showAreaPicker() async {
    final areas = await _supabaseService.getDeliveryAreas();
    if (!mounted)
      return; // Added this check for use_build_context_synchronously

    // The `if (query.isEmpty) { return; }` line from the snippet was removed
    // as 'query' is not defined in this context and would cause a compile error.

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
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
              const Text(
                "اختر المنطقة",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: areas.length,
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
                            color: Colors.black.withOpacity(0.01),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: ListTile(
                        onTap: () {
                          final selectedArea = area;
                          Navigator.pop(context); // Close the sheet first

                          setState(() {
                            _selectedAreaId = selectedArea['id'];
                            _areaController.text = selectedArea['name'];

                            if (selectedArea['location'] != null) {
                              final lat = _parseLat(selectedArea['location']);
                              final lng = _parseLng(selectedArea['location']);
                              final newPos = LatLng(lat, lng);
                              _selectedLocation = newPos;
                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(newPos, 15),
                              );
                              _updateAddressDetails(newPos);
                            }
                          });
                        },
                        leading: Icon(
                          Icons.arrow_back_ios,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.location_city,
                            color: Colors.grey,
                          ),
                        ),
                        title: Text(
                          area['name'],
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
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

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 30, top: 15),
      child: ElevatedButton(
        onPressed: _submitting ? null : _saveAddress,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 2,
        ),
        child: _submitting
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                "استمر",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
