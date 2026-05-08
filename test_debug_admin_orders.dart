import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
    'https://ylpjqejnvhaqbdssjaof.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY',
  );

  print('--- FETCHING ALL ORDERS ---');
  try {
    final List<dynamic> response = await supabase.from('orders').select('''
          *,
          vendors(name),
          customer:profiles!orders_user_id_fkey(full_name, phone),
          order_items(*)
        ''').order('created_at', ascending: false);

    print('Total orders in DB: ${response.length}');

    for (var i = 0; i < response.length; i++) {
      final order = response[i];
      print(
          'Order ${i + 1}: ID=${order['id']}, Status=${order['status']}, VendorID=${order['vendor_id']}, VendorName=${order['vendors']?['name']}');
    }

    // Check if there are any parsing issues by simulating the Order.fromJson logic
    print('\n--- SIMULATING Order.fromJson FOR ALL ---');
    int failCount = 0;
    for (var i = 0; i < response.length; i++) {
      try {
        final order = response[i];
        // Simplified fields to check for nulls or types
        final id = order['id'];
        final vendorId = order['vendor_id'];
        final status = order['status'];
        final subtotal = (order['subtotal'] ?? 0).toDouble();

        if (id == null || vendorId == null || status == null) {
          print('MISSING CRITICAL FIELD: Order Index $i');
          failCount++;
        }
      } catch (e) {
        print('PARSING ERROR at index $i: $e');
        failCount++;
      }
    }
    print('Failed parsing simulation: $failCount');

    // Test updates for a couple of different vendors
    if (response.length >= 2) {
      print('\n--- TESTING STATUS UPDATES ---');
      // Find two different vendors
      String? vendor1Id = response[0]['vendor_id'];
      String? vendor2Id;
      for (var order in response) {
        if (order['vendor_id'] != vendor1Id) {
          vendor2Id = order['vendor_id'];
          break;
        }
      }

      for (var vid in [vendor1Id, vendor2Id]) {
        if (vid == null) continue;
        final orderToUpdate = response.firstWhere((o) => o['vendor_id'] == vid);
        final currentStatus = orderToUpdate['status'];
        final targetStatus =
            currentStatus == 'confirmed' ? 'preparing' : 'confirmed';

        print(
            'Attempting to update Order ${orderToUpdate['id']} (Vendor: ${orderToUpdate['vendors']?['name']}) to "$targetStatus"...');
        try {
          await supabase
              .from('orders')
              .update({'status': targetStatus}).eq('id', orderToUpdate['id']);
          print('SUCCESS for Vendor $vid');
          // Revert back
          await supabase
              .from('orders')
              .update({'status': currentStatus}).eq('id', orderToUpdate['id']);
        } catch (e) {
          print(
              'FAILURE for Vendor $vid (Vendor Name: ${orderToUpdate['vendors']?['name']}): $e');
        }
      }
    }
  } catch (e) {
    print('CRITICAL ERROR: $e');
  }

  exit(0);
}
