import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'ui/widgets/network_connectivity_wrapper.dart';
import 'core/providers/cart_provider.dart';
import 'core/services/supabase_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_colors.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/deep_link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/local_log_service.dart';
import 'ui/screens/splash_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await LocalLogService.init();
    LocalLogService.log("BKGND_START: Payload Received -> Data: ${message.data}, Hybrid: ${message.notification != null}");
  } catch(e) {
    debugPrint("Failed to log background start: $e");
  }

  // 1. Initialize Firebase for the background isolate
  try {
    await Firebase.initializeApp();
  } catch (e) {
    LocalLogService.log("BKGND_FB_ERROR: $e");
  }

  // 2. Initialize AwesomeNotifications for the background process
  await AwesomeNotifications().initialize(null, [
    NotificationChannel(
      channelKey: 'alerts',
      channelName: 'Alerts',
      channelDescription: 'Notification channel for orders and messages',
      defaultColor: AppColors.primary,
      ledColor: Colors.white,
      importance: NotificationImportance.Max,
      channelShowBadge: true,
      playSound: true,
      criticalAlerts: true,
    ),
    NotificationChannel(
      channelKey: 'admin_call_channel_v2',
      channelName: 'Admin Calls',
      channelDescription: 'Notifications for new orders and admin alerts',
      defaultColor: AppColors.primary,
      ledColor: Colors.white,
      importance: NotificationImportance.Max,
      channelShowBadge: true,
      playSound: true,
      criticalAlerts: true,
    ),
  ]);

  // 3. Display manually ONLY if it is a data-only payload.
  // Since we use a hybrid payload, Firebase SDK will handle the OS notification automatically.
  // We skip creating it via AwesomeNotifications to prevent duplicate notifications.
  if (message.notification == null) {
    LocalLogService.log("BKGND_EXEC: Data-Only. Manually rendering with AwesomeNotifications.");
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: message.data['channel_id'] ?? 'alerts',
        title: message.data['notification_title'] ?? "تنبيه جديد",
        body: message.data['notification_body'] ?? "",
        notificationLayout: NotificationLayout.Default,
        payload: Map<String, String>.from(message.data),
        wakeUpScreen: true,
        category: (message.data['type'] == 'order' || message.data['type'] == 'order_status')
            ? NotificationCategory.Call 
            : NotificationCategory.Message,
      ),
    );
  } else {
    LocalLogService.log("BKGND_SKIP: Message is Hybrid. Native FCM displayed it. No action needed.");
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('chat_cache');
  await LocalLogService.init();
  LocalLogService.log("APP_START: Main initialized");

  try {
    // Initialize Firebase for all platforms including Windows
    await Firebase.initializeApp();
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }

  await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'alerts',
          channelName: 'Alerts',
          channelDescription: 'Notification channel for orders and messages',
          defaultColor: AppColors.primary,
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          criticalAlerts: true,
        ),
        NotificationChannel(
          channelKey: 'admin_call_channel_v2',
          channelName: 'Admin Calls',
          channelDescription: 'Notifications for new orders and admin alerts',
          defaultColor: AppColors.primary,
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          criticalAlerts: true,
        ),
      ],
      debug: true);

  await Supabase.initialize(
    url: 'https://ylpjqejnvhaqbdssjaof.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY',
  );

  final prefs = await SharedPreferences.getInstance();
  
  // Initialize global settings
  await SupabaseService().initializeSettings();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        Provider<SupabaseService>(create: (_) => SupabaseService()),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<DeepLinkService>(
          create: (_) => DeepLinkService(),
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
      ],
      child: const TalabakPSApp(),
    ),
  );
}

class TalabakPSApp extends StatefulWidget {
  const TalabakPSApp({super.key});

  @override
  State<TalabakPSApp> createState() => _TalabakPSAppState();
}

class _TalabakPSAppState extends State<TalabakPSApp> with WidgetsBindingObserver {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _initNotifications();
    _updatePresence();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.tokenRefreshed) {
        debugPrint("Supabase Auth Event: ${data.event}");
        _updatePresence();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updatePresence();
    }
  }

  void _updatePresence() {
    SupabaseService().updateUserPresence();
  }

  void _initNotifications() {
    if (_initialized) return;
    _initialized = true;
    
    // Use addPostFrameCallback to ensure context is ready to find providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationService>().initialize();
      context.read<DeepLinkService>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Talabak PS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            primaryColor: themeProvider.primaryColor,
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeProvider.primaryColor,
              primary: themeProvider.primaryColor,
              secondary: themeProvider.secondaryColor,
              surface: AppColors.surface,
              error: AppColors.error,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
            ),
            textTheme: GoogleFonts.cairoTextTheme(Theme.of(context).textTheme),
          ),
          builder: (context, child) {
            return SafeArea(
              top: false,
              bottom: true,
              child: NetworkConnectivityWrapper(
                child: Directionality(
                  textDirection: TextDirection.rtl, 
                  child: child!
                ),
              ),
            );
          },
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          home: const SplashScreen(),
        );
      },
    );
  }
}
