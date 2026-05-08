import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/utils/image_utils.dart';

class HangarView extends StatefulWidget {
  final int initialMoney;
  final Map<String, dynamic> initialUpgrades;
  final int initialRocketTier;
  final Map<String, dynamic> gameSettings;
  final int bestAltitude;
  final Function(int newMoney, Map<String, dynamic> newUpgrades, {int? rocketTier}) onSave;
  final Function(double fuelPercent) onLaunch;

  const HangarView({
    super.key,
    required this.initialMoney,
    required this.initialUpgrades,
    required this.initialRocketTier,
    required this.gameSettings,
    required this.bestAltitude,
    required this.onSave,
    required this.onLaunch,
  });


  @override
  State<HangarView> createState() => _HangarViewState();
}

class _HangarViewState extends State<HangarView> {
  late int _money;
  late Map<String, dynamic> _upgrades;
  late int _maxUnlockedTier;
  late int _equippedTier;
  late int _viewingTier;
  double _fuelPercent = 1.0;

  bool get _isAdvancedMode => widget.gameSettings['is_advanced_mode'] ?? false;
  bool get _requireMaxUpgradesToUnlock => widget.gameSettings['require_max_upgrades_to_unlock'] == true;

  Map<int, Map<String, dynamic>> _rocketTiers = {};

  void _loadRocketTiers() {
    final definitions = widget.gameSettings['rocket_custom_definitions'] as List?;
    if (_isAdvancedMode && definitions != null && definitions.isNotEmpty) {
      _rocketTiers = {};
      for (var d in definitions) {
        if (d == null) continue;
        final i = definitions.indexOf(d);
        
        // Try to get image from new nested structure, then legacy field, then icon
        String? bestImage = d['full'] is Map ? (d['full'] as Map)['image_url']?.toString() : null;
        if (bestImage == null || bestImage.isEmpty) {
          bestImage = d['image_url']?.toString();
        }
        if (bestImage == null || bestImage.isEmpty) {
           bestImage = d['icon']?.toString();
        }

        final String? imageUrl = ImageUtils.proxyUrl(bestImage);
        
        // Extract visual props for fallback
        final String colorStr = d['full'] is Map ? ((d['full'] as Map)['color']?.toString() ?? '0xFFE53935') : '0xFFE53935';
        final Color color = Color(int.tryParse(colorStr.replaceFirst('#', '')) ?? 0xFFE53935);
        final String shape = d['full'] is Map ? ((d['full'] as Map)['shape']?.toString() ?? 'rocket') : 'rocket';

        _rocketTiers[i + 1] = {
          'name': (d['name'] ?? "صاروخ ${i + 1}").toString(),
          'icon': '🚀',
          'image_url': imageUrl,
          'color': color,
          'shape': shape,
          'max_upgrades': (d['max_level'] ?? 10).toInt(),
          'next_tier_cost': (d['price'] ?? 5000).toInt(),
          'base_fuel': (d['base_fuel'] ?? 100.0).toDouble(),
          'fuel_per_upgrade': (d['fuel_per_upgrade'] ?? 25.0).toDouble(),
          'base_thrust': (d['base_thrust'] ?? 1.2).toDouble(),
          'thrust_per_upgrade': (d['thrust_per_upgrade'] ?? 0.1).toDouble(),
          'fuel_upgrade_cost': (d['fuel_upgrade_cost'] ?? 500).toInt(),
          'thrust_upgrade_cost': (d['thrust_upgrade_cost'] ?? 800).toInt(),
          'hull_upgrade_cost': (d['hull_upgrade_cost'] ?? 1000).toInt(),
          'max_altitude': (d['max_altitude'] ?? 10000.0).toDouble(),
          'unlock_altitude': (d['unlock_altitude'] ?? (d['max_altitude'] ?? 10000.0) * 0.85).toDouble(),
          'description': d['description'] ?? 'صاروخ من الطراز الرفيع تم تصميمه بمهارة.',
        };


      }
      
      // Safety Clamp: REMOVED. We no longer automatically downgrade users if definitions are missing.
      // Keeping the tier integrity regardless of temporary server-side changes.
      /*
      if (definitions.isNotEmpty && _maxUnlockedTier > definitions.length) {
        _maxUnlockedTier = definitions.length;
      }
      */
    } else {
      // Legacy / Default Fallback
      _rocketTiers = {
        1: {
          'name': 'صاروخ Sparrow',
          'icon': '🚀',
          'max_upgrades': 5,
          'next_tier_cost': 500,
          'max_altitude': 3000.0,
          'description': 'صاروخ تعليمي بسيط مخصص للارتفاعات القريبة.',
        },
        2: {
          'name': 'صاروخ Advanced Falcon',
          'icon': '🛰️',
          'max_upgrades': 10,
          'next_tier_cost': 2000,
          'max_altitude': 15000.0,
          'description': 'صاروخ احترافي فائق السرعة يمكنه بلوغ طبقات الجو العليا.',
        },
        3: {
          'name': 'مركبة Starship X',
          'icon': '🛸',
          'max_upgrades': 15,
          'next_tier_cost': 0, // Max tier
          'max_altitude': 100000.0,
          'description': 'مركبة فضائية جبارة مخصصة للفضاء العميق وما بعده.',
        },
      };
    }
  }

