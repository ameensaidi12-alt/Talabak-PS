import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Mocking likely needed

void main() {
  test('Debug Vendor Menu', () async {
    // Mock SharedPreferences if needed by Supabase (usually not for basic client)
    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(
      url: 'https://ylpjqejnvhaqbdssjaof.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY',
    );
    final client = Supabase.instance.client;

    print('--- Fetching Vendors ---');
    final vendors = await client.from('vendors').select().limit(1);

    if (vendors.isEmpty) {
      print('No vendors found.');
      return;
    }

    final vendor = vendors.first;
    final vendorId = vendor['id'];
    print('Vendor: ${vendor['name']} (ID: $vendorId)');

    print('--- Fetching Menu ---');
    // Using the exact query structure from SupabaseService (minus product_options for brevity)
    final response = await client
        .from('products')
        .select('id, name, vendor_id, categories(*)')
        .eq('vendor_id', vendorId);

    final data = response as List;
    print('Products count: ${data.length}');

    Set<String> distinctCategories = {};

    for (var p in data) {
      final pid = p['id'];
      final pName = p['name'];
      final pVendor = p['vendor_id'];

      final cat = p['categories'];
      String catName = 'N/A';
      String catId = 'N/A';

      if (cat != null) {
        catName = cat['name'];
        catId = cat['id'];
        distinctCategories.add('$catName ($catId)');
      }

      if (pVendor != vendorId) {
        print(
            'CRITICAL: Product $pName ($pid) has vendor_id $pVendor, expected $vendorId');
      }
    }

    print('--- Distinct Categories Found ---');
    for (var c in distinctCategories) {
      print(c);
    }
  });
}
