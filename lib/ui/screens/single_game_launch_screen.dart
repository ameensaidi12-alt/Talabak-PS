import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../widgets/game/fast_delivery_game.dart';
import '../widgets/game/into_space_game.dart';
import '../widgets/game/hangar_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/utils/image_utils.dart';

class SingleGameLaunchScreen extends StatefulWidget {
  final Map<String, dynamic> gameData;
  const SingleGameLaunchScreen({super.key, required this.gameData});

  @override
  State<SingleGameLaunchScreen> createState() => _SingleGameLaunchScreenState();
}

class _SingleGameLaunchScreenState extends State<SingleGameLaunchScreen> {
  final _supabaseService = SupabaseService();
  bool _isLoading = true;
  late Map<String, dynamic> _settings;
  late Map<String, dynamic> _rewardSettings;
  late Map<String, dynamic> _eligibilitySettings;
  int _remainingAttempts = 0;
  bool _isPlaying = false;
  String? _statusMessage;
  List<dynamic> _topPlayers = [];
  Map<String, dynamic>? _userRank;
  bool _isWithinTimeWindow = false;
  bool _isEligible = true;
  double _minAmount = 0;
  double _totalSpent = 0;
  double _requiredMore = 0;
  int _windowDays = 7;
  Duration _timeOffset = Duration.zero;
  bool _isLiveActive = true;


  // Hangar/Progress State
  bool _showHangar = false;
  Map<String, dynamic>? _gameProgress;
  double _selectedFuelPercent = 1.0;

  String get _gameSlug => widget.gameData['slug'];
  bool get _isAdvancedMode => _settings['is_advanced_mode'] ?? false;

  @override
  void initState() {
    super.initState();
    _settings = widget.gameData['settings'] ?? {};
    _rewardSettings = widget.gameData['reward_settings'] ?? {};
    _eligibilitySettings = widget.gameData['eligibility_settings'] ?? {};
    _loadGameData();
  }

