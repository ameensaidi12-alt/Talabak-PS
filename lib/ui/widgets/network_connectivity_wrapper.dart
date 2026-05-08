import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import '../../core/theme/app_colors.dart';

class NetworkConnectivityWrapper extends StatefulWidget {
  final Widget child;

  const NetworkConnectivityWrapper({super.key, required this.child});

  @override
  State<NetworkConnectivityWrapper> createState() => _NetworkConnectivityWrapperState();
}

class _NetworkConnectivityWrapperState extends State<NetworkConnectivityWrapper> with WidgetsBindingObserver {
  bool _hasInternet = true;
  late StreamSubscription<InternetStatus> _subscription;
  Timer? _verificationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialConnection();
    _subscription = InternetConnection().onStatusChange.listen((InternetStatus status) {
      if (status == InternetStatus.connected) {
        // Internet is back, dismiss immediately
        _verificationTimer?.cancel();
        if (mounted && !_hasInternet) {
          setState(() {
            _hasInternet = true;
          });
        }
      } else {
        // Connection dropped, wait 3 seconds to confirm before showing overlay
        _startVerificationTimer();
      }
    });
  }

  void _startVerificationTimer() {
    _verificationTimer?.cancel();
    _verificationTimer = Timer(const Duration(seconds: 3), () async {
      final hasInternet = await InternetConnection().hasInternetAccess;
      if (mounted && !hasInternet) {
        setState(() {
          _hasInternet = false;
        });
      }
    });
  }

  Future<void> _checkInitialConnection() async {
    final hasInternet = await InternetConnection().hasInternetAccess;
    if (mounted) {
      if (hasInternet) {
        setState(() {
          _hasInternet = true;
        });
        _verificationTimer?.cancel();
      } else {
        // If we currently have internet (or don't know yet), don't show the error immediately.
        // Let the verification timer confirm it.
        _startVerificationTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    _verificationTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check immediately for 'true', but be lenient with 'false'
      _checkInitialConnection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_hasInternet)
          Positioned.fill(
            child: Material(
              color: Colors.white,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 120,
                          color: AppColors.primary.withOpacity(0.8),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          "لا يوجد اتصال بالإنترنت",
                          style: GoogleFonts.cairo(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "يرجى التحقق من اتصال شبكة Wi-Fi أو بيانات الجوال والمحاولة مرة أخرى.",
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              setState(() {
                                _hasInternet = true; // Temporary assume true to show loader
                              });
                              final hasInternet = await InternetConnection().hasInternetAccess;
                              await Future.delayed(const Duration(milliseconds: 500));
                              if (mounted) {
                                setState(() {
                                  _hasInternet = hasInternet;
                                });
                              }
                            },
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            label: Text(
                              "حاول مرة أخرى",
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
