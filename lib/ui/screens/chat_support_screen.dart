import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';

class ChatSupportScreen extends StatefulWidget {
  const ChatSupportScreen({super.key});

  @override
  State<ChatSupportScreen> createState() => _ChatSupportScreenState();
}

class _ChatSupportScreenState extends State<ChatSupportScreen> {
  final _supabaseService = SupabaseService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Optimistic UI updates
  final List<Map<String, dynamic>> _optimisticMessages = [];

  // Streams
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  Stream<Map<String, dynamic>?>? _statusStream;
  Stream<bool>? _supportOnlineStream;
  StreamSubscription? _chatSummarySub;

  bool _isTyping = false;
  bool _isChatEnded = false;
  DateTime? _lastClearedAt;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _setupFocusListener();
    _setupChatSummaryListener();
    _supabaseService.markMessagesAsRead();
  }

  void _setupStreams() {
    // 50 messages limit is enough for typical support session
    _messagesStream = _supabaseService.getSupportMessages(limit: 50);
    _statusStream = _supabaseService.getChatStatus();
    _supportOnlineStream = _supabaseService.getSupportOnlineStream();

    // ✅ NEW: Automatic "Read" status when message arrives while screen is active
    _messagesStream?.listen((messages) {
      if (!mounted) return;
      final hasUnreadAdmin =
          messages.any((m) => m['is_from_admin'] == true && m['is_read'] != true);
      if (hasUnreadAdmin) {
        _supabaseService.markMessagesAsRead();
      }
    });
  }

  void _setupFocusListener() {
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isTyping) _stopTyping();
      if (_focusNode.hasFocus) _supabaseService.markMessagesAsRead();
    });
  }

  void _setupChatSummaryListener() {
    _chatSummarySub = _supabaseService.getChatSummaryStream().listen((summary) {
      if (summary != null && mounted) {
        final ended = summary['is_chat_ended'] == true;
        final clearedAtStr = summary['last_cleared_at'] as String?;
        final clearedAt =
            clearedAtStr != null ? DateTime.tryParse(clearedAtStr) : null;

        if (ended != _isChatEnded || clearedAt != _lastClearedAt) {
          setState(() {
            _isChatEnded = ended;
            _lastClearedAt = clearedAt;
          });
          if (ended && ended != _isChatEnded) {
            // Chat ended logic
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("تم إنهاء الجلسة من قبل الدعم.")),
              );
              // We don't force pop immediately, let them see it ended
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _stopTyping();
    _typingTimer?.cancel();
    _chatSummarySub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTypingChanged(String value) {
    if (!_isTyping) {
      _isTyping = true;
      _supabaseService.updateTypingStatus(isTyping: true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () => _stopTyping());
  }

  void _stopTyping() {
    if (_isTyping) {
      _isTyping = false;
      _supabaseService.updateTypingStatus(isTyping: false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    // Small delay to allow list to render new item
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    final clientId = DateTime.now().millisecondsSinceEpoch.toString();

    final optimisticMsg = {
      'client_id': clientId,
      'message': text,
      'is_from_admin': false,
      'status': 'sending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    setState(() {
      _optimisticMessages.insert(0, optimisticMsg);
      _messageController.clear();
    });

    _scrollToBottom();
    _stopTyping();

    try {
      await _supabaseService.sendSupportMessage(text, clientId: clientId);
      // Success: The stream will eventually deliver the message with the matching client_id.
      // We handle the merging in the build method.
    } catch (e) {
      if (mounted) {
        setState(
          () => _optimisticMessages.removeWhere(
            (m) => m['client_id'] == clientId,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل الإرسال: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startNewChat() async {
    try {
      HapticFeedback.mediumImpact();
      await _supabaseService.startNewChat();
      if (mounted) {
        setState(() {
          _isChatEnded = false;
          _optimisticMessages.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم بدء محادثة جديدة بنجاح"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل بدء محادثة جديدة: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime _safeParse(String? date) {
    if (date == null || date.isEmpty) return DateTime.now();
    return DateTime.tryParse(date)?.toLocal() ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "حدث خطأ في تحميل المحادثة",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                final serverMessagesRaw = snapshot.data ?? [];

                // Filter out messages that were sent BEFORE the chat was last cleared
                final serverMessages = serverMessagesRaw.where((m) {
                  if (_lastClearedAt == null) return true;
                  final createdAt = _safeParse(m['created_at']);
                  return createdAt.isAfter(_lastClearedAt!);
                }).toList();

                // Merge optimistic: Remove optimistic if present in server (by client_id)
                final serverClientIds = serverMessages
                    .map((m) => m['client_id']?.toString())
                    .where((id) => id != null)
                    .toSet();

                // Keep only optimistic messages that are NOT yet in the server list
                final pendingOptimistic = _optimisticMessages
                    .where((m) => !serverClientIds.contains(m['client_id']))
                    .toList();

                // Combined list: Pending first (since reverse: true, index 0 is bottom), then server messages
                final combined = [...pendingOptimistic, ...serverMessages];

                if (combined.isEmpty &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Bottom to top
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  itemCount: combined.length + (combined.isEmpty ? 0 : 2),
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    // Header (Welcome) is at the end of list (since reverse=true)
                    if (index == combined.length + 1)
                      return _buildWelcomeHeader();

                    if (index == combined.length) {
                      return const SizedBox(height: 10);
                    }

                    final msg = combined[index];
                    final isAdmin = msg['is_from_admin'] == true;
                    // Check status
                    bool isOptimistic = msg['status'] == 'sending' ||
                        pendingOptimistic.contains(msg);

                    bool showDate = false;
                    // Logic for date separator (compare with next item in list, which is previous in time)
                    if (index == combined.length - 1) {
                      showDate = true;
                    } else {
                      final currentMsgDate = _safeParse(msg['created_at']);
                      final prevMsgDate = _safeParse(
                        combined[index + 1]['created_at'],
                      ); // Next in list is older
                      if (currentMsgDate.day != prevMsgDate.day)
                        showDate = true;
                    }

                    return RepaintBoundary(
                      key: ValueKey(msg['client_id'] ?? msg['id'] ?? index),
                      child: Column(
                        children: [
                          if (showDate) _buildDateHeader(msg['created_at']),
                          _buildMessageBubble(msg, isAdmin, isOptimistic),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildAdminTypingIndicator(),
          if (_isChatEnded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              color: Colors.amber[50],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18, color: Colors.amber[900]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "تم إنهاء هذه المحادثة من قبل الدعم الفني.",
                          style: TextStyle(
                            color: Colors.amber[900],
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startNewChat,
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      label: const Text(
                        "بدء محادثة جديدة",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: AppColors.primary,
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: StreamBuilder<bool>(
        stream: _supportOnlineStream,
        builder: (context, snapshot) {
          final isAdminOnline = snapshot.data ?? false;

          return Column(
            children: [
              const Text(
                "الدعم الفني",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Colors.black,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isAdminOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isAdminOnline ? "متصل الآن" : "غير متصل",
                    style: TextStyle(
                      fontSize: 10,
                      color: isAdminOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Container(
      margin: const EdgeInsets.only(top: 30, bottom: 20, left: 20, right: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(AppColors.glowIntensity),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.support_agent, color: Colors.white, size: 38),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "فريق دعم طلبك",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            "أهلاً بك! نحن هنا لمساعدتك في أي استفسار. نرد عادةً خلال دقائق بمجرد وصول استفسارك.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(String? createdAt) {
    final date = _safeParse(createdAt);
    final now = DateTime.now();
    String formatted = (date.day == now.day &&
            date.month == now.month &&
            date.year == now.year)
        ? "اليوم"
        : intl.DateFormat('d MMMM yyyy', 'ar').format(date);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        formatted,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> msg,
    bool isAdmin,
    bool isOptimistic,
  ) {
    final time = intl.DateFormat('HH:mm').format(_safeParse(msg['created_at']));

    return Align(
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 6),
        decoration: BoxDecoration(
          gradient: isAdmin
              ? null
              : LinearGradient(
                  colors: isOptimistic
                      ? [
                          AppColors.primary.withOpacity(0.7),
                          const Color(0xFFE53935).withOpacity(0.7),
                        ]
                      : [AppColors.primary, const Color(0xFFE53935)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isAdmin ? Colors.white : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isAdmin ? Radius.zero : const Radius.circular(18),
            bottomRight: isAdmin ? const Radius.circular(18) : Radius.zero,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg['message'] ?? '',
              style: TextStyle(
                color: isAdmin ? Colors.black87 : Colors.white,
                fontSize: 15.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: (isAdmin ? Colors.grey : Colors.white70).withOpacity(
                      0.6,
                    ),
                    fontSize: 9,
                  ),
                ),
                if (!isAdmin) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(msg, isOptimistic),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Map<String, dynamic> msg, bool isOptimistic) {
    if (isOptimistic) {
      return const Icon(Icons.access_time, size: 12, color: Colors.white70);
    }

    final isRead = msg['is_read'] == true;

    if (isRead) {
      return const Icon(Icons.done_all, size: 13, color: Colors.blueAccent);
    } else {
      return const Icon(Icons.done, size: 13, color: Colors.white70);
    }
  }

  Widget _buildAdminTypingIndicator() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _statusStream,
      builder: (context, snapshot) {
        final status = snapshot.data;
        bool isTyping = status?['is_admin_typing'] ?? false;

        // Robustness: Only show typing if updated in the last 15 seconds (Heartbeat timeout)
        if (isTyping && status?['last_seen_at'] != null) {
          try {
            final lastSeen = DateTime.parse(status!['last_seen_at']).toUtc();
            final diff = DateTime.now().toUtc().difference(lastSeen);
            if (diff.inSeconds > 15) {
              isTyping = false;
            }
          } catch (e) {
            debugPrint("Error parsing last_seen_at: $e");
          }
        }

        if (!isTyping) return const SizedBox();

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Text(
                "الدعم يكتب الآن...",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
        top: 10,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: _isChatEnded ? 0.5 : 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  enabled: !_isChatEnded,
                  textAlign: TextAlign.right,
                  maxLines: 5,
                  minLines: 1,
                  onChanged: _onTypingChanged,
                  onSubmitted: (_) => _isChatEnded ? null : _sendMessage(),
                  textInputAction: TextInputAction.send,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText:
                        _isChatEnded ? "المحادثة منتهية" : "اكتب رسالتك هنا...",
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: _isChatEnded ? 0.5 : 1.0,
            child: Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: _isChatEnded ? null : _sendMessage,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
