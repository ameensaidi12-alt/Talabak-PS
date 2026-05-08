import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import 'deep_link_service.dart';
import 'local_log_service.dart';

class NotificationService {
  final _supabase = Supabase.instance.client;
  static String? _lastHandledId; // Global flag to prevent double-handling in the same session

  Future<void> initialize() async {
    // 1. Listen for notification actions (taps)
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
    );

    // 2. Immediate Listeners (Register before any awaits to catch early events)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      LocalLogService.log("FOREGROUND: Message received ${message.messageId}");
      _showNotificationPopup(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      LocalLogService.log("CLICK: App opened from background ${message.messageId}");
      _handleMessageNavigation(message.data);
    });

    // 3. Immediate Cold Start Check (Check before permissions to avoid blocking)
    
    // 3a. Check AwesomeNotifications (This is likely where our background-displayed notifications go)
    AwesomeNotifications().getInitialNotificationAction().then((receivedAction) {
      if (receivedAction != null && receivedAction.payload != null) {
        final messageId = receivedAction.id?.toString() ?? receivedAction.payload!['id'];
        if (messageId != null && _lastHandledId == messageId) return;
        _lastHandledId = messageId;
        
        LocalLogService.log("COLD_START (Awesome): App launched from notification ${receivedAction.id}");
        _handleMessageNavigation(receivedAction.payload!);
      }
    });

    // 3b. Check Firebase (Fallback for native OS-handled push)
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        if (_lastHandledId == message.messageId) return;
        _lastHandledId = message.messageId;

        LocalLogService.log("COLD_START (FCM): App launched from notification ${message.messageId}");
        _handleMessageNavigation(message.data);
      }
    });

    // 4. Request Firebase Permissions (Non-blocking for the logic above)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final firebaseMessaging = FirebaseMessaging.instance;
      LocalLogService.log("INIT: Requesting FCM Permissions...");
      
      firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      ).then((settings) async {
        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          LocalLogService.log("INIT: FCM Permission Granted");

          String? token = await firebaseMessaging.getToken();
          if (token != null) {
            LocalLogService.log("INIT: Got FCM Token: ${token.substring(0, 10)}...");
            await _saveToken(token);
          }

          firebaseMessaging.onTokenRefresh.listen(_saveToken);
          await firebaseMessaging.subscribeToTopic('all_customers');
          debugPrint("Subscribed to all_customers topic");
        } else {
          LocalLogService.log("INIT: FCM Permission Denied/Declined");
        }
      });
    }

    // 5. Request AwesomeNotifications Permission (For local tray icons)
    AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        LocalLogService.log("INIT: AwesomeNotifications permission not allowed, requesting...");
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });
  }

  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
    // This is called when an AwesomeNotification is tapped
    if (receivedAction.payload != null) {
      _handleMessageNavigation(receivedAction.payload!);
    }
  }

  static Future<void> _handleMessageNavigation(Map<String, dynamic> data) async {
    final type = data['type'];
    final actionType = data['action_type'];
    final actionId = data['action_id'] ?? data['id']; // Support both keys
    final messageId = data['google.message_id'] ?? data['id'];

    if (messageId != null) {
      if (_lastHandledId == messageId) {
        debugPrint("Skipping already handled notification: $messageId");
        return;
      }
      _lastHandledId = messageId;
    }

    debugPrint("Handling Navigation: type=$type, actionType=$actionType, actionId=$actionId");

    String? url;
    if (type == 'order' || type == 'order_status') {
      url = "hatstar://order?id=$actionId";
    } else if (actionType == 'vendor') {
      url = "hatstar://shop?id=$actionId";
    } else if (actionType == 'game') {
      url = "hatstar://game?slug=$actionId";
    }

    if (url != null) {
      int attempts = 0;
      while (navigatorKey.currentContext == null && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }

      final context = navigatorKey.currentContext;
      if (context != null) {
        try {
          context.read<DeepLinkService>().handleUri(Uri.parse(url));
        } catch (e) {
          debugPrint("Error navigating from notification: $e");
        }
      }
    }
  }

  void _showNotificationPopup(RemoteMessage message) {
    if (message.notification != null || message.data.isNotEmpty) {
      final isOrder = message.data['type'] == 'order' ||
          message.data['type'] == 'order_status';

      AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: message.data['channel_id'] ?? 'alerts', // Dynamic from server
          title: message.notification?.title ?? message.data['notification_title'] ?? "تنبيه جديد",
          body: message.notification?.body ?? message.data['notification_body'] ?? "",
          notificationLayout: NotificationLayout.Default,
          payload: Map<String, String>.from(message.data),
          wakeUpScreen: true,
          category: isOrder
              ? NotificationCategory.Call   // Louder & higher priority for orders
              : NotificationCategory.Message,
        ),
      );
    }
  }

  Future<void> _saveToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('user_fcm_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'device_type': kIsWeb ? 'web' : Platform.operatingSystem,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id, token');
      debugPrint('FCM Token saved to Supabase');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }
}

