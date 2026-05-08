import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Check Columns', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://ylpjqejnvhaqbdssjaof.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY',
    );
    final client = Supabase.instance.client;
    final res = await client.from('categories').select().limit(1);
    if (res.isNotEmpty) {
      print('Categories Columns: ${res.first.keys.toList()}');
    } else {
      print('Categories table is empty');
    }
  });
}
