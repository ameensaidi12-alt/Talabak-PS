import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../../core/theme/app_colors.dart';
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WebViewScreen({super.key, required this.url, required this.title});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  // Use ValueNotifier to avoid rebuilding the entire WebViewWidget on progress updates
  final ValueNotifier<bool> _isLoading = ValueNotifier(true);
  final ValueNotifier<double> _progress = ValueNotifier(0.0);

  Timer? _timeoutTimer;
  String? _lastLoadedUrl;
  bool _hasError = false;
  bool _showBypassButton = false;
  Timer? _bypassTimer;
  final List<String> _jsLogs = [];
  bool _isAdmin = false;
  bool _isLoggingEnabled = false; 
  bool _isUnsupportedPlatform = false;

  @override
  void initState() {
    super.initState();
    _checkPlatform();
    _checkAdminStatus();
    if (!_isUnsupportedPlatform) {
      _initController();
      _startTimeout();
      _startBypassTimer();
    }
  }

  void _checkPlatform() {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      setState(() {
        _isUnsupportedPlatform = true;
      });
    }
  }

  Future<void> _checkAdminStatus() async {
    // 1. FAST PATH: Use current session without network refresh if possible
    final session = Supabase.instance.client.auth.currentSession;
    final user = session?.user;

    if (user == null) return;

    final appRole = user.appMetadata['role'];
    final userRole = user.userMetadata?['role'];
    final email = user.email?.toLowerCase() ?? '';

    setState(() {
      _isAdmin =
          appRole == 'admin' || userRole == 'admin' || email.contains('admin');
    });

    debugPrint("👮 [WebView] Admin status determined: $_isAdmin");
  }

  void _startBypassTimer() {
    _bypassTimer?.cancel();
    // Only show bypass for admins
    if (!_isAdmin) return;

    _bypassTimer = Timer(const Duration(seconds: 10), () {
      if (_isLoading.value && mounted) {
        setState(() {
          _showBypassButton = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _bypassTimer?.cancel();
    _isLoading.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _loadLegalContent(String url) async {
    try {
      _isLoading.value = true;
      final uri = Uri.parse(url);
      final slug = uri.queryParameters['slug'] ?? 'privacy';

      debugPrint("📄 [WebView] Fetching legal content for: $slug");

      final response = await Supabase.instance.client.functions.invoke(
        'legal',
        queryParameters: {'slug': slug},
        headers: {'Accept': 'application/json'},
      );

      final data = response.data;
      if (data != null && data['html'] != null) {
        final String html = data['html'];
        await _controller.loadHtmlString(html);
        debugPrint("✅ [WebView] Legal content loaded successfully");
      } else {
        throw "بيانات غير صالحة المستلمة من السيرفر";
      }
    } catch (e) {
      debugPrint("❌ [WebView] Error loading legal content: $e");
      _showErrorDialog("فشل في تحميل سياسة الخصوصية. يرجى المحاولة لاحقاً.");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    } finally {
      if (mounted) {
        _isLoading.value = false;
      }
    }
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 20), () {
      if (_isLoading.value && mounted) {
        debugPrint("⏰ WebView Timeout reached for: ${widget.url}");
        _isLoading.value = false;
        setState(() {
          _hasError = true;
        });
        _showErrorDialog(
          "استغرق تحميل المتجر وقتاً طويلاً جداً. يرجى التحقق من اتصال الإنترنت أو المحاولة لاحقاً.",
        );
      }
    });
  }

  void _initController() {
    if (_isUnsupportedPlatform) return;
    
    // 1. Initialize Controller IMMEDIATELY
    _controller = WebViewController();

    try {
      // 2. Get current Auth Token
      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken;
      final refreshToken = session?.refreshToken;

      // 3. Build final URL
      String finalUrl = widget.url;
      if (finalUrl.contains('?')) {
        finalUrl += '&source=mob_app';
      } else {
        finalUrl += '?source=mob_app';
      }

      if (token != null) {
        finalUrl += '&token=${Uri.encodeComponent(token)}';
        if (refreshToken != null) {
          finalUrl += '&refresh=${Uri.encodeComponent(refreshToken)}';
        }
      }

      debugPrint("🌐 [WebView] Final constructed URL: $finalUrl");

      // 4. CHECK FOR LEGAL PAGE (Dynamic Handling)
      if (finalUrl.contains('/functions/v1/legal')) {
        _loadLegalContent(finalUrl);
      } else {
        // Fix for potential "No host specified" error: ensure URL is absolute
        final targetUri = Uri.tryParse(finalUrl);
        if (targetUri != null && targetUri.hasScheme && targetUri.host.isNotEmpty) {
          _controller.loadRequest(targetUri);
        } else {
          debugPrint("❌ [WebView] Invalid or local-only URL: $finalUrl");
          _showErrorDialog("رابط غير صالح أو محلي فقط.");
        }
      }

      // 5. Configure Controller
      _controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
        )
        ..setBackgroundColor(const Color(0xFFFFFFFF))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              _progress.value = progress / 100;
            },
            onPageStarted: (String url) {
              debugPrint("🌐 [WebView] Page started loading: $url");
              _jsLogs.clear();
              _jsLogs.add("--- New Page Load: ${DateTime.now()} ---");
              if (_isAdmin && _isLoggingEnabled) {
                _controller.runJavaScript("""
                  (function() {
                    var oldLog = console.log;
                    console.log = function() {
                      var msg = Array.from(arguments).join(' ');
                      LogBridge.postMessage(JSON.stringify({type: 'log', message: msg}));
                      oldLog.apply(console, arguments);
                    };
                  })();
                """);
              }
              _isLoading.value = true;
              if (mounted) {
                setState(() {
                  _hasError = false;
                  _lastLoadedUrl = url;
                });
              }
            },
            onPageFinished: (String url) async {
              _timeoutTimer?.cancel();
              _bypassTimer?.cancel();
              if (mounted) {
                _isLoading.value = false;
                setState(() {
                  _showBypassButton = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (error.isForMainFrame ?? true) {
                _timeoutTimer?.cancel();
                if (mounted) {
                  _isLoading.value = false;
                  setState(() {
                    _hasError = true;
                  });
                  _showErrorDialog(
                    "خطأ في الاتصال: ${error.description}\n(كود الخطأ: ${error.errorCode})",
                  );
                }
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              return NavigationDecision.navigate;
            },
          ),
        )
        ..addJavaScriptChannel(
          'AuthBridge',
          onMessageReceived: (JavaScriptMessage message) async {
            try {
              final data = jsonDecode(message.message);
              if (data['type'] == 'error') return;
              final rToken = data['refresh_token'];
              if (rToken != null) {
                await Supabase.instance.client.auth.setSession(rToken);
              }
            } catch (e) {
              debugPrint("❌ [WebView] Bridge error: $e");
            }
          },
        )
        ..addJavaScriptChannel(
          'LogBridge',
          onMessageReceived: (JavaScriptMessage message) {
            if (!_isAdmin) return;
            try {
              final data = jsonDecode(message.message);
              final type = data['type']?.toString().toUpperCase() ?? 'LOG';
              final msg = data['message'] ?? '';
              _jsLogs.add("[$type] $msg");
            } catch (e) {}
          },
        );

      _controller.loadRequest(Uri.parse(finalUrl));
    } catch (e) {
      debugPrint("❌ [WebView] Initialization error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  Future<void> _launchInBrowser(String url) async {
    final uri = Uri.parse(url);
    try {
      // Direct launch without canLaunch check (which is often unreliable)
      final success = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!success) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      debugPrint("❌ Failed to launch URL: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("تعذر فتح المتصفح: $e")));
      }
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    debugPrint("🚨 [WebView] Showing Error Dialog: $message");

    // Only show SnackBar with browser action for Admin
    if (_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: "فتح في المتصفح",
            onPressed: () => _launchInBrowser(widget.url),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('خطأ في تحميل المتجر'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (_isAdmin) ...[
                const SizedBox(height: 12),
                const Divider(),
                const Text(
                  "جرب فتح المتجر في المتصفح الخارجي إذا استمرت المشكلة",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          if (_isAdmin)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _launchInBrowser(widget.url);
              },
              child: const Text('فتح في المتصفح'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _isLoading.value = true;
              setState(() {
                _hasError = false;
                _progress.value = 0;
              });
              _startTimeout();
              _controller.reload();
            },
            child: const Text('إعادة المحاولة'),
          ),
          if (_isAdmin)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showLogConsole();
              },
              child: const Text('سجلات البيانات'),
            ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isUnsupportedPlatform) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.open_in_browser, size: 80, color: Colors.blueGrey),
                const SizedBox(height: 24),
                Text(
                  "هذا الجزء يتطلب هاتفاً محمولاً",
                  style: GoogleFonts.cairo(fontSize: 20, fontStyle: FontStyle.normal, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  "متصفح النظام المدمج غير مدعوم على ويندوز حالياً. هل تود العرض في متصفح خارجي؟",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _launchInBrowser(widget.url),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("فتح في المتصفح الخارجي", style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isAdmin) ...[
            IconButton(
              icon: Icon(Icons.open_in_browser, color: AppColors.primary),
              tooltip: "فتح في المتصفح الخارجي",
              onPressed: () => _launchInBrowser(widget.url),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black),
              onSelected: (value) async {
                switch (value) {
                  case 'refresh':
                    _isLoading.value = true;
                    // Reset errors if manually refreshing
                    setState(() {
                      _hasError = false;
                    });
                    _progress.value = 0;
                    _startTimeout();
                    _controller.reload();
                    break;
                  case 'browser':
                    _launchInBrowser(widget.url);
                    break;
                  case 'logs':
                    _showLogConsole();
                    break;
                  case 'clear':
                    final cookieManager = WebViewCookieManager();
                    await cookieManager.clearCookies();
                    await _controller.clearCache();
                    await _controller.clearLocalStorage();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("تم مسح ذاكرة التخزين المؤقت"),
                      ),
                    );
                    _controller.reload();
                    break;
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: widget.url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("تم نسخ الرابط")),
                    );
                    break;
                  case 'toggle_logs':
                    setState(() {
                      _isLoggingEnabled = !_isLoggingEnabled;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isLoggingEnabled
                              ? "تم تفعيل تسجيل البيانات (التغيير سيظهر بعد التحديث)"
                              : "تم تعطيل تسجيل البيانات",
                        ),
                      ),
                    );
                    if (_isLoggingEnabled) {
                      _controller.reload(); // Must reload to inject the JS
                    }
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh),
                      SizedBox(width: 8),
                      Text("إعادة تحميل"),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'browser',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_browser),
                      SizedBox(width: 8),
                      Text("فتح في المتصفح"),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline),
                      SizedBox(width: 8),
                      Text("مسح الذاكرة"),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logs',
                  child: Row(
                    children: [
                      Icon(Icons.terminal),
                      SizedBox(width: 8),
                      Text("عرض سجلات الأخطاء"),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.copy),
                      SizedBox(width: 8),
                      Text("نسخ الرابط"),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle_logs',
                  child: Row(
                    children: [
                      Icon(
                        _isLoggingEnabled
                            ? Icons.bug_report
                            : Icons.bug_report_outlined,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isLoggingEnabled
                            ? "تعطيل سجلات البيانات"
                            : "تفعيل سجلات البيانات",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // IMPORTANT: WebViewWidget is built once (or rarely) since controller doesn't change
          Opacity(
            opacity: _hasError ? 0 : 1,
            child: WebViewWidget(controller: _controller),
          ),

          // Loading Overlay - listening to ValueNotifiers
          ValueListenableBuilder<bool>(
            valueListenable: _isLoading,
            builder: (context, isLoading, child) {
              if (!isLoading) return const SizedBox();
              return Stack(
                children: [
                  // Progress bar at the top (Only for Admin)
                  if (_isAdmin)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _progress,
                        builder: (context, progress, _) {
                          return LinearProgressIndicator(
                            value: progress > 0 ? progress : null,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                            minHeight: 3,
                          );
                        },
                      ),
                    ),
                  // Centered spinner (For everyone)
                  Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ],
              );
            },
          ),

          if (_hasError) // Removed isLoading checks here, logic handled in setState
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 80,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "تعذر تحميل المتجر",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "يبدو أن هناك مشكلة في الموقع أو اتصال الإنترنت.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _startTimeout();
                          _startBypassTimer();
                          _controller.reload();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "إعادة المحاولة",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _launchInBrowser(widget.url),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            "فتح في المتصفح الخارجي",
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _showLogConsole,
                        child: const Text(
                          "عرض البيانات التقنية (Technical Logs)",
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FadeInWidget extends StatefulWidget {
  final Widget child;
  const FadeInWidget({super.key, required this.child});

  @override
  State<FadeInWidget> createState() => _FadeInWidgetState();
}

class _FadeInWidgetState extends State<FadeInWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}

extension on _WebViewScreenState {
  void _showLogConsole() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Technical Logs (JavaScript)",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: _jsLogs.isEmpty
                  ? const Center(
                      child: Text(
                        "No logs captured yet...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _jsLogs.length,
                      itemBuilder: (context, index) {
                        final log = _jsLogs[index];
                        final isError =
                            log.contains('[ERROR]') ||
                            log.contains('[EXCEPTION]');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: isError
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _jsLogs.join('\n')));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("تم نسخ السجلات")));
              },
              child: const Text("نسخ السجلات (Copy Logs)"),
            ),
          ],
        ),
      ),
    );
  }
}
