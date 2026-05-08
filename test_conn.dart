import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

void main() async {
  print('Starting connection test...');
  final supabase = SupabaseClient(
    'https://ylpjqejnvhaqbdssjaof.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY',
  );

  try {
    print('Querying orders count...');
    final response = await supabase.from('orders').select('id').limit(1);
    print('Query successful! Result: $response');
  } catch (e) {
    print('Query failed: $e');
  }
  print('Test finished.');
  exit(0);
}
