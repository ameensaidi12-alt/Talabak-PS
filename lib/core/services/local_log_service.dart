import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class LocalLogService {
  static const String _boxName = 'debug_logs';
  static const String _prefsBoxName = 'app_prefs';

  static bool? _cachedEnabled;

  static Future<void> init() async {
    await Hive.openBox(_boxName);
    await Hive.openBox(_prefsBoxName);
    // Cache the status at startup
    _isLoggingEnabled();
  }

  /// Updates whether logging is enabled for this device.
  /// Usually set based on the user's role (admin = enabled).
  static Future<void> setLoggingEnabled(bool enabled) async {
    try {
      final box = Hive.box(_prefsBoxName);
      await box.put('is_logging_enabled', enabled);
      _cachedEnabled = enabled; // Update cache
    } catch (e) {
      print("Failed to set logging status: $e");
    }
  }

  static bool _isLoggingEnabled() {
    // 1. Check Cache first (Fastest)
    if (_cachedEnabled != null) return _cachedEnabled!;

    // Always enable logs in debug mode (development)
    if (kDebugMode) {
      _cachedEnabled = true;
      return true;
    }
    
    try {
      final box = Hive.box(_prefsBoxName);
      _cachedEnabled = box.get('is_logging_enabled', defaultValue: false);
      return _cachedEnabled!;
    } catch (e) {
      return false;
    }
  }

  static void log(String message) {
    // 1. Check if logging is allowed for this user/mode (Instant check)
    if (!_isLoggingEnabled()) {
      return;
    }

    print("DEBUG_LOG: $message");
    
    try {
      final box = Hive.box(_boxName);
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final entry = {
        'timestamp': timestamp,
        'message': message,
      };
      
      final rawLogs = box.get('logs', defaultValue: []) as List;
      final logs = rawLogs.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      logs.add(entry);
      
      // Keep only last 200 logs
      if (logs.length > 200) {
        logs.removeRange(0, logs.length - 200);
      }
      
      box.put('logs', logs);
    } catch (e) {
      print("Failed to save local log: $e");
    }
  }

  static List<Map<String, dynamic>> getLogs() {
    try {
      final box = Hive.box(_boxName);
      final rawLogs = box.get('logs', defaultValue: []) as List;
      return rawLogs.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      return [{'timestamp': 'Error', 'message': 'Could not read logs: $e'}];
    }
  }

  static Future<void> clear() async {
    final box = Hive.box(_boxName);
    await box.put('logs', []);
  }
}
