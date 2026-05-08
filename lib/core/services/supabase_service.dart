import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart' as g_auth;
import 'package:geolocator/geolocator.dart';
 import 'local_log_service.dart';
 import '../models/models.dart';
 import '../utils/image_utils.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _client = Supabase.instance.client;
  SupabaseClient get client => _client;
  User? get currentUser => _client.auth.currentUser;

  Future<void> initializeSettings() async {
    try {
      final duration = await getAppSetting('vendor_new_duration_days');
      if (duration != null) {
        Vendor.newDurationDays = int.tryParse(duration) ?? 7;
        debugPrint("⚙️ [Settings] Vendor New Duration: ${Vendor.newDurationDays} days");
      }

      final isNewEnabled = await getAppSetting('is_new_badge_enabled');
      if (isNewEnabled != null) {
        Vendor.isNewBadgeEnabled = isNewEnabled.toLowerCase().trim() == 'true';
        debugPrint("⚙️ [Settings] Vendor New Badge Enabled: ${Vendor.isNewBadgeEnabled}");
      } else {
        // Default to true if setting is missing from DB
        Vendor.isNewBadgeEnabled = true;
      }
      final dynamicLimit = await getAppSetting('home_horizontal_limit');
      if (dynamicLimit != null) {
        int limit = int.tryParse(dynamicLimit) ?? 20;
        // Safety cap: Don't allow more than 50 in horizontal scroll for performance
        AppConfig.homeHorizontalLimit = limit > 50 ? 50 : limit;
        debugPrint("⚙️ [Settings] Home Horizontal Limit: ${AppConfig.homeHorizontalLimit}");
      }
    } catch (e) {
      debugPrint("Error initializing settings: $e");
    }
  }

  // --- In-Memory Caching ---
  final Map<String, List<Vendor>> _vendorsCache = {};
  final Map<String, List<Map<String, dynamic>>> _homeDataCache = {};
  final Map<String, List<PromotionBanner>> _promotionsCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  // Cache TTL: 5 minutes for stores/home data
  static const _cacheDuration = Duration(minutes: 5);

  bool _isCacheValid(String key) {
    if (!_cacheTimestamps.containsKey(key)) return false;
    return DateTime.now().difference(_cacheTimestamps[key]!) < _cacheDuration;
  }

  Future<DateTime> getServerTime() async {
    try {
      final response = await _client.rpc('get_server_time');
      return DateTime.parse(response.toString());
    } catch (e) {
      debugPrint("Error fetching server time, falling back to local: $e");
      return DateTime.now();
    }
  }

  /// Updates the user's 'last_seen_at' timestamp on the server.
  /// Used for presence tracking in the admin panel.
  Future<void> updateUserPresence() async {
    try {
      if (_client.auth.currentUser == null) return;
      await _client.rpc('update_user_presence');
      
      // Update device model
      String? deviceModel;
      try {
        if (!kIsWeb) {
          DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
          if (Platform.isAndroid) {
            AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
            deviceModel = 'Android - ${androidInfo.brand} ${androidInfo.model}';
          } else if (Platform.isIOS) {
            IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
            deviceModel = 'iOS - ${iosInfo.name}';
          }
        }
      } catch (e) {
         debugPrint("Error fetching device info: $e");
      }
      
      if (deviceModel != null) {
         await _client.from('profiles').update({'device_model': deviceModel}).eq('id', _client.auth.currentUser!.id);
      }
    } catch (e) {
      debugPrint("Error updating presence: $e");
    }
  }



  String formatPhoneNumber(String phone) {
    String p = phone.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (p.isEmpty) return p;
    if (p.startsWith('+')) return p;
    if (p.startsWith('00')) return '+${p.substring(2)}';
    if (p.startsWith('0')) return '+970${p.substring(1)}';
    if ((p.startsWith('970') || p.startsWith('972')) && p.length >= 12) {
      return '+$p';
    }
    // If it's 9 digits and doesn't start with 0, it's likely a local number without the leading 0
    if (p.length == 9) return '+970$p';
    return p;
  }

  // Vendors
  Future<List<Vendor>> getVendors({
    String? type,
    String? categoryId,
    required String? areaId,
    String? searchQuery,
  }) async {
    final cacheKey = "vendors_${type}_${categoryId}_$areaId";
    
    try {
      // 1. Return from Cache if valid
      if (searchQuery == null && _isCacheValid(cacheKey) && _vendorsCache.containsKey(cacheKey)) {
        debugPrint("⚡ [Cache] Serving vendors from memory for $cacheKey");
        // Trigger background refresh
        _fetchAndCacheVendors(type: type, categoryId: categoryId, areaId: areaId)
            .catchError((e) => debugPrint("Vendor cache refresh error: $e"));
        return _vendorsCache[cacheKey]!;
      }

      return await _fetchAndCacheVendors(
        type: type,
        categoryId: categoryId,
        areaId: areaId,
        searchQuery: searchQuery,
      );
    } catch (e) {
      debugPrint("❌ Error in getVendors wrapper: $e");
      return _vendorsCache[cacheKey] ?? [];
    }
  }

  Future<List<Vendor>> _fetchAndCacheVendors({
    String? type,
    String? categoryId,
    required String? areaId,
    String? searchQuery,
  }) async {
    try {
      final cacheKey = "vendors_${type}_${categoryId}_$areaId";
      
      debugPrint(
        "📡 Fetching vendors... Area: $areaId, Type: $type, Cat: $categoryId",
      );

      // 1. Build the select with necessary joins
      String selectString = '*, delivery_areas(name)';
      if (categoryId != null || type != null) {
        selectString +=
            ', vendor_global_category_links!inner(global_category_id, global_categories!inner(vendor_type))';
      }

      var query = _client.from('vendors').select(selectString).eq('is_visible', true);

      // 2. Apply filters
      if (areaId != null) {
        final allAreas = await getDeliveryAreas();
        final relevantAreaIds = _getRelevantAreaIds(areaId, allAreas);
        query = query.inFilter('area_id', relevantAreaIds);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
          'name.ilike.%$searchQuery%,description.ilike.%$searchQuery%',
        );
      }

      if (categoryId != null) {
        query = query.eq(
          'vendor_global_category_links.global_category_id',
          categoryId,
        );
      }

      if (type != null) {
        if (type == 'supermarket') {
          query = query.inFilter(
            'vendor_global_category_links.global_categories.vendor_type',
            ['supermarket', 'retail', 'pharmacy'],
          );
        } else {
          query = query.eq('vendor_global_category_links.global_categories.vendor_type', type);
        }
      }

      final data = await query.order('sort_order', ascending: false);
      final vendors = data.map((json) => Vendor.fromJson(json)).toList();
      
      // Update Cache (only if not searching)
      if (searchQuery == null) {
        _vendorsCache[cacheKey] = vendors;
        _cacheTimestamps[cacheKey] = DateTime.now();
      }
      
      return vendors;
    } catch (e) {
      debugPrint("❌ Error fetching vendors: $e");
      throw e;
    }
  }

  Future<List<Vendor>> getVendorsFiltered({
    String? type,
    String? areaId,
    String? searchQuery,
  }) async {
    try {
      // 1. Build the select with necessary joins if type is specified
      String selectString = '*, delivery_areas(name)';
      if (type != null && type != 'all') {
        selectString +=
            ', vendor_global_category_links!inner(global_categories!inner(vendor_type))';
      }

      var query = _client.from('vendors').select(selectString).eq('is_visible', true);

      // 2. Apply filters
      if (areaId != null) {
        final allAreas = await getDeliveryAreas();
        final relevantAreaIds = _getRelevantAreaIds(areaId, allAreas);
        query = query.inFilter('area_id', relevantAreaIds);
      }

      if (type != null && type != 'all') {
        if (type == 'supermarket') {
          query = query.inFilter(
            'vendor_global_category_links.global_categories.vendor_type',
            ['supermarket', 'retail', 'pharmacy'],
          );
        } else {
          query = query.eq(
            'vendor_global_category_links.global_categories.vendor_type',
            type,
          );
        }
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.ilike('name', '%$searchQuery%');
      }

      final data = await query.order('sort_order', ascending: false).limit(100);
      if (data is List) { return data.map((json) => Vendor.fromJson(json)).toList(); } return [];
    } catch (e) {
      debugPrint("❌ Error in getVendorsFiltered: $e");
      return [];
    }
  }

  // Delivery Areas
  Future<List<Map<String, dynamic>>> getDeliveryAreas() async {
    final response = await _client
        .from('delivery_areas')
        .select('*, parent:delivery_areas!parent_id(name)')
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<String>> getRecursiveSubAreaIds(String areaId) async {
    try {
      final response = await _client.rpc('get_recursive_sub_areas', params: {'root_area_id': areaId});
      if (response is List) {
        return response.map((e) {
          if (e is Map) return e['id']?.toString() ?? '';
          return e.toString();
        }).where((id) => id.isNotEmpty).toList();
      }
      return [areaId];
    } catch (e) {
      debugPrint("RPC error for recursive sub-areas: $e");
      return [areaId];
    }
  }

  // --- Financial Management Removed ---

  Future<Map<String, dynamic>?> getNearestArea(double lat, double lng,
      {List<String>? possibleNames}) async {
    final areas = await getDeliveryAreas();
    if (areas.isEmpty) return null;

    Map<String, dynamic>? nearest;
    double minDistance = double.infinity;

    for (final area in areas) {
      if (area['location'] != null) {
        final areaLat = _parseLat(area['location']);
        final areaLng = _parseLng(area['location']);
        
        final areaName = (area['name'] as String).toLowerCase();
        final List<dynamic> aliases = area['aliases'] ?? [];

        double distance = Geolocator.distanceBetween(lat, lng, areaLat, areaLng);

        // Name matching priority - if the geocoding says we are in this town, 
        // give it a massive 5km "bonus" to overcome center-point inaccuracy.
        if (possibleNames != null && possibleNames.isNotEmpty) {
          bool matched = false;
          for (final pName in possibleNames) {
            final normalizedPName = pName.toLowerCase();
            
            // Check original name
            if (normalizedPName.contains(areaName) || areaName.contains(normalizedPName)) {
              matched = true;
            }
            
            // Check aliases (e.g. Attil, Atil, Baqa)
            if (!matched) {
              for (final alias in aliases) {
                final normalizedAlias = alias.toString().toLowerCase();
                if (normalizedPName.contains(normalizedAlias) || normalizedAlias.contains(normalizedPName)) {
                  matched = true;
                  break;
                }
              }
            }
            
            if (matched) {
              distance -= (area['parent_id'] != null ? 15000 : 5000);
              break;
            }
          }
        }

        // If this area is significantly closer, pick it.
        // If it's roughly the same distance (within 500m), and it's a sub-area (has parent),
        // prioritize it over a parent area.
        if (distance < minDistance - 500) {
          minDistance = distance;
          nearest = area;
        } else if (distance < minDistance + 500 && area['parent_id'] != null) {
          // If distances are similar but this is a specific town (sub-area), pick it.
          minDistance = distance;
          nearest = area;
        }
      }
    }
    return nearest;
  }

  /// Decodes a PostGIS Hex EWKB string into lat/lng. Returns null on failure.
  ({double lat, double lng})? _parseHexEWKB(String hex) {
    try {
      if (hex.length < 42) return null;
      final byteOrder = int.parse(hex.substring(0, 2), radix: 16);
      if (byteOrder != 1) return null; // only handle little-endian
      final typeHigh = int.parse(hex.substring(8, 10), radix: 16);
      final hasSrid = (typeHigh & 0x20) != 0;
      // xOffset = hex char position where X coord starts
      // No SRID: 1(order) + 4(type) = 5 bytes = 10 hex chars
      // With SRID: 1 + 4 + 4(srid) = 9 bytes = 18 hex chars
      final xOffset = hasSrid ? 18 : 10;
      if (hex.length < xOffset + 32) return null;
      final xHex = hex.substring(xOffset, xOffset + 16);
      final yHex = hex.substring(xOffset + 16, xOffset + 32);
      final lng = _littleEndianDouble(xHex);
      final lat = _littleEndianDouble(yHex);
      // Sanity check on valid coordinate range
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
      return (lat: lat, lng: lng);
    } catch (e) {
      debugPrint('_parseHexEWKB error: $e');
      return null;
    }
  }

  double _littleEndianDouble(String hex) {
    final bytes = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return ByteData.view(bytes.buffer).getFloat64(0, Endian.little);
  }

  double _parseLat(dynamic loc) {
    if (loc == null) return 32.2211;

    if (loc is Map && loc['coordinates'] != null) {
      final coords = loc['coordinates'] as List;
      if (coords.length >= 2) return (coords[1] as num).toDouble();
    }

    if (loc is String) {
      // Hex EWKB (PostGIS format from Supabase REST)
      final wkb = _parseHexEWKB(loc);
      if (wkb != null) return wkb.lat;

      // WKT fallback: "POINT(lng lat)"
      try {
        final match = RegExp(r"POINT\s*\(([\d\.-]+)\s+([\d\.-]+)\)", caseSensitive: false).firstMatch(loc);
        if (match != null) return double.parse(match.group(2)!);
      } catch (e) {
        debugPrint("Service Parse Lat error: $e");
      }
    }
    return 32.2211;
  }

  double _parseLng(dynamic loc) {
    if (loc == null) return 35.2544;

    if (loc is Map && loc['coordinates'] != null) {
      final coords = loc['coordinates'] as List;
      if (coords.length >= 1) return (coords[0] as num).toDouble();
    }

    if (loc is String) {
      // Hex EWKB (PostGIS format from Supabase REST)
      final wkb = _parseHexEWKB(loc);
      if (wkb != null) return wkb.lng;

      // WKT fallback: "POINT(lng lat)"
      try {
        final match = RegExp(r"POINT\s*\(([\d\.-]+)\s+[\d\.-]+\)", caseSensitive: false).firstMatch(loc);
        if (match != null) return double.parse(match.group(1)!);
      } catch (e) {
        debugPrint("Service Parse Lng error: $e");
      }
    }
    return 35.2544;
  }

  // User Addresses
  Future<void> saveUserAddress(Map<String, dynamic> addressData) async {
    debugPrint("☁️ [saveUserAddress] Data: $addressData");
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception("User not authenticated");

      final data = {
        'user_id': user.id,
        ...addressData,
      };

      await _client.from('user_addresses').upsert(data, onConflict: 'user_id');
      debugPrint("☁️ [saveUserAddress] Upsert success");
    } catch (e, stack) {
      debugPrint("❌ [saveUserAddress] Error: $e");
      debugPrint("❌ [saveUserAddress] StackTrace: $stack");
      rethrow;
    }
  }

  Future<void> deleteTemporaryAddresses() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('user_addresses')
        .delete()
        .eq('user_id', userId)
        .eq('is_temporary', true);
  }

  Future<bool> checkDuplicateAddress(String street, String areaId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await _client
        .from('user_addresses')
        .select()
        .eq('user_id', userId)
        .eq('address_line_1', street)
        .eq('area_id', areaId);

    return response is List && response.isNotEmpty;

  }

  Future<Map<String, dynamic>> saveAddressDraft(
    String street,
    double lat,
    double lng,
  ) async {
    debugPrint("☁️ [saveAddressDraft] Street: $street, Lat: $lat, Lng: $lng");
    try {
      final response = await _client.rpc('set_user_address_draft', params: {
        'p_street': street,
        'p_lat': lat,
        'p_lng': lng,
      });
      debugPrint("☁️ [saveAddressDraft] RPC success: $response");
      return Map<String, dynamic>.from(response);
    } catch (e, stack) {
      debugPrint("❌ [saveAddressDraft] Error: $e");
      debugPrint("❌ [saveAddressDraft] StackTrace: $stack");
      rethrow;
    }
  }

  Future<void> finalizeAddress(String building, String floor) async {
    debugPrint("☁️ [finalizeAddress] Building: $building, Floor: $floor");
    try {
      await _client.rpc(
        'finalize_user_address',
        params: {'p_building': building, 'p_floor': floor},
      );
      debugPrint("☁️ [finalizeAddress] RPC success");
    } catch (e, stack) {
      debugPrint("❌ [finalizeAddress] Error: $e");
      debugPrint("❌ [finalizeAddress] StackTrace: $stack");
      rethrow;
    }
  }

  // --- Guest Location Persistence (In-Memory AppState) ---
  Map<String, dynamic>? _appStateGuestLocation;

  void setAppStateFromAuth(Map<String, dynamic> authAddress) {
    _appStateGuestLocation = {
      'area_id': authAddress['area_id'],
      'address_line_1': authAddress['address_line_1'] ?? authAddress['delivery_areas']?['name'] ?? 'موقعي',
      'location': authAddress['location'],
      'latitude': _parseLat(authAddress['location']),
      'longitude': _parseLng(authAddress['location']),
    };
    debugPrint("✅ Auth address copied to AppState");
  }

  Future<void> saveGuestLocation(
    String areaId,
    String areaName,
    double lat,
    double lng,
  ) async {
    _appStateGuestLocation = {
      'area_id': areaId,
      'address_line_1': areaName,
      'latitude': lat,
      'longitude': lng,
      'location': 'POINT($lng $lat)',
    };
    debugPrint("✅ Guest location saved to AppState (in-memory)");
  }

  Future<Map<String, dynamic>?> getGuestLocation() async {
    return _appStateGuestLocation;
  }

  Future<Map<String, dynamic>> getEffectiveDeliveryFeeInfo(
    String? vendorAreaId,
    double defaultFee,
  ) async {
    double fee = defaultFee;
    bool hasPromo = false;
    try {
      final guestLoc = await getGuestLocation();
      final userAreaId = guestLoc?['area_id'];

      final useDynamic = await getAppSetting('use_dynamic_delivery_fees');

      if (useDynamic?.toLowerCase() == 'true' && userAreaId != null && vendorAreaId != null) {
        final response = await _client
            .from('area_delivery_fees')
            .select('fee, from_area_id')
            .or('and(from_area_id.eq.$userAreaId,to_area_id.eq.$vendorAreaId),and(from_area_id.eq.$vendorAreaId,to_area_id.eq.$userAreaId)');

        if ((response as List).isNotEmpty) {
          final exactMatch = response.firstWhere(
            (row) => row['from_area_id'] == userAreaId,
            orElse: () => response.first,
          );
          fee = (exactMatch['fee'] as num).toDouble();
        } else if (userAreaId == vendorAreaId) {
          fee = 5.0;
        } else {
          fee = 10.0;
        }
      }

      // Apply promotions with Hierarchy and Priority
      double feeBeforePromo = fee;
      try {
        // 1. Get relevant area IDs (Self + Parents)
        List<String> areaIds = [];
        if (userAreaId != null) {
          areaIds.add(userAreaId);
          try {
            final List<dynamic> areaData = await _client
                .from('delivery_areas')
                .select('parent_id')
                .eq('id', userAreaId);
            
            if (areaData.isNotEmpty) {
              final dynamic parentId = areaData.first['parent_id'];
              if (parentId != null) {
                areaIds.add(parentId.toString());
              }
            }
          } catch (e) {
            debugPrint("Error fetching parent area: $e");
          }
        }

        // 2. Query promotions
        final List<dynamic> promoData;
        if (areaIds.isNotEmpty) {
          final String idList = areaIds.map((id) => '"$id"').join(',');
          promoData = await _client
              .from('delivery_promotions')
              .select('discount_percentage, area_id')
              .eq('is_active', true)
              .or('area_id.is.null,area_id.in.($idList)');
        } else {
          promoData = await _client
              .from('delivery_promotions')
              .select('discount_percentage, area_id')
              .eq('is_active', true)
              .filter('area_id', 'is', null);
        }

        if (promoData.isNotEmpty) {
          // Sort by specificity: القرية أولاً ثم المنطقة ثم العام
          final List<dynamic> promos = List<dynamic>.from(promoData);
          promos.sort((a, b) {
            final dynamic areaA = (a as Map)['area_id'];
            final dynamic areaB = (b as Map)['area_id'];
            
            if (areaA == userAreaId) return -1;
            if (areaB == userAreaId) return 1;
            if (areaA != null && areaB == null) return -1;
            if (areaA == null && areaB != null) return 1;
            return 0;
          });

          final dynamic bestPromo = promos.first;
          final double discountPct = (bestPromo['discount_percentage'] as num).toDouble();
          if (discountPct > 0) {
            fee = fee * (1 - (discountPct / 100));
            hasPromo = true;
          }
        }
      } catch (e) {
        debugPrint("Error fetching promotion info: $e");
      }

      return {
        'fee': fee, 
        'originalFee': feeBeforePromo, 
        'hasPromo': hasPromo
      };
    } catch (e) {
      debugPrint("Error calculating fee info: $e");
      return {'fee': defaultFee, 'originalFee': defaultFee, 'hasPromo': false};
    }
  }

  // Keep old method for backward compatibility
  Future<double> getEffectiveDeliveryFee(String? vendorAreaId, double defaultFee) async {
    final Map<String, dynamic> info = await getEffectiveDeliveryFeeInfo(vendorAreaId, defaultFee);
    return (info['fee'] as num).toDouble();
  }


  Future<void> syncGuestLocationWithUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final guestLoc = await getGuestLocation();
    if (guestLoc != null) {
      try {
        await saveUserAddress({
          'title': 'موقعي المختار',
          'address_line_1': guestLoc['address_line_1'],
          'area_id': guestLoc['area_id'],
          'location': guestLoc['location'], // Use pre-formatted location
          'is_default': true,
        });

        // AppState _appStateGuestLocation is purposely NOT cleared here
        // so that if the user logs out, they seamlessly fall back to this guest location.
        debugPrint("✅ Guest location synced to User DB (Kept in AppState)");
      } catch (e) {
        debugPrint("❌ Error syncing guest location: $e");
      }
    }
  }

  Future<List<Map<String, dynamic>>> getGlobalCategories({String? type}) async {
    var query = _client.from('global_categories').select().eq('is_visible', true);
    if (type != null) {
      if (type == 'supermarket') {
        // Broaden market tab to include retail, pharmacy and brands, EXCLUDE restaurants
        query = query.inFilter('vendor_type', [
          'supermarket',
          'retail',
          'pharmacy',
          'brand',
          'market',
        ]);
      } else {
        query = query.eq('vendor_type', type);
      }
    }
    final response = await query.order('sort_order', ascending: false);
    final data = List<Map<String, dynamic>>.from(response);
    for (var item in data) {
      if (item.containsKey('image_url')) {
        item['image_url'] = ImageUtils.proxyUrl(item['image_url']);
      }
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> getHomeGroupedData(
    String type, {
    String? areaId,
  }) async {
    final cacheKey = "home_data_${type}_$areaId";
    
    if (_isCacheValid(cacheKey) && _homeDataCache.containsKey(cacheKey)) {
        debugPrint("⚡ [Cache] Serving home data from memory for $cacheKey");
        _fetchAndCacheHomeData(type, areaId: areaId).catchError((e) => debugPrint("Home cache refresh error: $e"));
        return _homeDataCache[cacheKey]!;
    }
    
    return await _fetchAndCacheHomeData(type, areaId: areaId);
  }

  Future<List<Map<String, dynamic>>> _fetchAndCacheHomeData(
    String type, {
    String? areaId,
  }) async {
    try {
      final cacheKey = "home_data_${type}_$areaId";
      
      // 1. Fetch categories for this type (Standardized sorting: Highest = Top)
      var catQuery =
          _client.from('global_categories').select().eq('vendor_type', type).eq('is_visible', true);

      if (type == 'supermarket') {
        catQuery = _client.from('global_categories').select().eq('is_visible', true).inFilter(
          'vendor_type',
          ['supermarket', 'retail', 'pharmacy', 'brand', 'market'],
        );
      }

      final catData = await catQuery.order('sort_order', ascending: false);
      final List<Map<String, dynamic>> categories =
          List<Map<String, dynamic>>.from(catData);

      if (categories.isEmpty) return [];

      final catIds = categories.map((c) => c['id']).toList();

      var vendorQuery = _client.from('vendor_global_category_links').select('''
            global_category_id,
            vendors!inner(*, delivery_areas(name))
          ''').inFilter('global_category_id', catIds).eq('vendors.is_visible', true);

      if (areaId != null) {
        final allAreas = await getDeliveryAreas();
        final relevantAreaIds = _getRelevantAreaIds(areaId, allAreas);
        vendorQuery = vendorQuery.inFilter('vendors.area_id', relevantAreaIds);
      }

      final vendorLinkData = await vendorQuery;
      if (vendorLinkData is! List) return [];
      final List links = vendorLinkData;

      Map<String, List<Vendor>> categoryToVendors = {};
      for (var link in links) {
        final catId = link['global_category_id'];
        final vendorJson = link['vendors'];
        if (catId == null || vendorJson == null) continue;
        final vendor = Vendor.fromJson(vendorJson);
        categoryToVendors.putIfAbsent(catId, () => []).add(vendor);
      }

      List<Map<String, dynamic>> result = [];
      for (var cat in categories) {
        final catId = cat['id'];
        final vendors = categoryToVendors[catId] ?? [];
        if (vendors.isEmpty) continue;
        vendors.sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
        result.add({
          'id': catId,
          'name': cat['name'],
          'image_url': ImageUtils.proxyUrl(cat['image_url'] ?? cat['category_image']),
          'vendors': vendors,
        });
      }

      // Update Cache
      _homeDataCache[cacheKey] = result;
      _cacheTimestamps[cacheKey] = DateTime.now();

      return result;
    } catch (e) {
      debugPrint("❌ Error fetching home grouped data (table bypass): $e");
      return _homeDataCache["home_data_${type}_$areaId"] ?? [];
    }
  }

  // Promotions/Banners
  Future<List<PromotionBanner>> getPromotions({String? areaId}) async {
    final cacheKey = "promos_$areaId";
    
    if (_isCacheValid(cacheKey) && _promotionsCache.containsKey(cacheKey)) {
        debugPrint("⚡ [Cache] Serving promotions from memory for $cacheKey");
        _fetchAndCachePromotions(areaId: areaId).catchError((e) => debugPrint("Promo cache refresh error: $e"));
        return _promotionsCache[cacheKey]!;
    }
    
    return await _fetchAndCachePromotions(areaId: areaId);
  }

  Future<List<PromotionBanner>> _fetchAndCachePromotions({String? areaId}) async {
    try {
      final cacheKey = "promos_$areaId";
      var query = _client.from('promotions').select();

      if (areaId != null) {
        final allAreas = await getDeliveryAreas();
        final relevantAreaIds = _getRelevantAreaIds(areaId, allAreas);
        final filterString = relevantAreaIds.map((id) => 'area_id.eq.$id').join(',');
        query = query.or('$filterString,area_id.is.null');
      }

      final response = await query
          .order('sort_order', ascending: false)
          .order('id', ascending: true);

      if (response is! List) return []; 
      final List data = response;

      var active = data.where((item) {
        if (item.containsKey('is_active')) {
          return item['is_active'] == true;
        }
        return true;
      }).toList();

      final result = active.map((json) => PromotionBanner.fromJson(json)).toList();
      
      // Update Cache
      _promotionsCache[cacheKey] = result;
      _cacheTimestamps[cacheKey] = DateTime.now();
      
      return result;
    } catch (e) {
      debugPrint("❌ Error fetching promotions: $e");
      return _promotionsCache["promos_$areaId"] ?? [];
    }
  }

  Future<Vendor> getVendorById(String id) async {
    final response = await _client
        .from('vendors')
        .select('*, delivery_areas(name)')
        .eq('id', id.trim())
        .single();
    return Vendor.fromJson(response);
  }

  // --- VENDOR DETAIL / MENU METHODS ---

  Future<List<MenuCategory>> getVendorMenu(
    String vendorId, {
    String? vendorType,
  }) async {
    try {
      debugPrint("📡 Fetching menu for vendor: $vendorId");

      // Changed from product_categories to categories (correct table name)
      final response = await _client
          .from('products')
          .select(
            '*, categories(*), sub_categories(*), product_options(*, product_option_values(*))',
          )
          .eq('vendor_id', vendorId)
          .order('sort_order', ascending: true);

      final List<dynamic> data = response;
      debugPrint("📦 Products found: ${data.length}");

      if (data.isEmpty) {
        debugPrint("⚠️ No products found for vendor: $vendorId");
        return [];
      }

      Map<String, Map<String, dynamic>> categoryMap = {};
      Map<String, List<Product>> productsByCategory = {};
      Map<String, Map<String, SubCategory>> subCategoriesByCategory = {};

      double parseDouble(dynamic val) {
        if (val == null) return 0.0;
        if (val is num) return val.toDouble();
        return double.tryParse(val.toString()) ?? 0.0;
      }

      // 1. Fetch vendor type(s) if not provided
      if (vendorType == null) {
        try {
          final vRes = await _client
              .from('vendors')
              .select('type')
              .eq('id', vendorId)
              .maybeSingle();
          if (vRes != null) vendorType = vRes['type'];

          if (vendorType == null) {
            final mtRes = await _client
                .from('vendor_multi_types')
                .select('type')
                .eq('vendor_id', vendorId)
                .limit(1);
            if (mtRes.isNotEmpty) vendorType = mtRes.first['type'];
          }
        } catch (e) {
          debugPrint("Could not fetch vendor type for filtering: $e");
        }
      }

      for (var row in data) {
        final catJson = row['categories'] as Map<String, dynamic>?;

        // Handle products without categories
        final catId = catJson?['id'] ?? 'default_category';
        final catName = catJson?['name'] ?? 'عام';
        final isTrending = catJson?['is_trending'] ?? false;
        final sortOrder = catJson?['sort_order'] ?? 999;

        // --- KEY FIX: Filter by Vendor Type ---
        if (catJson != null) {
          final catVendorType =
              catJson['vendor_type']?.toString().toLowerCase();
          final vType = vendorType?.toLowerCase();

          if (vType != null && catVendorType != null) {
            bool isRestaurantVendor = vType == 'restaurant';
            bool isMarketVendor = [
              'supermarket',
              'retail',
              'pharmacy',
              'brand',
              'market',
            ].contains(vType);

            bool isRestaurantCat = catVendorType == 'restaurant';
            bool isMarketCat = [
              'supermarket',
              'retail',
              'pharmacy',
              'brand',
              'market',
            ].contains(catVendorType);

            if (isRestaurantVendor && isMarketCat) continue;
            if (isMarketVendor && isRestaurantCat) continue;
          }
        }

        // Strict Vendor ID check (Original Plan - still very valid for "Brands"):
        // If a category has a SPECIFIC vendor_id that is NOT THIS VENDOR, hide it.
        if (catJson?['vendor_id'] != null &&
            catJson!['vendor_id'] != vendorId) {
          continue;
        }

        if (!categoryMap.containsKey(catId)) {
          categoryMap[catId] = {
            'id': catId,
            'name': catName,
            'is_trending': isTrending,
            'sort_order': sortOrder,
            'image_url': catJson?['image_url'],
          };
          productsByCategory[catId] = [];
          subCategoriesByCategory[catId] = {};
        }

        // Parse SubCategory if available
        final subCatJson = row['sub_categories'] as Map<String, dynamic>?;
        if (subCatJson != null) {
          final subCat = SubCategory.fromJson(subCatJson);
          subCategoriesByCategory[catId]![subCat.id] = subCat;
        }

        final options = (row['product_options'] as List?)?.map((opt) {
              final optMap = Map<String, dynamic>.from(opt);
              return ProductOption.fromJson({
                ...optMap,
                'values': optMap['product_option_values'],
              });
            }).toList() ??
            [];

        productsByCategory[catId]!.add(
          Product(
            id: row['id'],
            name: row['name'],
            description: row['description'],
            price: parseDouble(row['base_price']),
            imageUrl: row['image_url'],
            vendorId: vendorId,
            options: options,
            isTrending: row['is_trending'] ?? false,
            isFeatured: row['is_featured'] ?? false,
            sortOrder: row['sort_order'] ?? 0,
            subCategory: row['sub_category'], // Legacy text support
            subCategoryId: subCatJson?['id'], // FK support
            salePrice: row['sale_price'] != null
                ? (row['sale_price'] as num).toDouble()
                : null,
          ),
        );
      }

      // Build category list
      final List<MenuCategory> categories = categoryMap.keys.map((id) {
        final subCats = subCategoriesByCategory[id]?.values.toList() ?? [];
        // Sort sub-categories by order
        subCats.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        return MenuCategory.fromJson(
          categoryMap[id]!,
          productsByCategory[id]!,
          subCategories: subCats,
        );
      }).toList();

      // Sort by category sort_order
      categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      return categories;
    } catch (e, stack) {
      debugPrint("❌ Critical Error in getVendorMenu: $e");
      debugPrint(stack.toString());
      return [];
    }
  }

  Future<List<Product>> getPaginatedProducts({
    String? vendorId,
    String? categoryId,
    int offset = 0,
    int limit = 20,
    String? searchQuery,
  }) async {
    try {
      var query = _client.from('products').select(
        '*, categories(*), sub_categories(*), product_options(*, product_option_values(*))',
      );

      if (vendorId != null) {
        query = query.eq('vendor_id', vendorId);
      }
      
      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.ilike('name', '%$searchQuery%');
      }

      final response = await query
          .order('sort_order', ascending: true)
          .range(offset, offset + limit - 1);

      final List<dynamic> data = response;
      
      double parseDouble(dynamic val) {
        if (val == null) return 0.0;
        if (val is num) return val.toDouble();
        return double.tryParse(val.toString()) ?? 0.0;
      }

      return data.map((row) {
        final options = (row['product_options'] as List?)?.map((opt) {
          final optMap = Map<String, dynamic>.from(opt);
          return ProductOption.fromJson({
            ...optMap,
            'values': optMap['product_option_values'],
          });
        }).toList() ?? [];

        return Product(
          id: row['id'],
          name: row['name'],
          description: row['description'],
          price: parseDouble(row['base_price']),
          imageUrl: row['image_url'],
          vendorId: row['vendor_id'],
          options: options,
          isTrending: row['is_trending'] ?? false,
          isFeatured: row['is_featured'] ?? false,
          sortOrder: row['sort_order'] ?? 0,
          subCategoryId: row['sub_category_id'],
          salePrice: row['sale_price'] != null
              ? (row['sale_price'] as num).toDouble()
              : null,
        );
      }).toList();
    } catch (e) {
      debugPrint("❌ Error fetching paginated products: $e");
      return [];
    }
  }

  Future<List<Product>> getProductsByVendor(String vendorId) async {
    // Existing method - kept for backward compatibility if needed
    final response =
        await _client.from('products').select().eq('vendor_id', vendorId);
    if (response is List) {
      return response.map((json) => Product.fromJson(json)).toList();
    }
    return [];
  }

  // Categories
  Future<List<Map<String, dynamic>>> getCategories(String vendorId) async {
    final response = await _client
        .from('categories')
        .select()
        .eq('vendor_id', vendorId)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(response);
  }

  // --- STAR POINTS ---

  Future<UserProfile?> getUserProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      LocalLogService.setLoggingEnabled(false);
      return null;
    }
    try {
      final response =
          await _client.from('profiles').select().eq('id', user.id).single();
      final profile = UserProfile.fromJson(response);
      
      // Sync admin logging status
      LocalLogService.setLoggingEnabled(profile.role == 'admin');
      
      return profile;
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
      return null;
    }
  }

  /// Returns a real-time stream of the current user's profile.
  Stream<UserProfile?> streamUserProfile() {
    final user = _client.auth.currentUser;
    if (user == null) {
      LocalLogService.setLoggingEnabled(false);
      return Stream.value(null);
    }

    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .where((data) => data.isNotEmpty) // Prevents flickering by skipping empty pulses
        .map((data) {
          final profile = UserProfile.fromJson(data.first);
          // Sync admin logging status
          LocalLogService.setLoggingEnabled(profile.role == 'admin');
          return profile;
        });
  }

  Future<List<StarPointsTransaction>> getStarPointsHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    try {
      final response = await _client
          .from('star_points_transactions')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      return (response as List)
          .map((json) => StarPointsTransaction.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint("Error fetching points history: $e");
      return [];
    }
  }

  // Orders
  Future<void> createOrder({
    required String vendorId,
    required double subtotal,
    required double deliveryFee,
    required String address,
    required List<Map<String, dynamic>> items,
    String? batchId,
    String status = 'pending',
    int redeemedPoints = 0,
    double pointsDiscount = 0,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final orderResponse = await _client
        .from('orders')
        .insert({
          'user_id': user.id,
          'vendor_id': vendorId,
          'batch_id': batchId,
          'subtotal': subtotal,
          'delivery_fee': deliveryFee,
          'total_price': subtotal + deliveryFee - pointsDiscount,
          'delivery_address': address,
          'status': status,
          'source': 'mob_app', // Explicitly mark as App Order
          'points_redeemed': redeemedPoints,
          'points_discount': pointsDiscount,
        })
        .select()
        .single();

    final orderId = orderResponse['id'];

    final List<Map<String, dynamic>> orderItems = items
        .map(
          (item) => {
            'order_id': orderId,
            'product_id': item['product_id'],
            'name': item['name'],
            'quantity': item['quantity'],
            'price_at_time': item['price'],
            if (item['notes'] != null) 'notes': item['notes'],
            if (item['selected_options'] != null)
              'selected_options': item['selected_options'],
          },
        )
        .toList();

    await _client.from('order_items').insert(orderItems);

    // If points were redeemed, deduct them
    if (redeemedPoints > 0) {
      try {
        await _client.rpc('redeem_star_points', params: {
          'p_amount': redeemedPoints,
          'p_order_id': orderId,
        });
      } catch (e) {
        debugPrint("Error redeeming points: $e");
        // We don't throw here to avoid failing the order if only points deduction fails,
        // but ideally this should be atomic.
      }
    }
  }

  Future<List<Map<String, dynamic>>> getOrders() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final response = await _client
        .from('orders')
        .select('*, vendors(name, logo_url)')
        .eq('user_id', user.id)
        .eq('source', 'mob_app') // Only show App Orders
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Stream<Map<String, dynamic>> streamOrderUpdates(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((data) => data.first);
  }

  // --- EXPANSION METHODS ---

  Stream<Map<String, dynamic>?> streamUserAddress() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value(null);

    return _client
        .from('user_addresses')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('is_default', ascending: false)
        .map((data) {
          if (data.isEmpty) return null;
          // The stream only gives us the table, we need to handle the join or area name manually
          // if we can't do a full relational stream yet.
          return data.first;
        });
  }

  // Addresses
  Future<List<Map<String, dynamic>>> getUserAddresses() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final response = await _client
        .from('user_addresses')
        .select('*, delivery_areas(name)')
        .eq('user_id', user.id)
        .order('is_default', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addAddress(
    String title,
    String line1, {
    bool isDefault = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('user_addresses').insert({
      'user_id': user.id,
      'title': title,
      'address_line_1': line1,
      'is_default': isDefault,
    });
  }

  // Favorites
  Future<bool> isFavorite(String vendorId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final response = await _client
        .from('favorite_vendors')
        .select()
        .eq('user_id', user.id)
        .eq('vendor_id', vendorId)
        .maybeSingle();
    return response != null;
  }

  Future<void> submitRating({
    required String vendorId,
    required String orderId,
    required int rating,
    String? comment,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("يجب تسجيل الدخول للتقييم");

    await _client.from('reviews').insert({
      'user_id': user.id,
      'vendor_id': vendorId,
      'order_id': orderId,
      'rating': rating,
      'comment': comment,
    });
  }

  Future<Map<String, dynamic>?> getOrderReview(String orderId) async {
    return await _client
        .from('reviews')
        .select()
        .eq('order_id', orderId)
        .maybeSingle();
  }

  Future<String?> getRateableOrderId(String vendorId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final response = await _client
          .from('orders')
          .select('id, reviews(id)')
          .eq('user_id', user.id)
          .eq('vendor_id', vendorId)
          .eq('status', 'delivered');
      
      if (response is! List) return null; final List data = response;
      for (var order in data) {
        final reviews = order['reviews'] as List?;
        if (reviews == null || reviews.isEmpty) {
          return order['id'].toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint("Error checking rateable order: $e");
      return null;
    }
  }


  Future<List<Vendor>> getTopRatedVendors({
    String? type,
    String? areaId,
    int limit = 10,
  }) async {
    try {
      var query = _client
          .from('vendors')
          .select()
          .eq('is_visible', true)
          .gt('review_count', 0);

      if (areaId != null) {
        final allAreas = await getDeliveryAreas();
        final relevantAreaIds = _getRelevantAreaIds(areaId, allAreas);
        query = query.inFilter('area_id', relevantAreaIds);
      }

      if (type != null && type != 'all') {
        if (type == 'supermarket') {
          query = query.inFilter('type', ['supermarket', 'retail', 'pharmacy', 'market']);
        } else {
          query = query.eq('type', type);
        }
      }

      final data = await query
          .order('rating_avg', ascending: false)
          .order('review_count', ascending: false)
          .limit(limit);

      if (data is List) { return data.map((json) => Vendor.fromJson(json)).toList(); } return [];
    } catch (e) {
      debugPrint("❌ Error fetching top rated vendors: $e");
      return [];
    }
  }

  Future<void> toggleFavorite(String vendorId, bool currentStatus) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (currentStatus) {
      await _client
          .from('favorite_vendors')
          .delete()
          .eq('user_id', user.id)
          .eq('vendor_id', vendorId);
    } else {
      await _client.from('favorite_vendors').insert({
        'user_id': user.id,
        'vendor_id': vendorId,
      });
    }
  }

  // Coupons
  Future<Map<String, dynamic>?> validateCoupon(String code) async {
    final response =
        await _client.from('coupons').select().eq('code', code).maybeSingle();
    // In a real app, check valid_until and usage_limit here
    return response;
  }

  // Auth
  Future<AuthResponse> signInWithGoogle() async {
    const webClientId =
        '1072349230592-nng3ok1rggr78djniqib30pecpt7t148.apps.googleusercontent.com';
    const iosClientId =
        '1072349230592-m6f8f8k9k8k8k8k8k8k8k8k8k8k8k8k8.apps.googleusercontent.com'; // Placeholder for iOS until plist found

    final googleSignIn = g_auth.GoogleSignIn(
      clientId: iosClientId,
      serverClientId: webClientId,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google Sign-In cancelled by user');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null || accessToken == null) {
      throw Exception('Failed to retrieve authentication tokens.');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<AuthResponse> signIn(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signInWithPhone(String phone, String password) {
    return _client.auth.signInWithPassword(
      phone: formatPhoneNumber(phone),
      password: password,
    );
  }

  Future<void> signInWithOtp(String phone) async {
    await _client.auth.signInWithOtp(phone: formatPhoneNumber(phone));
  }

  Future<AuthResponse> verifyOtp(
    String contact,
    String token, {
    OtpType type = OtpType.signup,
  }) {
    // For email generic, we might use OtpType.email if supported, or signup/recovery
    // Supabase generic verifyOTP uses 'phone' or 'email' param.
    // The Dart SDK `verifyOTP` takes `phone` OR `email`.
    if (type == OtpType.sms || type == OtpType.phoneChange) {
      return _client.auth.verifyOTP(
        phone: formatPhoneNumber(contact),
        token: token,
        type: type,
      );
    } else {
      return _client.auth.verifyOTP(email: contact, token: token, type: type);
    }
  }

  Future<void> resendOtp(
    String contact, {
    OtpType type = OtpType.signup,
  }) async {
    if (type == OtpType.sms || type == OtpType.phoneChange) {
      await _client.auth.resend(type: type, phone: formatPhoneNumber(contact));
    } else {
      await _client.auth.resend(type: type, email: contact);
    }
  }

  Future<AuthResponse> signUp(
    String email,
    String password,
    String name, {
    String? phone,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': name,
        if (phone != null) 'phone': formatPhoneNumber(phone),
      },
    );
  }

  Future<AuthResponse> signUpWithPhone(
    String phone,
    String password,
    String name,
  ) {
    final formattedPhone = formatPhoneNumber(phone);
    return _client.auth.signUp(
      phone: formattedPhone,
      password: password,
      data: {'full_name': name},
    );
  }

  Future<void> updateUserProfile({String? name, String? phone}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final data = <String, dynamic>{
      'id': user.id, // Require ID for upsert
    };
    final authData = <String, dynamic>{};
    
    if (name != null) {
      data['full_name'] = name;
      authData['full_name'] = name;
    }
    if (phone != null) {
      data['phone'] = formatPhoneNumber(phone);
      authData['phone'] = formatPhoneNumber(phone);
    }

    if (authData.isEmpty) return;

    // 1. Update Auth Metadata
    await _client.auth.updateUser(UserAttributes(data: authData));

    // 2. Upsert Profiles Table (Insert if missing, update if exists)
    await _client.from('profiles').upsert(data);
  }

  Future<void> updateUserPhone(String phone) async {
    await updateUserProfile(phone: phone);
  }

  Future<void> resetPasswordForEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async {
    await LocalLogService.setLoggingEnabled(false);
    await _client.auth.signOut();
  }


  // --- Support Features ---

  Future<String> getDeliveryFeeRange() async {
    try {
      final response = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'delivery_fee_range')
          .maybeSingle();
      return response?['value'] ?? '5 - 20 ₪ حسب المنطقة';
    } catch (e) {
      debugPrint("Error fetching delivery fee setting: $e");
      return '5 - 20 ₪ حسب المنطقة';
    }
  }

  Future<String> getSupportWhatsApp() async {
    try {
      final response = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'support_whatsapp')
          .maybeSingle();
      return response?['value'] ?? '+970599000000';
    } catch (e) {
      debugPrint("Error fetching WhatsApp setting: $e");
      return '+970599000000';
    }
  }

  Stream<List<Map<String, dynamic>>> getSupportMessages({int limit = 50}) {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value([]);

    // ✅ Only stream the most recent messages for performance
    return _client
        .from('support_messages')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .map((messages) {
          return messages.where((m) => m['is_deleted'] != true).toList();
        });
  }

  // ✅ Fetch messages modified since a timestamp (to get deletions + status updates + new messages)
  Future<List<Map<String, dynamic>>> fetchLatestMessages({
    String? sinceTimestamp,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      var query =
          _client.from('support_messages').select().eq('user_id', user.id);

      if (sinceTimestamp != null) {
        query = query.gt('updated_at', sinceTimestamp);
      }

      final response =
          await query.order('updated_at', ascending: false).limit(50);

      // We return everything (including is_deleted = true) so the client can process the "delete" event
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("Error fetching updates: $e");
      return [];
    }
  }

  Future<void> sendSupportMessage(String text, {String? clientId}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('support_messages').insert({
      'user_id': user.id,
      'client_id': clientId, // ✅ Match with optimistic ID
      'message': text,
      'is_from_admin': false,
      'status': 'sent',
    });

    // Reset user typing status
    await updateTypingStatus(isTyping: false);
  }

  Stream<Map<String, dynamic>?> getChatStatus() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value(null);

    return _client
        .from('chat_status')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', user.id)
        .limit(1)
        .map((list) => list.isNotEmpty ? list.first : null);
  }

  Future<void> updateTypingStatus({required bool isTyping}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('chat_status').upsert({
      'user_id': user.id,
      'is_user_typing': isTyping,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> markMessagesAsRead() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // 1. Mark individual messages as read
    await _client
        .from('support_messages')
        .update({'is_read': true, 'status': 'read'})
        .eq('user_id', user.id)
        .eq('is_from_admin', true)
        .eq('is_read', false);

    // 2. Reset the aggregate unread counter for the user
    await _client
        .from('support_chats')
        .update({'unread_count_user': 0}).eq('user_id', user.id);
  }

  Future<Map<String, dynamic>?> fetchChatSummary() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return await _client
        .from('support_chats')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
  }

  Stream<Map<String, dynamic>?> getChatSummaryStream() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value(null);

    return _client
        .from('support_chats')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', user.id)
        .limit(1)
        .map((list) => list.isNotEmpty ? list.first : null);
  }

  Future<void> deleteMessage(String messageId) async {
    await _client
        .from('support_messages')
        .update({'is_deleted': true}).eq('id', messageId);
  }

  Future<void> clearChat() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('support_messages')
        .update({'is_deleted': true}).eq('user_id', user.id);
  }

  Future<void> startNewChat() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('support_chats').upsert({
      'user_id': user.id,
      'is_chat_ended': false,
      'last_cleared_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Stream<bool> getSupportOnlineStream() {
    return _client
        .from('app_settings')
        .stream(primaryKey: ['key'])
        .eq('key', 'is_support_online')
        .map((data) {
          if (data.isEmpty) return false;
          final value = data.first['value']?.toString().toLowerCase();
          return value == 'true';
        });
  }

  Future<String?> getAppSetting(String key) async {
    try {
      final response = await _client
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();
      return response?['value'];
    } catch (e) {
      debugPrint("Error fetching setting $key: $e");
      return null;
    }
  }

  Future<void> updateAppSetting(String key, String value) async {
    try {
      await _client.from('app_settings').upsert({
        'key': key,
        'value': value,
      });
      debugPrint("✅ App setting updated: $key = $value");
    } catch (e) {
      debugPrint("❌ Error updating app setting ($key): $e");
      rethrow;
    }
  }

  Future<String> getAppVersion() async {
    final version = await getAppSetting('latest_version');
    return version ?? '1.0.0';
  }

  Stream<Map<String, String>> getAppSettingsStream() {
    return _client.from('app_settings').stream(primaryKey: ['key']).map((data) {
      final Map<String, String> settings = {};
      for (var item in data) {
        settings[item['key']] = item['value']?.toString() ?? '';
      }
      return settings;
    });
  }

  Future<List<Product>> searchProducts({
    String? areaId,
    required String query,
  }) async {
    try {
      var dbQuery = _client.from('products').select('*, vendors!inner(*)');

      if (areaId != null) {
        final allAreas = await getDeliveryAreas();
        final relevantAreaIds = _getRelevantAreaIds(areaId, allAreas);
        dbQuery = dbQuery.inFilter('vendors.area_id', relevantAreaIds);
      }

      if (query.isNotEmpty) {
        dbQuery = dbQuery.ilike('name', '%$query%');
      }

      final data = await dbQuery.limit(50);
      if (data is List) {
        return data.map((json) => Product.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("❌ Error searching products: $e");
      return [];
    }
  }

  // --- Game System ---
  Future<List<Map<String, dynamic>>> getActiveGames() async {
    try {
      final response = await _client
          .from('games')
          .select()
          .order('created_at');
          
      final List<Map<String, dynamic>> games = List<Map<String, dynamic>>.from(response);
      
      for (int i = 0; i < games.length; i++) {
        final slug = games[i]['slug'];
        Map<String, dynamic> settingsRow = {};
        
        try {
            if (slug == 'into-space') {
               settingsRow = await _client.from('space_game_settings').select().eq('id', 1).single();
               games[i]['is_active'] = settingsRow['is_active'] ?? true; 
            } else {
               settingsRow = await _client.from('game_settings').select().eq('id', 1).single();
               games[i]['is_active'] = settingsRow['is_active'] ?? true; 
            }
        } catch (e) {
           debugPrint("Error fetching sub-settings for $slug: $e");
        }
        
        // Emulate the structure Expected by SingleGameLaunchScreen
        games[i]['settings'] = settingsRow;
        
        games[i]['reward_settings'] = {
            'max_attempts': settingsRow['max_attempts'],
            'points_to_stars_ratio': settingsRow['points_to_stars_ratio'],
            'min_score_for_reward': settingsRow['min_score_for_reward'],
            'is_fixed_reward': settingsRow['is_fixed_reward'],
            'reward_amount_fixed': settingsRow['reward_amount_fixed'],
            'show_leaderboard': settingsRow['show_leaderboard'],
            'is_competition_mode': settingsRow['is_competition_mode'],
            'competition_title': settingsRow['competition_title'],
            'competition_description': settingsRow['competition_description'],
            'competition_reward_text': settingsRow['competition_reward_text'],
        };
        
        games[i]['eligibility_settings'] = {
            'start_time': settingsRow['start_time'],
            'end_time': settingsRow['end_time'],
            'require_purchase': settingsRow['require_purchase'],
            'min_purchase_amount': settingsRow['min_purchase_amount'],
            'purchase_window_days': settingsRow['purchase_window_days'],
        };
      }
      
      return games;
    } catch (e) {
      debugPrint("Error fetching active games: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>?> getGameSettings(String gameSlug) async {
    try {
      final games = await getActiveGames();
      return games.firstWhere((g) => g['slug'] == gameSlug);
    } catch (e) {
      debugPrint("Error fetching game settings for $gameSlug: $e");
      return null;
    }
  }

  /// Live check: fetches is_active directly from the settings table.
  Future<bool> isGameActive(String gameSlug) async {
    try {
      final table = gameSlug == 'into-space' ? 'space_game_settings' : 'game_settings';
      final response = await _client.from(table).select('is_active').eq('id', 1).single();
      return (response as Map<String, dynamic>)['is_active'] ?? true;
    } catch (e) {
      debugPrint('Error checking game active status for $gameSlug: $e');
      return true; // fail open so we don't block users on network errors
    }
  }

  Future<Map<String, dynamic>> checkCompetitionEligibility(String gameSlug) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return {'isEligible': false, 'reason': 'auth'};
    }

    final gameData = await getGameSettings(gameSlug);
    if (gameData == null || gameData['eligibility_settings'] == null) {
      return {'isEligible': true};
    }

    final eligibilitySettings = gameData['eligibility_settings'];
    final requirePurchase = eligibilitySettings['require_purchase'] ?? false;

    if (!requirePurchase) return {'isEligible': true};

    final minAmount = (eligibilitySettings['min_purchase_amount'] ?? 0);
    final windowDays = eligibilitySettings['purchase_window_days'] ?? 7;
    
    // Use server time for eligibility cutoff
    final serverNow = await getServerTime();
    final cutoffDate = serverNow
        .subtract(Duration(days: windowDays))
        .toUtc()
        .toIso8601String();


    try {
      // Fetch all qualifying orders within the window to calculate total spent
      final ordersResponse = await _client
          .from('orders')
          .select('total_price')
          .eq('user_id', user.id)
          .or('status.eq.delivered,status.eq.confirmed,status.eq.preparing,status.eq.out_for_delivery')
          .gte('created_at', cutoffDate);

      final List<dynamic> orders = ordersResponse as List<dynamic>;
      double totalSpent = 0;
      for (var order in orders) {
        totalSpent += (order['total_price'] ?? 0).toDouble();
      }

      if (totalSpent >= minAmount) {
        return {'isEligible': true};
      } else {
        return {
          'isEligible': false,
          'reason': 'purchase_required',
          'totalSpent': totalSpent,
          'requiredMore': minAmount - totalSpent,
          'minAmount': minAmount,
          'windowDays': windowDays,
        };
      }
    } catch (e) {
      debugPrint("❌ [SupabaseService] Error checking eligibility for $gameSlug: $e");
      return {'isEligible': true};
    }
  }

  Future<String?> startGameAttempt(String gameSlug) async {
    try {
      final response = await _client.rpc('start_game_attempt_v2', params: {
        'p_game_slug': gameSlug
      });
      return response as String?;
    } catch (e) {
      debugPrint("Error starting game attempt for $gameSlug: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>> processGameResult(String gameSlug, int score, {String? attemptId, bool isAdvancedMode = false}) async {
    try {
      final int ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final String sig = _generateHmacSignature('result:$gameSlug:$score:$ts');

      final response = await _client.rpc('process_game_result_secure', params: {
        'p_game_slug': gameSlug,
        'p_score': score,
        if (attemptId != null) 'p_attempt_id': attemptId,
        'p_is_advanced_mode': isAdvancedMode,
        'p_ts': ts,
        'p_sig': sig,
      });
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint("Error processing game result for $gameSlug: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getGameLeaderboard(String gameSlug) async {
    try {
      final response = await _client.rpc('get_game_leaderboard_v2', params: {
        'p_game_slug': gameSlug
      });
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint("Error fetching leaderboard for $gameSlug: $e");
      return {'top_players': [], 'user_rank': null};
    }
  }

  Future<Map<String, dynamic>> placeOrderSecurely({
    required String vendorId,
    required List<Map<String, dynamic>> items,
    required String address,
    required int redeemedPoints,
    String? batchId,
    double? batchTotal,
    String? notes,
    String? areaId,
    double? deliveryFee,
  }) async {
    try {
      final response = await _client.rpc('place_order_securely_v2', params: {
        'p_vendor_id': vendorId,
        'p_items': items,
        'p_delivery_address': address,
        'p_points_to_redeem': redeemedPoints,
        'p_notes': notes,
        'p_area_id': areaId,
        'p_batch_id': batchId,
        'p_batch_total': batchTotal,
        'p_delivery_fee': deliveryFee ?? 0,
      });
      
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint("Secure Checkout Error: $e");
      return {
        'success': false,
        'message': e.toString()
      };
    }
  }

  Future<int> getRemainingAttempts(String gameSlug) async {
    try {
      final response = await _client.rpc('get_remaining_attempts_v2', params: {
        'p_game_slug': gameSlug
      });
      return response as int;
    } catch (e) {
      debugPrint('Error fetching remaining attempts for $gameSlug: $e');
      return 0;
    }
  }

  // --- Game Progress (Hangar / Upgrades) ---
  Future<Map<String, dynamic>> getGameProgress(String gameSlug) async {
    final user = _client.auth.currentUser;
    if (user == null) return {};

    try {
      // 1. Fetch relevant game settings to check for global reset
      final settingsTable = gameSlug == 'into-space' ? 'space_game_settings' : 'game_settings';
      final settings = await _client.from(settingsTable).select('last_reset_at').eq('id', 1).maybeSingle();
      final lastResetAtStr = settings?['last_reset_at'];
      final DateTime? lastResetAt = lastResetAtStr != null ? DateTime.parse(lastResetAtStr) : null;

      // 2. Fetch user progress
      final response = await _client
          .from('game_progress')
          .select()
          .eq('user_id', user.id)
          .eq('game_slug', gameSlug)
          .maybeSingle();
          
      final defaultProgress = {
          'money_collected': 0,
          'current_rocket_tier': 1,
          'upgrades': {
            'engine_lv': 1,
            'fuel_lv': 1,
            'hull_lv': 1,
            'booster_lv': 0,
            'magnet_lv': 0,
          }
      };

      if (response == null) return defaultProgress;

      // 3. --- RESET AWARENESS CHECK ---
      // If a global reset happened AFTER the user last updated their progress,
      // then we must treat the user as having NO progress (forced reset).
      if (lastResetAt != null) {
          final lastUpdatedStr = response['last_updated_at'];
          final DateTime lastUpdated = lastUpdatedStr != null 
              ? DateTime.parse(lastUpdatedStr) 
              : DateTime.fromMillisecondsSinceEpoch(0);
          
          if (lastResetAt.isAfter(lastUpdated)) {
              debugPrint("🔄 Global reset detected for $gameSlug (Reset: $lastResetAt > LastUpdate: $lastUpdated). Cleaning stale progress.");
              return defaultProgress;
          }
      }

      return response;
    } catch (e) {
      debugPrint("Error fetching game progress for $gameSlug: $e");
      return {};
    }
  }

  Future<void> updateGameProgress(String gameSlug, Map<String, dynamic> data) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final payload = {
        'user_id': user.id,
        'game_slug': gameSlug,
        ...data,
        'last_updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final existing = await _client
          .from('game_progress')
          .select('id')
          .eq('user_id', user.id)
          .eq('game_slug', gameSlug)
          .maybeSingle();

      if (existing != null) {
        await _client.from('game_progress').update(payload).eq('id', existing['id']);
        debugPrint("✅ Game progress updated successfully");
      } else {
        await _client.from('game_progress').insert(payload);
        debugPrint("✅ Game progress inserted successfully");
      }
    } catch (e) {
      debugPrint("❌ Error updating game progress for $gameSlug: $e");
    }
  }

  Future<void> updateWonMilestones(String gameSlug, List<int> newMilestones) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      // Get current milestones first
      final progress = await _client.from('game_progress').select('won_milestones').eq('user_id', user.id).eq('game_slug', gameSlug).maybeSingle();
      List<int> current = List<int>.from(progress?['won_milestones'] ?? []);
      
      // Merge and unique
      final updated = {...current, ...newMilestones}.toList();
      
      await _client.from('game_progress').update({
        'won_milestones': updated,
        'last_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', user.id).eq('game_slug', gameSlug);
    } catch (e) {
      debugPrint("Error updating won milestones for $gameSlug: $e");
    }
  }

  // ─── Security: HMAC-SHA256 Signature Generator ───────────────────────────
  // This key must exactly match the one stored in Supabase.
  // Obfuscated representation of the secret key to prevent simple string extraction.
  String get _rewardSecretKey {
    return String.fromCharCodes([72, 83, 50, 48, 50, 54, 64, 72, 97, 116, 83, 116, 97, 114, 35, 83, 101, 99, 117, 114, 101, 33, 75, 51, 121, 36]);
  }

  String _generateHmacSignature(String message) {
    final key = utf8.encode(_rewardSecretKey);
    final bytes = utf8.encode(message);
    final hmac = Hmac(sha256, key);
    // Use lower case to match PostgreSQL's encode(..., 'hex') behavior
    return hmac.convert(bytes).toString().toLowerCase();
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> addGameMoney(String gameSlug, int amountEarned) async {
    final user = _client.auth.currentUser;
    if (user == null || amountEarned <= 0) return;

    try {
      final int ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final String sig = _generateHmacSignature('money:$gameSlug:$amountEarned:$ts');

      final result = await _client.rpc('increment_game_money_secure', params: {
        'p_game_slug': gameSlug,
        'p_amount': amountEarned,
        'p_ts': ts,
        'p_sig': sig,
      });

      final bool ok = (result is Map && result['success'] == true);
      if (ok) {
        debugPrint('✅ addGameMoney: secure RPC succeeded (+$amountEarned coins)');
      } else {
        debugPrint('❌ Secure money RPC rejected the request: $result');
      }
    } catch (e) {
      debugPrint('❌ Secure money RPC exception. No fallback allowed. Error: $e');
    }
  }

  Future<void> addBonusStars(int amount, {String? description}) async {
    if (amount <= 0) return;
    try {
      final int ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final String sig = _generateHmacSignature('stars:$amount:$ts');

      final result = await _client.rpc('add_user_stars_secure_v1', params: {
        'p_amount': amount,
        'p_ts': ts,
        'p_sig': sig,
        'p_description': description ?? 'ربح من اللعبة',
      });

      final bool ok = (result is Map && result['success'] == true);
      if (ok) {
        debugPrint('✅ addBonusStars: secure RPC succeeded (+$amount stars)');
      } else {
        debugPrint('❌ Secure stars RPC rejected the request: $result');
      }
    } catch (e) {
      debugPrint('❌ Secure stars RPC exception. No fallback allowed. Error: $e');
    }
  }

  List<String> _getRelevantAreaIds(String areaId, List<Map<String, dynamic>> allAreas) {
    try {
      final selectedArea = allAreas.firstWhere(
        (a) => a['id'] == areaId,
        orElse: () => {},
      );

      if (selectedArea.isEmpty) return [areaId];

      final parentId = selectedArea['parent_id'] ?? selectedArea['id'];
      return allAreas
          .where((a) => a['id'] == parentId || a['parent_id'] == parentId)
          .map((a) => a['id'] as String)
          .toList();
    } catch (e) {
      debugPrint("Error in _getRelevantAreaIds: $e");
      return [areaId];
    }
  }

  // --- Account Management ---
  Future<void> deleteAccount() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      // Note: This usually requires an Edge Function with Service Role 
      // to delete from auth.users. Here we call an RPC to mark for deletion
      // or delete user-accessible data.
      await _client.rpc('request_account_deletion');
      
      // Logout the user after request
      await signOut();
    } catch (e) {
      debugPrint("Error requesting account deletion: $e");
      rethrow;
    }
  }

  // --- Admin/Management ---
  Future<void> resetAllPlayersProgress(String gameSlug) async {
    try {
      await _client.from('game_progress').update({
        'money_collected': 0,
        'current_rocket_tier': 1,
        'upgrades': {
          'engine_lv': 1,
          'fuel_lv': 1,
          'hull_lv': 1,
          'booster_lv': 0,
          'magnet_lv': 0,
        },
        'won_milestones': [],
        'last_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('game_slug', gameSlug);
      
      // Also reset leaderboard scores for the new season
      await _client.from('game_attempts').delete().eq('game_slug', gameSlug);
    } catch (e) {
      debugPrint("Error resetting players progress: $e");
      rethrow;
    }
  }

  // --- Theme ---
  Stream<Map<String, dynamic>?> getActiveThemeStream() {
    return _client
        .from('theme_presets')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .map((data) => data.isNotEmpty ? data.first : null);
  }
}




