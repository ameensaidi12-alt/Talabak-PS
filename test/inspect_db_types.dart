import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Inspect DB Types', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://ylpjqejnvhaqbdssjaof.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY',
    );
    final client = Supabase.instance.client;

    print('--- Global Categories ---');
    try {
      final gCats =
          await client.from('global_categories').select('name, vendor_type');
      for (var gc in gCats) {
        print('Global Category: ${gc['name']} - Type: ${gc['vendor_type']}');
      }
    } catch (e) {
      print('Could not fetch global_categories: $e');
    }

    print('--- Vendor Multi-Types ---');
    try {
      final multiTypes =
          await client.from('vendor_multi_types').select('vendor_id, type');
      for (var mt in multiTypes) {
        print('VendorMT: ${mt['vendor_id']} -> Type: ${mt['type']}');
      }
    } catch (e) {
      print('Could not fetch vendor_multi_types (maybe table missing?): $e');
    }

    print('--- Categories (Menu) ---');
    try {
      final cats = await client.from('categories').select().limit(5);
      for (var c in cats) {
        print('Menu Category: ${c['name']} - Content: $c');
      }
    } catch (e) {
      print('Could not fetch categories: $e');
    }

    print('--- Vendors Sample ---');
    try {
      final vs = await client.from('vendors').select().limit(5);
      for (var v in vs) {
        print('Vendor Row: ${v['name']} - Content: $v');
      }
    } catch (e) {
      print('Could not fetch vendors: $e');
    }
  });
}