  final Map<String, Map<String, dynamic>> _upgradeDefs = {
    'engine_lv': {
      'name': 'المحرك',
      'icon': '🔥',
      'base_cost': 50,
      'max_level': 10,
    },
    'fuel_lv': {
      'name': 'خزان الوقود',
      'icon': '⛽',
      'base_cost': 40,
      'max_level': 10,
    },
    'hull_lv': {
      'name': 'الهيكل',
      'icon': '🛡️',
      'base_cost': 60,
      'max_level': 10,
    },
  };

  /// ✅ الحماية المطلقة للمستوى: تضمن عدم إرسال أي مستوى أقل من المستوى الحالي في قاعدة البيانات
  void _safeOnSave() {
    int tierToSave = _maxUnlockedTier;
    // إذا كان المستوى المحلي لسبب ما أقل من المستوى الذي بدأنا فيه، نعتمد مستوى البداية كحد أدنى
    if (tierToSave < widget.initialRocketTier) {
      tierToSave = widget.initialRocketTier;
    }
    
    widget.onSave(_money, _upgrades, rocketTier: tierToSave);
  }

  @override
  void initState() {
    super.initState();
    // Deep copy to prevent mutating parent state directly before save
    _upgrades = Map<String, dynamic>.from(widget.initialUpgrades);
    
    _maxUnlockedTier = widget.initialRocketTier;
    
    // Validate and clamp equipped tier to prevent exploits
    int eq = _upgrades['equipped_tier'] ?? _maxUnlockedTier;
    if (eq > _maxUnlockedTier) eq = _maxUnlockedTier;
    _equippedTier = eq;
    _upgrades['equipped_tier'] = _equippedTier;
    
    _viewingTier = _equippedTier;
    
    _loadRocketTiers();
    _money = widget.initialMoney;
    
    // Safety Clamps: REMOVED. We trust the database (initialRocketTier) as the absolute source of truth.
    // if (_maxUnlockedTier > _rocketTiers.length && _rocketTiers.isNotEmpty) _maxUnlockedTier = _rocketTiers.length;
    // if (_viewingTier > _rocketTiers.length && _rocketTiers.isNotEmpty) _viewingTier = _rocketTiers.length;

    // ✅ تشغيل فحص فتح الصواريخ الجديدة بعد بناء الواجهة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNewUnlocks();
    });
  }

  bool _isPrevTierMaxed(int tier) {
     if (!_requireMaxUpgradesToUnlock) return true;
     final prevTier = tier - 1;
     if (prevTier <= 0) return true;
     
     int tierMax = (_rocketTiers[prevTier]?['max_upgrades'] ?? 10) as int;
     
     if ((_upgrades['engine_lv'] ?? 1) < tierMax) return false;
     if ((_upgrades['fuel_lv'] ?? 1) < tierMax) return false;
     if ((_upgrades['hull_lv'] ?? 1) < tierMax) return false;
     return true;
  }

  void _checkNewUnlocks() {
    // نبحث عن أول صاروخ مقفل (لم يتم شراؤه بعد) ولكن تم تحقيق شرط الارتفاع الخاص به
    for (int t = _maxUnlockedTier + 1; t <= _rocketTiers.length; t++) {
      final prevTier = t - 1;
      final requiredAlt = (_rocketTiers[prevTier]?['unlock_altitude'] ?? ((_rocketTiers[prevTier]?['max_altitude'] ?? 10000.0) * 0.85)).round();
      
      if (widget.bestAltitude >= requiredAlt && _isPrevTierMaxed(t)) {
        // وجدنا صاروخاً جديداً متاحاً للشراء، تأكد أنه لم يتم إشعاره من قبل
        if (_upgrades['notified_unlock_$t'] != true) {
            _upgrades['notified_unlock_$t'] = true;
            _safeOnSave(); // Use safe save helper
            _showUnlockCelebration(t);
        }
        break; // نظهر رسالة واحدة فقط للصاروخ الأعلى المتاح
      }
    }
  }

  void _showUnlockCelebration(int tier) {
    final rocketName = _rocketTiers[tier]?['name'] ?? "صاروخ جديد";
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.amber.withOpacity(0.5), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 30, spreadRadius: 5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("✨ 🎉 ✨", style: TextStyle(fontSize: 30)),
              const SizedBox(height: 15),
              Text(
                "إنجاز جديد!",
                style: GoogleFonts.cairo(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                "لقد نجحت في فتح موديل جديد لرحلتك القادمة",
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 25),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.rocket_launch_rounded, color: Colors.amber, size: 60),
              ),
              const SizedBox(height: 15),
              Text(
                rocketName,
                style: GoogleFonts.cairo(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _viewingTier = tier; // انتقل للصاروخ الجديد في العرض
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[700],
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(
                  "رؤية الصاروخ",
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getUpgradeCost(String key, int currentLevel) {
    int baseCost = 500;
    
    if (_isAdvancedMode) {
      if (key == 'fuel_lv') baseCost = (_rocketTiers[_viewingTier]?['fuel_upgrade_cost'] ?? 500) as int;
      else if (key == 'engine_lv') baseCost = (_rocketTiers[_viewingTier]?['thrust_upgrade_cost'] ?? 800) as int;
      else if (key == 'hull_lv') baseCost = (_rocketTiers[_viewingTier]?['hull_upgrade_cost'] ?? 1000) as int;
    } else {
      if (key == 'fuel_lv') baseCost = (widget.gameSettings['fuel_upgrade_cost'] ?? 500).toInt();
      else if (key == 'engine_lv') baseCost = (widget.gameSettings['thrust_upgrade_cost'] ?? 800).toInt();
      else if (key == 'hull_lv') baseCost = (widget.gameSettings['hull_upgrade_cost'] ?? 1000).toInt();
    }

    // تطبيق القاعدة التصاعدية: (السعر الأساسي) + (50% من السعر الأساسي لكل مستوى إضافي)
    // مثال بسعر 500: المستويات 1(500) -> 2(750) -> 3(1000) -> 4(1250)
    double multiplier = 1.0 + (currentLevel - 1) * 0.5;
    return (baseCost * multiplier).toInt();
  }

  void _buyUpgrade(String key) {
    int currentLevel = _upgrades[key] ?? 1;
    
    // In advanced mode, max level depends on tier
    int globalMax = (_upgradeDefs[key]?['max_level'] ?? 10) as int;
    int tierMax = _isAdvancedMode ? ((_rocketTiers[_viewingTier]?['max_upgrades'] ?? 10) as int) : globalMax;
    int maxLevel = _isAdvancedMode ? tierMax : globalMax;

    
    if (currentLevel >= maxLevel) return;

    int cost = _getUpgradeCost(key, currentLevel);
    if (_money >= cost) {
      setState(() {
        _money -= cost;
        _upgrades[key] = currentLevel + 1;
      });
      _safeOnSave();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("لا يوجد رصيد كافٍ", style: GoogleFonts.cairo())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use base_fuel from the custom rocket tier definition if in advanced mode
    double baseFuel;
    double fuelPerLevel;
    int maxLevelForTier;
    
    if (_isAdvancedMode && _rocketTiers.containsKey(_viewingTier)) {
      var currentDef = _rocketTiers[_viewingTier]!;
      baseFuel = (currentDef['base_fuel'] ?? 100.0).toDouble();
      fuelPerLevel = (currentDef['fuel_per_upgrade'] ?? 25.0).toDouble();
      maxLevelForTier = (currentDef['max_upgrades'] ?? 10).toInt();
    } else {
      baseFuel = (widget.gameSettings['base_fuel'] ?? 100.0).toDouble();
      fuelPerLevel = (widget.gameSettings['fuel_per_upgrade'] ?? 25.0).toDouble();
      maxLevelForTier = (_viewingTier == 1 ? 5 : (_viewingTier == 2 ? 10 : 15));
    }
    
    int fuelLv = _upgrades['fuel_lv'] ?? 1;
    if (fuelLv > maxLevelForTier) fuelLv = maxLevelForTier;
    
    double globalBaseFuel = (widget.gameSettings['base_fuel'] ?? 300.0).toDouble();
    double currentMaxFuel = globalBaseFuel + baseFuel + ((fuelLv - 1) * fuelPerLevel);
    int currentLiters = (currentMaxFuel * _fuelPercent).toInt();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12), // Deeper dark background
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- PREMIUM HEADER & CURRENT ROCKET PREVIEW ---
                  _buildWorkshopHeader(),

                  const SizedBox(height: 20),

                  // --- ROCKET SHOWROOM (THE SHOP) ---
                  _buildShowroom(),

                  const SizedBox(height: 10),

                  // --- ACTION SECTION (EQUIP / BUY / LOCKED) ---
                  _buildActionSection(),

                  const SizedBox(height: 20),

                  // --- UPGRADES SECTION ---
                  if (_viewingTier <= _maxUnlockedTier)
                    _buildUpgradesSection(),

                  // --- FUEL & LAUNCH ---
                  _buildLaunchControls(currentLiters),
                  
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildWorkshopHeader() {
    final rocket = _rocketTiers[_viewingTier];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF16213E).withOpacity(0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ورشة الصواريخ",
                    style: GoogleFonts.cairo(
                      color: Colors.blueAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    _isAdvancedMode ? (rocket?['name']?.toString() ?? 'صاروخ غير معروف') : "Hangar",
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              _buildMoneyBadge(),
            ],
          ),
          const SizedBox(height: 30),
          // Large Central Rocket Preview
          Hero(
            tag: 'rocket_preview_$_viewingTier',
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.1),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: _buildRocketImage(
                  rocket?['image_url']?.toString(), 
                  size: 160,
                  fallbackColor: rocket?['color'] as Color?,
                ),
              ),
            ),
          ),
          if (rocket?['description'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                rocket!['description'].toString(),
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMoneyBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("💰", style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            "$_money",
            style: GoogleFonts.cairo(
              color: Colors.amber,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowroom() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            "معرض الموديلات المتاحة",
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            itemCount: _rocketTiers.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              int t = index + 1;
              bool isLocked = t > _maxUnlockedTier;
              
              // If it's the next tier in line, check if we met the altitude requirement and max upgrades if enabled
              if (isLocked && t == _maxUnlockedTier + 1) {
                  final prevTier = t - 1;
                  final requiredAlt = (_rocketTiers[prevTier]?['unlock_altitude'] ?? ((_rocketTiers[prevTier]?['max_altitude'] ?? 10000.0) * 0.85)).round();
                  if (widget.bestAltitude >= requiredAlt && _isPrevTierMaxed(t)) {
                      isLocked = false; // Remove the padlock visually so user can tap it to buy
                  }
              }

              bool isSelected = t == _viewingTier;
              bool isEquipped = t == _equippedTier;

              return GestureDetector(
                onTap: () => _onRocketTap(t, isLocked),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 90,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blueAccent.withOpacity(0.15) : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.blueAccent : (isLocked ? Colors.white10 : Colors.white24),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 10)
                    ] : null,
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Opacity(
                              opacity: isLocked ? 0.4 : 1.0,
                              child: _buildRocketImage(
                                _rocketTiers[t]?['image_url']?.toString(), 
                                size: 50, 
                                isLocked: isLocked,
                                fallbackColor: _rocketTiers[t]?['color'] as Color?,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isLocked ? "مغلق" : (_rocketTiers[t]?['name'] ?? "Tier $t").toString(),
                              style: GoogleFonts.cairo(
                                color: isLocked ? Colors.white38 : (isSelected ? Colors.white : Colors.white70),
                                fontSize: 9,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (isEquipped)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(Icons.check_circle, size: 16, color: Colors.greenAccent[400]),
                        ),
                      if (isLocked)
                        const Positioned(
                          top: 8,
                          left: 8,
                          child: Icon(Icons.lock_rounded, size: 14, color: Colors.white38),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onRocketTap(int t, bool isLocked) {
    if (isLocked) {
      final prevTier = t - 1;
      final requiredAlt = (_rocketTiers[prevTier]?['unlock_altitude'] ?? ((_rocketTiers[prevTier]?['max_altitude'] ?? 10000.0) * 0.85)).round();
      final bool needAlt = widget.bestAltitude < requiredAlt;
      final bool needUpgrades = !_isPrevTierMaxed(t);
      
      String reqText = "لتتمكن من قيادة ${_rocketTiers[t]?['name']}:\n";
      if (needAlt) reqText += "- يجب عليك الوصول لارتفاع ${requiredAlt.toInt()} متر بالصاروخ الحالي.\n";
      if (needUpgrades) reqText += "- يجب ترقية الصاروخ الحالي (محرك، هيكل، وقود) للحد الأقصى (MAX).";

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF16213E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.blueAccent)),
          title: Text("🔒 مهمة قيد الانتظار", style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reqText,
                style: GoogleFonts.cairo(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (needAlt)
                LinearProgressIndicator(
                  value: (widget.bestAltitude / requiredAlt).clamp(0.0, 1.0),
                  backgroundColor: Colors.white10,
                  color: Colors.blueAccent,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("سأفعل ذلك!", style: GoogleFonts.cairo(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      setState(() => _viewingTier = t);
    }
  }

  Widget _buildActionSection() {
    bool isLocked = _viewingTier > _maxUnlockedTier;
    bool isNextToUnlock = _viewingTier == _maxUnlockedTier + 1;
    bool isEquipped = _viewingTier == _equippedTier;

    if (isEquipped) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text("هذا الصاروخ جاهز حالياً للإطلاق", style: GoogleFonts.cairo(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    if (!isLocked) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ElevatedButton(
          onPressed: () {
            setState(() {
              _equippedTier = _viewingTier;
              _upgrades['equipped_tier'] = _equippedTier;
            });
            _safeOnSave();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
            shadowColor: Colors.blueAccent.withOpacity(0.4),
          ),
          child: Text("تجهيز هذا الموديل", style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
        ),
      );
    }

    if (isNextToUnlock) {
      final prevTier = _viewingTier - 1;
      final requiredAlt = (_rocketTiers[prevTier]?['unlock_altitude'] ?? ((_rocketTiers[prevTier]?['max_altitude'] ?? 10000.0) * 0.85)).round();
      final bool isAltLocked = widget.bestAltitude < requiredAlt;
      final bool isUpgradeLocked = !_isPrevTierMaxed(_viewingTier);
      final bool isFullyLocked = isAltLocked || isUpgradeLocked;
      final int cost = (_rocketTiers[_viewingTier]?['next_tier_cost'] ?? 5000) as int;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isFullyLocked ? [Colors.red.withOpacity(0.1), Colors.black26] : [Colors.blueAccent.withOpacity(0.2), Colors.indigo.withOpacity(0.2)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isFullyLocked ? Colors.red.withOpacity(0.3) : Colors.blueAccent.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("إتاحة الموديل", style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12)),
                      Text(
                        isFullyLocked ? (isUpgradeLocked ? "تطوير الصاروخ للمحجر أولاً" : "مهمة الارتفاع مطلوبة") : "جاهز للشراء",
                        style: GoogleFonts.cairo(color: isFullyLocked ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: (isFullyLocked || _money < cost) ? null : () {
                      setState(() {
                        _money -= cost;
                        _maxUnlockedTier = _viewingTier;
                        _equippedTier = _maxUnlockedTier;
                        _upgrades['equipped_tier'] = _equippedTier;
                      });
                      _safeOnSave();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFullyLocked ? Colors.grey[800] : Colors.amber[700],
                      foregroundColor: isFullyLocked ? Colors.white70 : Colors.black87,
                      disabledBackgroundColor: Colors.grey[800]?.withOpacity(0.9), // Fix default disabled grey
                      disabledForegroundColor: Colors.white, // bright text on disabled button
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("💰 $cost", style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildUpgradesSection() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("تطوير أداء المحرك والهيكل", style: GoogleFonts.cairo(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ..._upgradeDefs.entries.map((entry) {
            String key = entry.key;
            var def = entry.value;
            int level = _upgrades[key] ?? 1;
            int globalMax = (def['max_level'] ?? 10) as int;
            int tierMax = (_rocketTiers[_viewingTier]?['max_upgrades'] ?? globalMax) as int;
            
            bool isMaxed = level >= tierMax;
            int cost = isMaxed ? 0 : _getUpgradeCost(key, level);
            bool canAfford = _money >= cost && !isMaxed;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                    child: Center(child: Text(def['icon'], style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(def['name'], style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        _buildLevelDots(level, tierMax),
                      ],
                    ),
                  ),
                  _buildUpgradeButton(isMaxed, canAfford, cost, key),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLevelDots(int level, int max) {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: List.generate(max, (index) {
        bool isActive = index < level;
        return Container(
          width: 8, height: 6,
          decoration: BoxDecoration(
            color: isActive ? (isActive && index == max - 1 ? Colors.orangeAccent : Colors.greenAccent) : Colors.white12,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildUpgradeButton(bool isMaxed, bool canAfford, int cost, String key) {
    return ElevatedButton(
      onPressed: isMaxed ? null : () => _buyUpgrade(key),
      style: ElevatedButton.styleFrom(
        backgroundColor: isMaxed ? Colors.white10 : (canAfford ? Colors.amber[700] : Colors.blueGrey[800]),
        foregroundColor: isMaxed ? Colors.white24 : (canAfford ? Colors.black : Colors.white38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(80, 40),
      ),
      child: Text(isMaxed ? "MAX" : "💰 $cost", style: GoogleFonts.cairo(fontWeight: FontWeight.w900, fontSize: 13)),
    );
  }

  Widget _buildLaunchControls(int liters) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("سعة الخزان المختارة", style: GoogleFonts.cairo(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    Text("${liters}L", style: GoogleFonts.cairo(color: Colors.orangeAccent, fontWeight: FontWeight.w900, fontSize: 20)),
                  ],
                ),
                Slider(
                  value: _fuelPercent,
                  min: 0.1, max: 1.0,
                  divisions: 9,
                  activeColor: Colors.orangeAccent,
                  inactiveColor: Colors.orangeAccent.withOpacity(0.1),
                  onChanged: (val) => setState(() => _fuelPercent = val),
                ),
                Text(
                  "كلما زاد الوقود زاد الوزن، تحكم بخطة الإقلاع بذكاء",
                  style: GoogleFonts.cairo(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 25),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Container(
            height: 65,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(color: const Color(0xFFD00030).withOpacity(0.3), blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: ElevatedButton(
              onPressed: () => widget.onLaunch(_fuelPercent),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD00030),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 15),
                  Text("بدء عملية الإقلاع", style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRocketImage(String? url, {double size = 50, bool isLocked = false, Color? fallbackColor}) {
    final Color actualColor = fallbackColor ?? Colors.redAccent;
    
    if (url == null || url.isEmpty || url.length < 5) {
      return _buildFallbackRocketShape(actualColor, size, isLocked);
    }
    
    return CachedNetworkImage(
      imageUrl: url,
      height: size,
      fit: BoxFit.contain,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => const SizedBox(),
      errorWidget: (context, url, error) => _buildFallbackRocketShape(actualColor, size, isLocked),
    );
  }

  Widget _buildFallbackRocketShape(Color color, double size, bool isLocked) {
    final double opacity = isLocked ? 0.3 : 1.0;
    final Color finalColor = color.withOpacity(opacity);
    
    return SizedBox(
      width: size * 0.6,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Nose cone
          Container(
            width: size * 0.3,
            height: size * 0.25,
            decoration: BoxDecoration(
              color: finalColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(size * 0.5)),
            ),
          ),
          // Body
          Container(
            width: size * 0.45,
            height: size * 0.45,
            color: finalColor,
            child: Center(
              child: Container(
                width: size * 0.2,
                height: size * 0.2,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          // Fins
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: size * 0.15,
                height: size * 0.15,
                decoration: BoxDecoration(
                  color: finalColor.withOpacity(0.7 * opacity),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
                ),
              ),
              SizedBox(width: size * 0.15),
              Container(
                width: size * 0.15,
                height: size * 0.15,
                decoration: BoxDecoration(
                  color: finalColor.withOpacity(0.7 * opacity),
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
