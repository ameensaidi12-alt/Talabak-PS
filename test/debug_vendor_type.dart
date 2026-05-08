import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Debug Vendor Type', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://ylpjqejnvhaqbdssjaof.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY',
    );
    final client = Supabase.instance.client;

    print('--- Fetching Vendors ---');
    final vendors =
        await client.from('vendors').select('id, name, type').limit(5);

    if (vendors.isEmpty) {
      print("No vendors found.");
      return;
    }

    for (var v in vendors) {
      print("Vendor: ${v['name']} (${v['id']}) - Type: ${v['type']}");
    }

    // Pick one that looks like a market
    var vendor = vendors.firstWhere(
        (v) =>
            v['type'] == 'supermarket' ||
            v['type'] == 'brand' ||
            v['type'] == 'retail',
        orElse: () => vendors.first);

    // Safety check if no market found
    if (vendor['type'] != 'supermarket' &&
        vendor['type'] != 'brand' &&
        vendor['type'] != 'retail') {
      print(
          "No market vendor found in first 5. Trying explicit search for 'supermarket'...");
      final markets = await client
          .from('vendors')
          .select('id, name, type')
          .eq('type', 'supermarket')
          .limit(1);
      if (markets.isNotEmpty) vendor = markets.first;
    }

    final vendorId = vendor['id'];
    print(
        "Selected Vendor for Test: ${vendor['name']} (Type: ${vendor['type']})");

    print('--- Fetching Products & Categories ---');
    final response = await client
        .from('products')
        .select('id, name, categories(*)')
        .eq('vendor_id', vendorId)
        .limit(10);

    final List<dynamic> data = response;
    for (var p in data) {
      final cat = p['categories'];
      if (cat != null) {
        print(
            "Product: ${p['name']} -> Category: ${cat['name']} (ID: ${cat['id']})");
        // Check keys available in category
        final Map<String, dynamic> catMap = cat;
        if (catMap.containsKey('vendor_type')) {
          print("   - VendorType: ${catMap['vendor_type']}");
        } else {
          print("   - VendorType: MISSING from 'categories'");
        }
        if (catMap.containsKey('vendor_id')) {
          print("   - VendorID: ${catMap['vendor_id']}");
        }
      } else {
        print("Product: ${p['name']} -> No Category");
      }
    }
  });
}