  Future<void> _loadGameData() async {
    setState(() => _isLoading = true);
    try {
      await _checkEligibility();
      await _checkAttempts();

      // Refresh settings to reflect any changes from Admin (like Advanced Mode)
      final latestData = await _supabaseService.getGameSettings(_gameSlug);
      if (latestData != null) {
        _settings = latestData['settings'] ?? {};
        _rewardSettings = latestData['reward_settings'] ?? {};
        _eligibilitySettings = latestData['eligibility_settings'] ?? {};
      }

      // Use Server Time to prevent local clock tampering
      final serverTime = await _supabaseService.getServerTime();
      _timeOffset = serverTime.difference(DateTime.now());

      if (_gameSlug == 'into-space') {
        final progress = await _supabaseService.getGameProgress(_gameSlug);
        
        // Anti-downgrade Defense: If the server returns a lower tier than what we already bought locally,
        // it means the server failed to save recently. We protect the local user progress.
        if (_gameProgress != null) {
          int localTier = _gameProgress!['current_rocket_tier'] ?? 1;
          int serverTier = progress['current_rocket_tier'] ?? 1;
          if (serverTier < localTier) {
            debugPrint("🛡️ Anti-downgrade triggered: Keeping local tier $localTier over server $serverTier");
            progress['current_rocket_tier'] = localTier;
            progress['upgrades'] = _gameProgress!['upgrades'];
            // Re-sync back to server in background
            _supabaseService.updateGameProgress(_gameSlug, {
              'current_rocket_tier': localTier,
              'upgrades': _gameProgress!['upgrades'],
            });
          }
        }
        
        _gameProgress = progress;
      }
      if (_rewardSettings['show_leaderboard'] ?? true) {
        await _fetchLeaderboard();
      }
      if (mounted) {
        await _checkLiveStatus(); // Check if active live
        if (_gameSlug == 'into-space') {
           _preloadRocketAssets();
        }
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = "حدث خطأ في تحميل بيانات اللعبة";
        });
      }
    }
  }

  Future<void> _preloadRocketAssets() async {
    try {
      // 1. Preload general game patterns
      precacheImage(
        const CachedNetworkImageProvider("https://www.transparenttextures.com/patterns/carbon-fibre.png"),
        context,
      );

      // 2. Preload specific rocket assets
      if (_settings['rocket_custom_definitions'] == null) return;
      final definitions = _settings['rocket_custom_definitions'] as List;
      
      for (var def in definitions) {
        final List<String?> urls = [
          def['full']?['image_url'],
          def['capsule']?['image_url'],
          def['booster']?['image_url'],
        ];
        for (var rawUrl in urls) {
          final url = ImageUtils.proxyUrl(rawUrl);
          if (url != null && url.isNotEmpty) {
            // This triggers both Disk and Memory caching via CachedNetworkImageProvider
            precacheImage(CachedNetworkImageProvider(url), context);
          }
        }
      }
      debugPrint("🚀 [Preload] Rocket assets (textures & models) preloaded and cached.");
    } catch (e) {
      debugPrint("❌ [Preload] Error preloading assets: $e");
    }
  }

  Future<void> _checkEligibility() async {
    try {
      // Check Competition Eligibility using the updated method
      final eligibility = await _supabaseService.checkCompetitionEligibility(_gameSlug);

      if (mounted) {
        setState(() {
          _isEligible = eligibility['isEligible'] ?? true;
          if (!_isEligible) {
            _minAmount = (eligibility['minAmount'] ?? 0).toDouble();
            _totalSpent = (eligibility['totalSpent'] ?? 0).toDouble();
            _requiredMore = (eligibility['requiredMore'] ?? 0).toDouble();
            _windowDays = eligibility['windowDays'] ?? 7;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading game settings: $e');
      if (mounted) {
        setState(() {
          _statusMessage = "حدث خطأ في تحميل إعدادات اللعبة";
        });
      }
    }
  }

  Future<void> _checkLiveStatus() async {
    try {
      final active = await _supabaseService.isGameActive(_gameSlug);
      if (mounted) {
        setState(() {
          _isLiveActive = active;
          _validateGameStatus();
        });
      }
    } catch (e) {
      debugPrint('Error heartbeating game status: $e');
    }
  }

  Future<void> _checkAttempts() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _statusMessage = "الرجاء تسجيل الدخول للمتابعة");
        return;
      }

      final attempts = await _supabaseService.getRemainingAttempts(_gameSlug);

      if (mounted) {
        setState(() {
          _remainingAttempts = attempts;
        });
      }
    } catch (e) {
      debugPrint('Error checking attempts: $e');
      if (mounted) {
        setState(() {
          _statusMessage = "حدث خطأ في التحقق من المحاولات";
        });
      }
    }
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final data = await _supabaseService.getGameLeaderboard(_gameSlug);
      if (mounted) {
        setState(() {
          _topPlayers = data['top_players'] ?? [];
          _userRank = data['user_rank'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching leaderboard: $e');
    }
  }

  void _validateGameStatus() {
    if (!_isLiveActive) {
      _statusMessage = "اللعبة غير متاحة حالياً. يرجى مراجعة الإدارة.";
      return;
    }

    // Check time window - Use Server-Adjusted Time
    final now = DateTime.now().add(_timeOffset);
    final startTimeStr = _eligibilitySettings['start_time'] ?? "00:00:00";
    final endTimeStr = _eligibilitySettings['end_time'] ?? "23:59:59";
    
    final startParts = startTimeStr.split(':');
    final endParts = endTimeStr.split(':');
    
    final start = DateTime(now.year, now.month, now.day, int.parse(startParts[0]), int.parse(startParts[1]));
    var end = DateTime(now.year, now.month, now.day, int.parse(endParts[0]), int.parse(endParts[1]));

    bool isWithinWindow;
    if (end.isBefore(start)) {
      isWithinWindow = now.isAfter(start) || now.isBefore(end);
    } else {
      isWithinWindow = now.isAfter(start) && now.isBefore(end);
    }

    _isWithinTimeWindow = isWithinWindow;
    if (!isWithinWindow) {
      final startFmt = DateFormat('HH:mm').format(start);
      final endFmt = DateFormat('HH:mm').format(end);
      _statusMessage = "التحدي يبدأ من $startFmt إلى $endFmt";
      return;
    }

    if (_remainingAttempts <= 0) {
      _statusMessage = "لقد استنفدت جميع محاولاتك لهذا اليوم. نراك غداً!";
      return;
    }

    if (!_isEligible) {
      final spentStr = _totalSpent.toStringAsFixed(0);
      final neededStr = _requiredMore.toStringAsFixed(0);
      final minStr = _minAmount.toStringAsFixed(0);

      if (_totalSpent > 0) {
        _statusMessage = "لديك طلبات بقيمة $spentStr₪. تحتاج لطلب بقيمة $neededStr₪ إضافية لتتمكن من اللعب.";
      } else {
        _statusMessage = "للعب، يجب أن يكون لديك طلب بقيمة $minStr₪ على الأقل خلال آخر $_windowDays أيام.";
      }
      return;
    }

    _statusMessage = null;
  }

  String? _currentAttemptId;

  Future<void> _startGame({double fuelPercent = 1.0}) async {
    // Live re-check before starting
    final active = await _supabaseService.isGameActive(_gameSlug);
    if (!active) {
      if (mounted) {
        setState(() {
          _isLiveActive = false;
          _validateGameStatus();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("عذراً، تم إغلاق اللعبة من قبل الإدارة.")),
        );
      }
      return;
    }

    await _checkEligibility();
    
    if (_statusMessage == null && _remainingAttempts > 0) {
      if (_gameSlug == 'into-space' && !_showHangar) {
        // Show Hangar first instead of immediately launching
        setState(() {
          _showHangar = true;
        });
        return;
      }

      final attemptId = await _supabaseService.startGameAttempt(_gameSlug);
      
      if (mounted) {
        setState(() {
          _currentAttemptId = attemptId;
          _isPlaying = true;
          _showHangar = false;
          _selectedFuelPercent = fuelPercent;
        });
        _checkAttempts();
      }
    }
  }

  Future<void> _handleGameEnd(int starsEarned, {int coinsEarned = 0, int giftsCount = 0, int coinsCount = 0, int maxAltitude = 0, List<int> newMilestones = const []}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
    
    try {
      // Use maxAltitude as score for into-space leaderboard, otherwise use starsEarned
      final finalScore = _gameSlug == 'into-space' ? maxAltitude.round() : starsEarned;
      final result = await _supabaseService.processGameResult(_gameSlug, finalScore, attemptId: _currentAttemptId, isAdvancedMode: _isAdvancedMode);
      
      // ✅ Refresh best altitude/rank/progress immediately so Hangar sees updated state
      await _loadGameData();
      
      // coinsEarned already includes BOTH stars-coins and bag-coins from IntoSpaceGame
      if (_gameSlug == 'into-space' && coinsEarned > 0) {
        // Always save total coins to Supabase
        await _supabaseService.addGameMoney(_gameSlug, coinsEarned);
        if (mounted) {
          setState(() {
            _gameProgress!['money_collected'] = (_gameProgress!['money_collected'] ?? 0) + coinsEarned;
          });
        }
      }

      if (starsEarned > 0 && _gameSlug != 'fast-delivery') {
        String rewardMessage = '🎯 أداء مذهل! ربحت $starsEarned نجوم ذهبية!';
        if (_gameSlug == 'into-space') {
          rewardMessage = '🚀 إقلاع أسطوري! ربحت $starsEarned نجوم ذهبية في الفضاء!';
        }
        await _supabaseService.addBonusStars(starsEarned, description: rewardMessage);
      }

      if (newMilestones.isNotEmpty) {
         await _supabaseService.updateWonMilestones(_gameSlug, newMilestones);
         
         if (mounted) {
           setState(() {
             _gameProgress!['won_milestones'] = [
             ...(_gameProgress!['won_milestones'] as List?)
               ?.map((e) => int.tryParse(e.toString()) ?? 0)
               .where((e) => e > 0)
               .toList() ?? [],
                ...newMilestones
              ].toSet().toList();
           });
         }
      }

      if (mounted) Navigator.pop(context); // Remove loading
      
      if (mounted) {
        if (result['success'] == true) {
          int finalStars = 0;
          bool altOk = true;
          int minAlt = 0;

          if (_gameSlug == 'into-space') {
            minAlt = int.tryParse(_settings['min_altitude_for_reward']?.toString() ?? '0') ?? 0;
            altOk = minAlt == 0 || maxAltitude >= minAlt;
            finalStars = altOk ? starsEarned : 0;
          } else if (_gameSlug == 'fast-delivery') {
            // Match database logic: 10:1 ratio, min 50 points
            if (starsEarned >= 50) {
              finalStars = (starsEarned / 10).floor();
            } else {
              finalStars = 0;
            }
          }

          _showResultSheet(starsEarned, finalStars,
              coinsEarned: coinsEarned, giftsCollected: giftsCount, coinsCollected: coinsCount,
              maxAltitude: maxAltitude, minAltitudeRequired: minAlt, altitudeConditionMet: altOk);
        } else {
          if (result['message'] == 'Daily attempts limit reached') {
            _showLimitReachedDialog();
          } else {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("تنبيه: ${result['message']}")),
            );
            if (mounted) setState(() => _isPlaying = false);
            _checkEligibility();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Remove loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("حدث خطأ في حفظ النتيجة. يرجى التأكد من الاتصال بالإنترنت.")),
        );
        setState(() {
           _isPlaying = false;
           _currentAttemptId = null;
        });
        _checkEligibility();
      }
    }
  }

  void _showLimitReachedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("انتهت المحاولات", textAlign: TextAlign.center, style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Text(
          "لقد استنفدت جميع محاولاتك لهذا اليوم. سيتم حفظ مجموع نقاطك ولكن لن تحصل على نجوم إضافية.",
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _isPlaying = false);
                _checkEligibility();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD00030),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text("حسناً", style: GoogleFonts.cairo(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showResultSheet(int score, int stars, {int coinsEarned = 0, int giftsCollected = 0, int coinsCollected = 0, int maxAltitude = 0, int minAltitudeRequired = 0, bool altitudeConditionMet = true}) {
    final hasAttempts = _remainingAttempts > 0;
    final isCompetition = _rewardSettings['is_competition_mode'] ?? false;
    
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(30),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(5)),
            ),
            const SizedBox(height: 20),
            Text(
              isCompetition 
                ? "انتهت الجولة! 🏆" 
                : (stars > 0 ? "أحسنت! 🏁" : "حاول مرة أخرى! 🚀"),
              style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_gameSlug == 'into-space') ...[
                  _resultStat("هدايا 🎁", "$giftsCollected", Colors.purple),
                  _resultStat("أكياس 💰", "$coinsCollected", Colors.orange),
                  if (!isCompetition) _resultStat("نجوم ⭐", "$stars", Colors.amber),
                  if (isCompetition) _resultStat("نقاط التحدي", "$stars", Colors.amber),
                  _resultStat("الارتفاع", "${maxAltitude}m", (!altitudeConditionMet && minAltitudeRequired > 0) ? Colors.red : Colors.teal),
                ],
                if (_gameSlug == 'fast-delivery') ...[
                   _resultStat(isCompetition ? "نقاط التحدي" : "النقاط", "$score", Colors.blue),
                   if (!isCompetition)
                      _resultStat("النجوم", " $stars ⭐", Colors.amber),
                ],
              ],
            ),
            if (!altitudeConditionMet && minAltitudeRequired > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red[200]!)),
                child: Text(
                  "⚠️ يجب الوصول لارتفاع ${minAltitudeRequired}m للفوز بالنجوم! (وصلت ${maxAltitude}m)",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
            if (isCompetition) ...[
              const SizedBox(height: 15),
              Text(
                "تم تسجيل نقاطك في لوحة المتصدرين!",
                style: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            const SizedBox(height: 30),
            if (hasAttempts)
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _isPlaying = false;
                    });
                    Future.delayed(const Duration(milliseconds: 100), () async {
                      await _loadGameData(); // Refresh rank/progress before restart
                      _startGame();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD00030),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Text("العب مرة أخرى ($_remainingAttempts محاولات)", style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _loadGameData(); // Refresh everything
                  setState(() => _isPlaying = false);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD00030)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text("العودة للخلف", style: GoogleFonts.cairo(color: const Color(0xFFD00030))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 14)),
        Text(value, style: GoogleFonts.cairo(color: color, fontSize: 32, fontWeight: FontWeight.w900)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPlaying) {
      if (_gameSlug == 'fast-delivery') {
        return Scaffold(
          body: FastDeliveryGame(
            initialSpeed: (_settings['initial_speed'] ?? 1.0).toDouble(),
            accelerationRate: (_settings['acceleration_rate'] ?? 0.0001).toDouble(),
            maxSpeed: (_settings['max_speed'] ?? 30.0).toDouble(),
            minScoreForReward: _rewardSettings['min_score_for_reward'] ?? 500,
            themeScoreThreshold: _settings['theme_score_threshold'] ?? 50,
            accelerationInterval: _settings['acceleration_interval'] ?? 5,
            accelerationStep: (_settings['acceleration_step'] ?? 0.5).toDouble(),
            accelerationDelay: _settings['acceleration_delay'] ?? 10,
            isCompetitionMode: _rewardSettings['is_competition_mode'] ?? false,
            speedMultiplier: (_settings['speed_multiplier'] ?? 1.0).toDouble(),
            giftsPer5Seconds: _settings['gifts_per_5s'] ?? 1,
            onGameOver: (score) => _handleGameEnd(score),
            onGameWin: (score) => _handleGameEnd(score),
          ),
        );
      } else if (_gameSlug == 'into-space') {
        // Pass upgrades to the game
        final upgrades = _gameProgress?['upgrades'] ?? {};
        
        // Exploit Protection: clamp equipped tier to max unlocked tier
        final maxUnlockedTier = _gameProgress?['current_rocket_tier'] ?? 1;
        int equippedTier = upgrades['equipped_tier'] ?? maxUnlockedTier;
        if (equippedTier > maxUnlockedTier) equippedTier = maxUnlockedTier;

        return Scaffold(
          body: IntoSpaceGame(
            gameSettings: _settings,
            upgrades: upgrades,
            rocketTier: equippedTier,
            wonMilestones: (_gameProgress?['won_milestones'] as List?)
                ?.map((e) => int.tryParse(e.toString()) ?? 0)
                .where((e) => e > 0)
                .toList() ?? [],
            initialFuelPercent: _selectedFuelPercent,
            isAdvancedMode: _isAdvancedMode,
            onGameOver: (stars, coins, giftsN, coinsN, maxAlt, newMils) => _handleGameEnd(stars, coinsEarned: coins, giftsCount: giftsN, coinsCount: coinsN, maxAltitude: maxAlt.round(), newMilestones: newMils),
          ),
        );
      }
      return Scaffold(body: Center(child: Text("Game Not Found", style: GoogleFonts.cairo())));
    }

    if (_showHangar && _gameProgress != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text("الورشة وتجهيز الإطلاق", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _showHangar = false),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: HangarView(
            initialMoney: _gameProgress!['money_collected'] ?? 0,
            initialUpgrades: _gameProgress!['upgrades'] ?? {},
            initialRocketTier: _gameProgress!['current_rocket_tier'] ?? 1,
            gameSettings: _settings,
            bestAltitude: (_userRank?['score'] ?? 0).toInt(),
            onSave: (money, upgrades, {rocketTier}) {
              _supabaseService.updateGameProgress(_gameSlug, {
                'money_collected': money,
                'upgrades': upgrades,
                if (rocketTier != null) 'current_rocket_tier': rocketTier,
              });
              _gameProgress!['money_collected'] = money;
              _gameProgress!['upgrades'] = upgrades;
              if (rocketTier != null) _gameProgress!['current_rocket_tier'] = rocketTier;
            },
            onLaunch: (fuel) => _startGame(fuelPercent: fuel), // _startGame will bypass hangar check since _showHangar is true
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.gameData['name'] ?? "لعبة", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                children: [
                  Text(
                    widget.gameData['icon_emoji'] ?? "🎮", 
                    style: const TextStyle(fontSize: 80)
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (_rewardSettings['is_competition_mode'] ?? false) 
                      ? (_rewardSettings['competition_title'] ?? "مسابقة حت ستار")
                      : widget.gameData['name'] ?? "لعبة التوصيل السريع",
                    style: GoogleFonts.cairo(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold,
                      color: (_rewardSettings['is_competition_mode'] ?? false) ? Colors.amber[900] : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (_rewardSettings['is_competition_mode'] ?? false)
                      ? (_rewardSettings['competition_description'] ?? "شارك في المسابقة الآن وحقق أعلى سكور لتربح جوائز مميزة!")
                      : widget.gameData['description'] ?? "العب واربح النجوم",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 30),
                  
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: (_rewardSettings['is_competition_mode'] ?? false) 
                          ? Colors.amber[50] 
                          : (!_isWithinTimeWindow ? Colors.grey[50] : (_remainingAttempts > 0 ? Colors.green[50] : Colors.red[50])),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: (_rewardSettings['is_competition_mode'] ?? false)
                            ? Colors.amber[200]!
                            : (!_isWithinTimeWindow ? Colors.grey[200]! : (_remainingAttempts > 0 ? Colors.green[100]! : Colors.red[100]!))
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ((_rewardSettings['is_competition_mode'] ?? false) ? Colors.amber : (!_isWithinTimeWindow ? Colors.grey : (_remainingAttempts > 0 ? Colors.green : Colors.red))).withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded, color: _remainingAttempts > 0 ? Colors.orange : Colors.grey, size: 28),
                            const SizedBox(width: 10),
                            Text(
                              "المحاولات المتاحة: ",
                              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _isWithinTimeWindow ? "$_remainingAttempts" : "-",
                              style: GoogleFonts.cairo(
                                fontSize: 24, 
                                fontWeight: FontWeight.w900,
                                color: _remainingAttempts > 0 && _isWithinTimeWindow ? Colors.green[700] : Colors.red[700],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        _infoRow(
                          (_rewardSettings['is_competition_mode'] ?? false) ? Icons.emoji_events_rounded : Icons.stars_rounded, 
                          (_rewardSettings['is_competition_mode'] ?? false) ? "جائزة المسابقة:" : "نظام الربح:", 
                          !_isWithinTimeWindow ? "-" : ((_rewardSettings['is_competition_mode'] ?? false)
                            ? (_rewardSettings['competition_reward_text'] ?? "جوائز مادية قيمة")
                            : (_gameSlug == 'into-space' 
                                ? "أهداف الوصول والجوائز" 
                                : ((_rewardSettings['is_fixed_reward'] == true) 
                                    ? "جائزة ثابتة: ${_rewardSettings['reward_amount_fixed']} نجوم"
                                    : "ربح تراكمي: نجمة لكل ${_rewardSettings['points_to_stars_ratio']} نقطة")))
                        ),
                        if (_gameSlug == 'into-space' && _isWithinTimeWindow) ...[
                          const SizedBox(height: 20),
                          _buildMilestoneRoadmap(),
                        ],
                        if ((_rewardSettings['min_score_for_reward'] ?? 0) > 0 && _gameSlug != 'into-space') ...[
                          const SizedBox(height: 8),
                          _infoRow(
                            Icons.flag_rounded, 
                            "هدف النقاط للفوز:", 
                            !_isWithinTimeWindow ? "-" : "${_rewardSettings['min_score_for_reward']} نقطة"
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // Leaderboard Section
                  if (_isWithinTimeWindow && (_rewardSettings['show_leaderboard'] ?? true)) ...[
                    const SizedBox(height: 40),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      alignment: WrapAlignment.start,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 28),
                            const SizedBox(width: 10),
                            Text(
                              "أبطال التحدي",
                              style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (_userRank != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber[100],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _gameSlug == 'into-space' 
                                ? "أفضل ارتفاع: #${_userRank!['rank'] ?? 0} (${_userRank!['score'] ?? 0} متر)"
                                : "تصنيفك: #${_userRank!['rank'] ?? 0} (${_userRank!['score'] ?? 0} نقطة)",
                              style: GoogleFonts.cairo(
                                fontSize: 13, 
                                fontWeight: FontWeight.bold, 
                                color: Colors.amber[900]
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildLeaderboard(),
                  ],

                  const SizedBox(height: 40),
                  // The Play button was moved to the bottomNavigationBar
                ],
              ),
            ),
          ),
      bottomNavigationBar: _isLoading
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_statusMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[100]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_clock, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: GoogleFonts.cairo(
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _statusMessage == null
                            ? _startGame
                            : (!_isEligible
                                ? () => Navigator.pop(context)
                                : null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (_rewardSettings['is_competition_mode'] ?? false)
                              ? (_isEligible ? Colors.amber[700] : Colors.amber[800])
                              : (_isEligible ? const Color(0xFFD00030) : Colors.grey[400]),
                          disabledBackgroundColor: Colors.grey[200],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _statusMessage == null
                                  ? (_gameSlug == 'into-space' ? Icons.rocket_launch_rounded : Icons.two_wheeler_rounded)
                                  : (!_isEligible
                                      ? Icons.shopping_basket_rounded
                                      : Icons.lock_outline_rounded),
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _statusMessage == null
                                  ? (_gameSlug == 'into-space' ? "انطلق الآن!" : "العب الآن!")
                                  : (!_isEligible
                                      ? "اطلب الآن لتتأهل"
                                      : "غير متاح حالياً"),
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: (_statusMessage == null || !_isEligible)
                                    ? Colors.white
                                    : Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
  Widget _buildLeaderboard() {
    if (_topPlayers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            "كن أول من يتصدر القائمة!",
            style: GoogleFonts.cairo(color: Colors.grey[600]),
          ),
        ),
      );
    }

    // Check if current user is in the TOP 6 (the initially visible set)
    bool userInTop6 = false;
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      for (int i = 0; i < _topPlayers.length && i < 6; i++) {
        if (_topPlayers[i]['user_id'] == currentUser.id) {
          userInTop6 = true;
          break;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380), // Approx 6 items
            child: ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(), // Smoother internal scroll
              itemCount: _topPlayers.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[100]),
              itemBuilder: (context, index) {
                final player = _topPlayers[index];
                return _buildLeaderboardRow(player, index);
              },
            ),
          ),
          // Sticky "Your Rank" footer if not in top 6
          if (!userInTop6 && _userRank != null) ...[
            Container(color: Colors.grey[100], height: 1),
            _buildStickyUserRank(),
          ],
        ],
      ),
    );
  }

  Widget _buildStickyUserRank() {
    final String fullName = _userRank!['full_name'] ?? "أنت";
    final int rank = int.tryParse(_userRank!['rank']?.toString() ?? '0') ?? 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
      ),
      child: Row(
        children: [
          _buildRankBadge(rank),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ترتيبك الحالي", 
                  style: GoogleFonts.cairo(fontSize: 10, color: Colors.blueGrey[600], fontWeight: FontWeight.bold)
                ),
                Text(
                  fullName,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${_userRank!['score'] ?? 0}",
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFD00030),
                  fontSize: 16,
                ),
              ),
              Text(
                _gameSlug == 'into-space' ? "متر" : "نقطة",
                style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(Map<String, dynamic> player, int index) {
    final int rank = int.tryParse(player['rank']?.toString() ?? '0') ?? (index + 1);
    final isTop3 = rank <= 3;
    final currentUser = Supabase.instance.client.auth.currentUser;
    final bool isMe = currentUser != null && player['user_id'] == currentUser.id;
    
    String rankTitle = "";
    Color badgeColor = Colors.grey;
    if (rank == 1) {
      rankTitle = "ULTRA 👑";
      badgeColor = Colors.amber[900]!;
    } else if (rank == 2) {
      rankTitle = "PRO 🚀";
      badgeColor = const Color(0xFF1A237E); // Navy Blue
    } else if (rank == 3) {
      rankTitle = "ELITE ⭐";
      badgeColor = Colors.blueGrey[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue.withOpacity(0.05) : (index == 0 ? Colors.amber[50]?.withOpacity(0.3) : null),
      ),
      child: Row(
        children: [
          _buildRankBadge(rank),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player['full_name'] ?? "لاعب مجهول",
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontWeight: (isTop3 || isMe) ? FontWeight.bold : FontWeight.normal,
                      fontSize: (isTop3 || isMe) ? 15 : 14,
                      color: isMe ? Colors.blue[900] : null,
                    ),
                  ),
                ),
                if (rankTitle.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: rank == 1 ? [
                        BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 4, spreadRadius: 1)
                      ] : null,
                    ),
                    child: Text(
                      rankTitle,
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ),
                ] else if (player['is_advanced'] == true) ...[
                   const SizedBox(width: 8),
                   Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[400],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "ADVANCED",
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${player['score'] ?? 0}",
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFD00030),
                  fontSize: 16,
                ),
              ),
              Text(
                _gameSlug == 'into-space' ? "متر / ${player['attempts'] ?? 0} محاولة" : "نقطة / ${player['attempts'] ?? 0} محاولة",
                style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildRankBadge(int rank) {
    if (rank == 1) return const Text("🥇", style: TextStyle(fontSize: 24));
    if (rank == 2) return const Text("🥈", style: TextStyle(fontSize: 24));
    if (rank == 3) return const Text("🥉", style: TextStyle(fontSize: 24));
    
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          "$rank",
          style: GoogleFonts.cairo(
            fontSize: 12, 
            fontWeight: FontWeight.bold, 
            color: Colors.grey[600]
          ),
        ),
      ),
    );
  }

  Widget _buildMilestoneRoadmap() {
    final rawMilestones = _settings['rocket_win_milestones'] as List? ?? [];
    if (rawMilestones.isEmpty) return const SizedBox.shrink();

    // Sort descending: Longest altitude at top, shortest at bottom, ensuring logical rocket path
    final milestones = List<Map<String, dynamic>>.from(rawMilestones);
    milestones.sort((a, b) => ((b['altitude'] ?? 0) as num).compareTo((a['altitude'] ?? 0) as num));

    final wonMilestones = (_gameProgress?['won_milestones'] as List?)
            ?.map((e) => int.tryParse(e.toString()) ?? 0)
            .toList() ?? [];

    return Column(
      children: List.generate(milestones.length, (index) {
        final m = milestones[index];
        final alt = m['altitude'] as int;
        final prize = m['prize'] as int;
        final isWon = wonMilestones.contains(alt);
        final isLast = index == milestones.length - 1;

        return IntrinsicHeight(
          child: Row(
            children: [
              // Timeline line and circle
              Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isWon ? Colors.green : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isWon ? Colors.green : Colors.grey[300]!,
                        width: 2,
                      ),
                      boxShadow: isWon ? [
                        BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 8)
                      ] : [],
                    ),
                    child: isWon 
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Center(child: Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.grey[300], shape: BoxShape.circle))),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isWon ? Colors.green : Colors.grey[200],
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Milestone Card
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isWon ? Colors.green.withOpacity(0.3) : Colors.grey[100]!,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "الارتفاع: $alt متر",
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isWon ? Colors.green[800] : Colors.grey[800],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              m['message'] ?? "عبر الغلاف الجوي",
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                color: Colors.grey[500],
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isWon ? Colors.green[50] : Colors.amber[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              "$prize",
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: isWon ? Colors.green[700] : Colors.amber[900],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "⭐",
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFD00030), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: GoogleFonts.cairo(fontSize: 14))),
        Text(value, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
