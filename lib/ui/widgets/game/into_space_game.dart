import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/utils/image_utils.dart';

class IntoSpaceGame extends StatefulWidget {
  final Map<String, dynamic> gameSettings;
  final Map<String, dynamic> upgrades;
  final int rocketTier;
  final List<int> wonMilestones;
  final double initialFuelPercent;
  final bool isAdvancedMode;
  final Function(int stars, int totalCoins, int giftsCount, int coinsCount, int maxAltitude, List<int> newMilestones) onGameOver;

  const IntoSpaceGame({
    super.key,
    required this.gameSettings,
    required this.upgrades,
    required this.rocketTier,
    required this.wonMilestones,
    required this.onGameOver,
    this.initialFuelPercent = 1.0,
    this.isAdvancedMode = false,
  });

  @override
  State<IntoSpaceGame> createState() => _IntoSpaceGameState();
}

class _IntoSpaceGameState extends State<IntoSpaceGame> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  double _altitude = 0.0;
  double _velocity = 0.0;
  double _fuel = 100.0;
  double _pointsPerMeter = 0.1;
  
  // Physics Mastery Settings
  double _airDragPower = 3.0;
  double _gravityScalingFactor = 0.02;
  double _resistanceStartRatio = 0.5;
  double _maxVelocityCap = 14.0; // Terminal velocity for balanced gameplay

  double _maxFuel = 100.0;
  bool _isEngineOn = false;
  bool _isGameOver = false;
  bool _isCountdown = true;
  int _countdownValue = 3;
  int _starsEarned = 0;         // from gift boxes
  int _coinsEarned = 0;          // from coin bags (for upgrades)
  int _giftsCollectedCount = 0;  // gift box counter for HUD
  int _coinsCollectedCount = 0;  // coin bag counter for HUD
  double _maxAltitudeReached = 0.0;
  bool _isStaged = false;
  bool _hasWonPrize = false; // Legacy prize
  final Set<int> _sessionReachedMilestones = {}; // Tracking milestones in current flight

  double _playerX = 0.0; 
  double _cameraX = 0.0;
  double _tiltAngle = 0.0;
  bool _movingLeft = false;
  bool _movingRight = false;
  bool _movingDown = false;
  
  double _rocketWidth = 60.0;
  double _rocketHeight = 110.0;

  final List<_SkyItem> _skyItems = [];
  double _lastItemSpawnAltitude = 0;
  final List<_BackgroundObj> _spaceObs = [];
  final List<_SkyItem> _obstacles = []; // asteroids / meteors
  String _currentZoneName = '';
  String? _zoneBannerText;
  double _zoneBannerOpacity = 0.0;
  bool _isBoostActive = false; // speed gate flash

  late double _enginePower;
  late double _gravity;
  late double _airResistance;
  late double _maxAltitudeMap;
  late double _fuelConsumptionRate;
  int _starsPerGift = 5;  // direct stars per gift box
  int _coinValue = 10;    // coins per coin bag (for upgrades)
  // _pointsPerMeter removed (altitude excluded from score)
  late double _fuelGiftAmount;
  late double _spawnStartAltitude;
  bool _isBlockedByTier = false;
  double _physicsTimeScale = 1.0;
  double _obstacleDamagePercent = 0.15;
  
  // Dynamic Coin Settings
  bool _isDynamicCoinEnabled = false;
  int _coinIncreasePer1000m = 5;

  bool get _isAdvancedMode => widget.isAdvancedMode;


  @override
  void initState() {
    super.initState();
    _applyUpgrades();
    
    final rand = math.Random();
    for (int i = 0; i < 40; i++) {
        _spaceObs.add(_BackgroundObj(
            type: rand.nextDouble() > 0.7 ? 'UFO' : (rand.nextDouble() > 0.5 ? 'PLANET1' : 'PLANET2'),
            x: (rand.nextDouble() * 10) - 5.0,
            y: 3000.0 + (rand.nextDouble() * 7000.0),
            size: 40.0 + rand.nextDouble() * 60.0
        ));
    }

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 50))..repeat();
    _controller.addListener(_updatePhysics);
    _startCountdown();
  }

  void _startCountdown() async {
     for (int i = 3; i > 0; i--) {
        if (!mounted) return;
        setState(() => _countdownValue = i);
        await Future.delayed(const Duration(seconds: 1));
     }
     if (mounted) {
        setState(() {
           _isCountdown = false;
           _isEngineOn = true;
        });
     }
  }

  void _applyUpgrades() {
    int engineLv = widget.upgrades['engine_lv'] ?? 1;
    int fuelLv = widget.upgrades['fuel_lv'] ?? 1;
    int hullLv = widget.upgrades['hull_lv'] ?? 1;

    // Load Dynamic Definition
    final definitions = widget.gameSettings['rocket_custom_definitions'] as List?;
    Map<String, dynamic>? currentDef;
    if (definitions != null && widget.rocketTier <= definitions.length && widget.rocketTier > 0) {
       currentDef = definitions[widget.rocketTier - 1];
    }
    
    // Clamp levels to prevent lower tiers from inheriting max levels of higher tiers
    int maxLevelForTier = currentDef?['max_level'] ?? (widget.rocketTier == 1 ? 5 : (widget.rocketTier == 2 ? 10 : 15));
    if (engineLv > maxLevelForTier) engineLv = maxLevelForTier;
    if (fuelLv > maxLevelForTier) fuelLv = maxLevelForTier;
    if (hullLv > maxLevelForTier) hullLv = maxLevelForTier;

    double baseFuel = (currentDef?['base_fuel'] ?? widget.gameSettings['base_fuel'] ?? 100.0).toDouble();
    double fuelPerLevel = (currentDef?['fuel_per_upgrade'] ?? widget.gameSettings['fuel_per_upgrade'] ?? 25.0).toDouble();
    double baseThrust = (currentDef?['base_thrust'] ?? widget.gameSettings['base_thrust'] ?? 1.0).toDouble();
    if (baseThrust < 0.5) baseThrust = 0.5; // Safety minimum
    double thrustPerLevel = (currentDef?['thrust_per_upgrade'] ?? widget.gameSettings['thrust_per_upgrade'] ?? 0.2).toDouble();
    
    _fuelConsumptionRate = (currentDef?['fuel_consumption_rate'] ?? widget.gameSettings['fuel_consumption_rate'] ?? 0.6).toDouble();
    
    // Set dynamic dimensions based on tier
    if (widget.rocketTier == 1) {
      _rocketWidth = 60.0;
      _rocketHeight = 110.0;
    } else if (widget.rocketTier == 2) {
      _rocketWidth = 70.0;
      _rocketHeight = 130.0;
    } else {
      _rocketWidth = 80.0;
      _rocketHeight = 150.0;
    }

    _enginePower = baseThrust + ((engineLv - 1) * thrustPerLevel);
    if (_enginePower < 0.5) _enginePower = 0.5; // Final safety clamp
    
    _starsPerGift = (widget.gameSettings['stars_per_gift'] ?? 5).toInt();
    _coinValue = (widget.gameSettings['coin_gift_amount'] ?? 10).toInt();
    _isDynamicCoinEnabled = widget.gameSettings['dynamic_coin_enabled'] ?? false;
    _coinIncreasePer1000m = (widget.gameSettings['coin_increase_per_1000m'] ?? 5).toInt();
    _gravity = (currentDef?['gravity'] ?? widget.gameSettings['gravity'] ?? 0.5).toDouble();
    
    // Set specific max altitude for the tier to simulate structural limits
    _maxAltitudeMap = (currentDef?['max_altitude'] ?? (widget.rocketTier == 1 ? 3000.0 : (widget.rocketTier == 2 ? 15000.0 : widget.gameSettings['max_altitude'] ?? 100000.0))).toDouble();
    
    _fuelGiftAmount = (widget.gameSettings['fuel_gift_amount'] ?? 20.0).toDouble();
    
    // Dynamic Spawn Start: Tier 1 gets gifts much earlier (200m) to help beginners progress
    double baseSpawnAlt = (widget.gameSettings['spawn_start_altitude'] ?? 1000.0).toDouble();
    _spawnStartAltitude = (widget.rocketTier == 1) ? 200.0 : baseSpawnAlt;

    _enginePower = baseThrust + ((engineLv - 1) * thrustPerLevel);
    if (_enginePower < 0.5) _enginePower = 0.5; // Final safety clamp
    
    // Apply Stage Booster Multiplier
    if (_isStaged && currentDef != null) {
       double multiplier = (currentDef['capsule']['thrust_multiplier'] ?? 1.2).toDouble();
       _enginePower *= multiplier;
    }

    double globalBaseFuel = (widget.gameSettings['base_fuel'] ?? 300.0).toDouble();
    _maxFuel = globalBaseFuel + baseFuel + ((fuelLv - 1) * fuelPerLevel);
    _fuel = _maxFuel * widget.initialFuelPercent;

    _airDragPower = (widget.gameSettings['air_drag_power'] ?? 3.0).toDouble();
    _gravityScalingFactor = (widget.gameSettings['gravity_scaling_factor'] ?? 0.02).toDouble();
    _resistanceStartRatio = (widget.gameSettings['resistance_start_ratio'] ?? 0.5).toDouble();
    _maxVelocityCap = (widget.gameSettings['max_velocity_cap'] ?? 11.0).toDouble();
    _physicsTimeScale = (widget.gameSettings['physics_time_scale'] ?? 1.0).toDouble();
    _obstacleDamagePercent = (widget.gameSettings['obstacle_fuel_damage_percent'] ?? 0.15).toDouble();

    double baseDrag = (currentDef?['air_resistance'] ?? widget.gameSettings['air_resistance'] ?? 0.02).toDouble();
    _airResistance = baseDrag - ((hullLv - 1) * 0.0015);
    if (_airResistance < 0) _airResistance = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _updatePhysics() {
    if (_isGameOver || _isCountdown) return;

    setState(() {
      if (_fuel > 0) {
        _isEngineOn = true;
      } else {
        _isEngineOn = false;
      }

      if (_isEngineOn && _fuel > 0) {
        // Realistic Liftoff: gradually ramp to full power at 800m
        double liftoffIntensity = (_altitude < 800) ? (0.75 + (_altitude / 800.0) * 0.25) : 1.0;
        
        // Increased base coefficient so Tier 1 maxed can reach 2800-3000m
        double baseCoefficient = _isStaged ? 0.08 : 0.14;
        double verticalPower = _enginePower * baseCoefficient;
        
        _velocity += verticalPower * liftoffIntensity * _physicsTimeScale;
        
        // Balanced Fuel Consumption
        double consumptionModifier = _isAdvancedMode ? 1.0 : 0.8;
        _fuel -= _fuelConsumptionRate * consumptionModifier * _physicsTimeScale;
      }
      
      if (_fuel <= 0 && !_isStaged && _altitude > 300) {
          _isStaged = true;
          _velocity += 2.0; // Moderate staging boost
          _fuel = _maxFuel * 0.2; // 20% Spare fuel reserve
      }

      double targetTilt = 0.0;
      if (!_isBoostActive) {
        if (_movingLeft) {
          _playerX -= 0.015 * _physicsTimeScale; // Slotted speed control
          targetTilt = -0.4;
        }
        if (_movingRight) {
          _playerX += 0.015 * _physicsTimeScale; // Slotted speed control
          targetTilt = 0.4;
        }
      }
      
      _cameraX += (_playerX - _cameraX) * 0.1;
      _tiltAngle += (targetTilt - _tiltAngle) * 0.2;

      if (_movingDown) {
        _velocity -= 0.6;
      }

      double gravityEffect = _velocity < 0 ? (_gravity * 0.18) : (_gravity * 0.1); 

      // Progressive Gravity: gets slightly heavier but mathematically balanced
      if (_isAdvancedMode) {
        // زيادة خفيفة ومعتدلة للجاذبية (2% لكل 5000 متر)
        double multiplier = 1.0 + (_altitude / 5000.0) * 0.02;
        gravityEffect *= multiplier;
      }
      
      // Dynamic Atmospheric Resistance (Soft Cap)
      // Controlled via Admin Physics Mastery
      double dragMultiplier = 1.0;
      if (_altitude > _maxAltitudeMap * _resistanceStartRatio) {
         // Start increasing resistance gradually from the defined start ratio
         double ratio = (_altitude / _maxAltitudeMap);
         
         // Resistance kicks in and grows based on air_drag_power (Starts from e.g. 50%)
         dragMultiplier = 1.0 + math.pow(ratio.clamp(0.0, 5.0), _airDragPower);
         
         // Gravity penalty ONLY kicks in when it exceeds its absolute maximum altitude limit (100%)
         if (ratio > 1.0) {
             gravityEffect += (ratio - 1.0) * _gravityScalingFactor;
         }
      }

      _velocity -= gravityEffect * _physicsTimeScale;
      _velocity -= _velocity * (_airResistance * dragMultiplier * _physicsTimeScale);
      
      // Velocity Soft Cap (Terminal Velocity)
      // If velocity exceeds the cap, apply additional damping to keep it balanced
      if (_velocity > _maxVelocityCap) {
          double excess = _velocity - _maxVelocityCap;
          _velocity -= excess * 0.15; // Smoothly pull back to the cap
      }
      
      _altitude += _velocity * _physicsTimeScale;
      if (_altitude > _maxAltitudeReached) _maxAltitudeReached = _altitude;
      
      if (_altitude - _lastItemSpawnAltitude > 200) {
         _spawnItems();
         _lastItemSpawnAltitude = _altitude;
      }
      
      _checkCollisions();

      if (_altitude <= 0) {
        _altitude = 0;
        if (_velocity < -4.0) _endGame(_maxAltitudeReached.toInt(), _sessionReachedMilestones.toList());
        else {
           _velocity = 0;
           _tiltAngle = 0.0;
           if (_fuel <= 0 && !_isEngineOn && _altitude == 0) {
              _endGame(
                _maxAltitudeReached.toInt(),
                _sessionReachedMilestones.toList(),
              );
           }
        }
      }
    });
  }

  // --- Zone helpers ---
  String _getZoneName() {
    if (_altitude < 3000) return 'atmosphere';   // Blue Sky
    if (_altitude < 12000) return 'exosphere';   // Sunset/Transition
    if (_altitude < 35000) return 'stratosphere'; // Dark Blue/Purple
    if (_altitude < 100000) return 'mesosphere';  // Deep Purple
    return 'space';
  }

  Map<String, dynamic> _getZoneTheme() {
    final z = _getZoneName();
    if (z == 'atmosphere') return {'label': '🌍 الغلاف الجوي', 'top': Colors.lightBlue[300]!, 'bottom': Colors.blue[600]!, 'stars': false};
    if (z == 'exosphere') return {'label': '🌅 حدود الغلاف الجوي', 'top': Colors.deepOrange[800]!, 'bottom': Colors.indigo[900]!, 'stars': true};
    if (z == 'stratosphere') return {'label': '🌌 الستراتوسفير', 'top': const Color(0xFF0D0D40), 'bottom': const Color(0xFF1A1A80), 'stars': true};
    if (z == 'mesosphere') return {'label': '💫 حافة الفضاء', 'top': const Color(0xFF0A0020), 'bottom': const Color(0xFF3D006E), 'stars': true};
    return {'label': '🚀 الفضاء الخارجي', 'top': Colors.black, 'bottom': const Color(0xFF070710), 'stars': true};
  }

  void _spawnItems() {
     final rand = math.Random();
     double lootChanceMultiplier = (widget.gameSettings['loot_chance_multiplier'] ?? 1.0).toDouble();
     
     // Boost loot density in early altitudes for faster progression
     if (_altitude < 2000) lootChanceMultiplier *= 1.5;
     
     final zone = _getZoneName();
          // Spawn collectibles
      if (_altitude > _spawnStartAltitude && rand.nextDouble() > (0.1 / lootChanceMultiplier)) {
         String lootType = 'COIN';
         double rnd = rand.nextDouble();
         if (rnd > 0.7) lootType = 'FUEL';
         else if (rnd > 0.4) lootType = 'COIN';
         else if (!_isAdvancedMode) lootType = 'GIFT'; // No gifts in advanced mode
         else lootType = 'COIN'; // Fallback for advanced mode

         // If altitude is low, allow spawning items starting from _spawnStartAltitude
         // Otherwise, spawn 600m ahead to avoid pop-in
         double minSpawnY = math.max(_altitude + 600, _spawnStartAltitude);
         if (_altitude < _spawnStartAltitude + 500) {
            minSpawnY = _spawnStartAltitude;
         }
         double spawnY = minSpawnY + (rand.nextDouble() * 400);

         int? dynamicCoinValue;
         if (lootType == 'COIN' && _isDynamicCoinEnabled) {
            int multiplier = (spawnY / 1000.0).floor();
            dynamicCoinValue = _coinValue + (multiplier * _coinIncreasePer1000m);
         }

         _skyItems.add(_SkyItem(
             type: lootType,
             x: _playerX + (rand.nextDouble() * 2) - 1.0,
             y: spawnY,
             coinValue: dynamicCoinValue,
         ));
       }
     // Spawn obstacles (asteroids) based on zone
     double obstacleChance = zone == 'atmosphere' ? 0.0
       : zone == 'stratosphere' ? 0.1
       : zone == 'mesosphere' ? 0.3
       : zone == 'space' ? 0.55
       : 0.75; // deep space = most dangerous
     
     if (rand.nextDouble() < obstacleChance) {
       List<String> types = ['ASTEROID', 'METEOR'];
       if (zone == 'mesosphere' || zone == 'space' || zone == 'deepspace') types.add('SATELLITE');
       if (zone == 'space' || zone == 'deepspace') types.add('ALIEN_SHIP');
       
       _obstacles.add(_SkyItem(
         type: types[rand.nextInt(types.length)],
         x: _playerX + (rand.nextDouble() * 4) - 2.0,
         y: _altitude + 600 + (rand.nextDouble() * 1000),
       ));
     }
     // Spawn PORTALS above 5000m
     if (_altitude > 5000 && rand.nextDouble() < 0.15) {
       _skyItems.add(_SkyItem(
         type: 'PORTAL',
         x: _playerX + (rand.nextDouble() * 3) - 1.5,
         y: _altitude + 700 + (rand.nextDouble() * 800),
       ));
     }
     _obstacles.removeWhere((o) => o.y < _altitude - 600);
     
     // Show zone banner on zone change
     final newZone = _getZoneName();
     if (newZone != _currentZoneName) {
       _currentZoneName = newZone;
       final theme = _getZoneTheme();
       _zoneBannerText = theme['label'] as String;
       _zoneBannerOpacity = 1.0;
       Future.delayed(const Duration(seconds: 2), () {
         if (mounted) setState(() => _zoneBannerOpacity = 0.0);
       });
     }
  }

  void _checkCollisions() {
      // --- Screen-space hitbox: map rocket pixel size to game coordinates ---
      // The rocket's altitude units-per-pixel ratio is derived from the screen.
      // We use a fixed scale: 1 pixel ≈ 1 altitude unit (items are spawned in altitude space).
      // So the hitbox IS the physical pixel size of the rocket image.
      double rW = _isStaged ? (_rocketWidth * 0.66) : _rocketWidth;
      double rH = _isStaged ? (_rocketHeight * 0.55) : _rocketHeight;

      // Map pixel sizes to game coordinate space dynamically based on device!
      double pixelsPerUnitX = MediaQuery.of(context).size.width / 2.0;
      double horizontalRocketThreshold = (rW / 2.0) / pixelsPerUnitX;
      // Vertical: altitude increases by ~velocity units/frame. Items are in altitude units.
      // 1 px ≈ 1 altitude unit worked well empirically (vertical scroll maps 1:1).
      double verticalRocketThreshold = rH / 2.0;

      for (int i = _skyItems.length - 1; i >= 0; i--) {
          final item = _skyItems[i];
          double dx = (item.x - _playerX).abs();
          double dy = (item.y - _altitude).abs();

          // Calculate Item Radius based on visual size (Portal=62px, others=44px approx)
          double itemRadiusPx = item.type == 'PORTAL' ? 31.0 : 22.0; 
          double horizontalItemRadius = itemRadiusPx / pixelsPerUnitX;
          double verticalItemRadius = itemRadiusPx;

          // Direct Touch from any side!
          if (dx < (horizontalRocketThreshold + horizontalItemRadius) && 
              dy < (verticalRocketThreshold + verticalItemRadius)) {
             double lootValueMultiplier = (widget.gameSettings['loot_amount_multiplier'] ?? 1.0).toDouble();
             _audioPlayer.play(AssetSource('sounds/collect.mp3'));
             if (item.type == 'FUEL') {
                 _fuel = (_fuel + (_fuelGiftAmount * lootValueMultiplier)).clamp(0.0, _maxFuel);
             } else if (item.type == 'COIN') {
                 int val = item.coinValue ?? _coinValue;
                 _coinsEarned += (val * lootValueMultiplier).toInt();
                 _coinsCollectedCount++;
             } else if (item.type == 'GIFT') {
                 _starsEarned += _starsPerGift;
                 _giftsCollectedCount++;
             } else if (item.type == 'PORTAL') {
                 _velocity += 8.0;
                 _isBoostActive = true;
                 Future.delayed(const Duration(milliseconds: 600), () {
                   if (mounted) setState(() => _isBoostActive = false);
                 });
             }
             _skyItems.removeAt(i);
          }
      }

      // Check Win Milestones (Advanced Mode)
      if (_isAdvancedMode) {
          final milestones = widget.gameSettings['rocket_win_milestones'] as List?;
          if (milestones != null) {
              for (var m in milestones) {
                  int alt = m['altitude'] as int;
                  if (_altitude >= alt && !_sessionReachedMilestones.contains(alt) && !widget.wonMilestones.contains(alt)) {
                      _sessionReachedMilestones.add(alt);
                      int prize = m['prize'] as int;
                      String msg = m['message'] ?? "مبروك! هدف جديد!";
                      
                      _starsEarned += prize;
                      _zoneBannerText = "🎉 $msg (+ $prize نجمة)";
                      _zoneBannerOpacity = 1.0;
                      _audioPlayer.play(AssetSource('sounds/win.mp3'));
                      
                      Future.delayed(const Duration(seconds: 4), () {
                        if (mounted) setState(() => _zoneBannerOpacity = 0.0);
                      });
                  }
              }
          }
      }

      // Check obstacle (asteroid) collisions — pixel-accurate hitbox (80% for fairness)
      for (int i = _obstacles.length - 1; i >= 0; i--) {
          final obs = _obstacles[i];
          double dx = (obs.x - _playerX).abs();
          double dy = (obs.y - _altitude).abs();

          double rW = _isStaged ? (_rocketWidth * 0.66) : _rocketWidth;
          double rH = _isStaged ? (_rocketHeight * 0.55) : _rocketHeight;
          double pixelsPerUnitX = MediaQuery.of(context).size.width / 2.0;

          // Astroids are ~32px, radius = 16px.
          double hThreshold = (((rW / 2.0) + 16.0) / pixelsPerUnitX) * 0.8; // 80% forgiveness
          double vThreshold = ((rH / 2.0) + 16.0) * 0.8;

          if (dx < hThreshold && dy < vThreshold) {
            _fuel = (_fuel - _maxFuel * _obstacleDamagePercent).clamp(0.0, _maxFuel);
            _velocity *= 0.6;
            _obstacles.removeAt(i);
          }
      }
  }

  Color _getBackgroundColor() {
    // Continuous Gradient Map with much wider ranges for slow, majestic transitions
    final List<Map<String, dynamic>> colorStops = [
      {'alt': 0.0, 'color': const Color(0xFF87CEEB)},       // Sky Blue (Day)
      {'alt': 12000.0, 'color': const Color(0xFFFF8C00)},   // Dark Orange (Peak sunset at 12km)
      {'alt': 28000.0, 'color': const Color(0xFFFF1493)},   // Deep Pink (High stratosphere)
      {'alt': 45000.0, 'color': const Color(0xFF2E1A47)},   // Midnight Purple (Mesosphere)
      {'alt': 70000.0, 'color': const Color(0xFF0F0F1A)},   // Dark Navy (Edge of space)
      {'alt': 95000.0, 'color': const Color(0xFF000000)},   // Pitch Black (Deep Space)
      {'alt': 150000.0, 'color': const Color(0xFF000000)}, 
    ];

    if (_altitude <= 0) return colorStops.first['color'];
    if (_altitude >= colorStops.last['alt']) return colorStops.last['color'];

    for (int i = 0; i < colorStops.length - 1; i++) {
      if (_altitude >= colorStops[i]['alt'] && _altitude <= colorStops[i + 1]['alt']) {
        double t = (_altitude - colorStops[i]['alt']) / (colorStops[i + 1]['alt'] - colorStops[i]['alt']);
        return Color.lerp(colorStops[i]['color'], colorStops[i + 1]['color'], t)!;
      }
    }
    return colorStops.last['color'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _getBackgroundColor(),
      body: Stack(
        children: [
          _buildSpaceBackground(),
          _buildWinLine(),
          ..._buildSkyItems(),
          _buildGroundAtmosphere(),
          _buildPlatform(),
          _buildRocket(),
          _buildUI(),
          _buildAltitudeMap(),
          _buildControls(),

          // Tier Blocked Warning
          if (_isBlockedByTier)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              left: 40, right: 40,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  "⛔ ضغط جوي هائل! صاروخك لا يستطيع الصعود أكثر. تحتاج لتطوير طراز الصاروخ من الورشة!",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),

          if (_isCountdown) _buildCountdown(),
          // Boost flash overlay
          if (_isBoostActive)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _isBoostActive ? 0.35 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(color: Colors.cyanAccent),
                ),
              ),
            ),
          // Zone entry banner
          if (_zoneBannerText != null)
            Positioned(
              top: 130,
              left: 0, right: 0,
              child: AnimatedOpacity(
                opacity: _zoneBannerOpacity,
                duration: const Duration(milliseconds: 600),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white30, width: 1.5),
                    ),
                    child: Text(
                      _zoneBannerText!,
                      style: GoogleFonts.cairo(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUI() {
    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Column(
        children: [
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (_fuel / _maxFuel).clamp(0.0, 1.0),
                backgroundColor: Colors.transparent,
                color: _fuel / _maxFuel > 0.3 ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoText("FUEL", "${_fuel.toInt()}L"),
              _infoText("ALT", "${_altitude.toInt()}m"),
              _infoText("🎁", "x$_giftsCollectedCount"),
              _infoText("💰", "x$_coinsCollectedCount"),
            ],
          ),
        ],
      ),
    );
  }
  Widget _infoText(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.cairo(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ],
    );
  }

  Widget _buildSpaceBackground() {
    return Stack(
      children: [
        // 1. Deep Space Nebulas (Cinematic Shapes)
        if (_altitude > 15000)
             ...List.generate(5, (index) {
                final random = math.Random(index + 77);
                double worldX = random.nextDouble() * 2 - 1.0;
                double worldY = random.nextDouble() * 2 - 1.0;
                
                // Very Slow Drift Parallax (0.005 to 0.015)
                double depth = 0.005 + (index * 0.002); 
                
                double screenX = (worldX - _cameraX * depth) * MediaQuery.of(context).size.width / 2 + MediaQuery.of(context).size.width/2;
                double screenY = (worldY - (_altitude * depth * 0.05)) % MediaQuery.of(context).size.height;
                
                List<Color> nebulaColors = [
                   Colors.deepPurple.withOpacity(0.12),
                   Colors.indigo.withOpacity(0.1),
                   Colors.pinkAccent.withOpacity(0.08),
                   Colors.blueAccent.withOpacity(0.1),
                   Colors.orangeAccent.withOpacity(0.05),
                ];

                return Positioned(
                  left: screenX - 300,
                  top: screenY - 300,
                  child: Container(
                    width: 600, height: 600,
                    decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       gradient: RadialGradient(
                          colors: [nebulaColors[index % nebulaColors.length], Colors.transparent],
                       ),
                    ),
                  ),
                );
             }),

        // 2. Far Celestial Objects (Moon/Planet)
        if (_altitude > 5000)
            Positioned(
              right: MediaQuery.of(context).size.width * 0.15,
              // Majestic slow drift (0.008 speed)
              top: (250 - (_altitude * 0.008)) % (MediaQuery.of(context).size.height * 3), 
              child: Opacity(
                 opacity: (_altitude > 12000) ? 0.9 : ((_altitude - 5000) / 7000).clamp(0, 0.9),
                 child: Text(
                    _altitude > 35000 ? "🪐" : "🌕", 
                    style: const TextStyle(fontSize: 80, shadows: [Shadow(color: Colors.white24, blurRadius: 60)]),
                 ),
              ),
            ),

        // 3. Distant Stars (Majestic Slow Flow)
        if (_altitude > 1500)
          ...List.generate(_altitude > 45000 ? 60 : 30, (index) {
            final random = math.Random(index + 123);
            double worldX = (random.nextDouble() * 2.0 - 1.0);
            double worldY = random.nextDouble();
            
            // Background stars move very slowly (coefficient 0.03 vs 0.4 before)
            double screenX = (worldX - _cameraX * 0.05) * MediaQuery.of(context).size.width / 2 + MediaQuery.of(context).size.width/2;
            double screenY = (worldY * MediaQuery.of(context).size.height + (_altitude * 0.03)) % MediaQuery.of(context).size.height;
            
            // Warp trails only if really fast or very deep
            bool isWarp = (_velocity > 12.0 || _altitude > 50000) && random.nextDouble() > 0.6;
            
            return Positioned(
              left: screenX,
              top: screenY,
              child: Container(
                 width: isWarp ? 1.0 : 2.0, 
                 height: isWarp ? 45.0 : 2.2, 
                 decoration: BoxDecoration(
                   color: isWarp ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.7),
                   borderRadius: BorderRadius.circular(2),
                   boxShadow: isWarp ? [const BoxShadow(color: Colors.white24, blurRadius: 5)] : null,
                 )
              ),
            );
          }),
        ..._spaceObs.where((o) => (o.y - _altitude).abs() < 1000).map((o) {
          final screenY = MediaQuery.of(context).size.height / 2 - ((o.y - _altitude) * 0.5);
          final screenX = (o.x - _cameraX + 1.0) / 2.0 * MediaQuery.of(context).size.width;
          return Positioned(
            left: screenX,
            top: screenY,
            child: Text(o.type == 'UFO' ? '🛸' : (o.type == 'PLANET1' ? '🪐' : '🌕'), style: TextStyle(fontSize: o.size)),
          );
        }),
      ],
    );
  }

  List<Widget> _buildSkyItems() {
    final List<Widget> result = [];
    // Collectibles
    for (final o in _skyItems.where((o) => (o.y - _altitude).abs() < 800)) {
      final screenY = MediaQuery.of(context).size.height * 0.6 - ((o.y - _altitude));
      final screenX = (o.x - _cameraX + 1.0) / 2.0 * MediaQuery.of(context).size.width;
      String iconText = '❓';
      double iconSize = 24.0;
      if (o.type == 'PORTAL') {
          iconText = '🌀';
          iconSize = 42.0;
      } else if (o.type == 'GIFT') {
          iconText = '🎁';
      } else if (o.type == 'FUEL') {
          iconText = '⛽';
      } else if (o.type == 'COIN') {
          iconText = '🪙'; // عملة ذهبية للقيمة القليلة
          iconSize = 24.0;
          if (o.coinValue != null && _coinIncreasePer1000m > 0) {
              int diff = o.coinValue! - _coinValue;
              if (diff >= _coinIncreasePer1000m * 15) {
                  iconText = '👑💎'; // تاج مع ألماس
                  iconSize = 40.0;
              } else if (diff >= _coinIncreasePer1000m * 10) {
                  iconText = '💎'; // ألماسة
                  iconSize = 36.0;
              } else if (diff >= _coinIncreasePer1000m * 5) {
                  iconText = '💰💰'; // أكياس ذهب
                  iconSize = 32.0;
              } else if (diff >= _coinIncreasePer1000m * 2) {
                  iconText = '💰'; // كيس ذهب
                  iconSize = 28.0;
              }
          }
      }

      result.add(Positioned(
        left: screenX, top: screenY,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white54, width: 2)),
          child: Text(iconText, style: TextStyle(fontSize: iconSize)),
        ),
      ));
    }
    // Obstacles (asteroids/meteors/satellites/ships)
    for (final o in _obstacles.where((o) => (o.y - _altitude).abs() < 1000)) {
      final screenY = MediaQuery.of(context).size.height * 0.6 - ((o.y - _altitude));
      final screenX = (o.x - _cameraX + 1.0) / 2.0 * MediaQuery.of(context).size.width;
      
      String emoji = '☄️';
      if (o.type == 'ASTEROID') emoji = '🪨';
      else if (o.type == 'SATELLITE') emoji = '🛰️';
      else if (o.type == 'ALIEN_SHIP') emoji = '👾';

      result.add(Positioned(
        left: screenX, top: screenY,
        child: Text(emoji, style: const TextStyle(fontSize: 32)),
      ));
    }
    return result;
  }

  Widget _buildWinLine() {
    if (!_isAdvancedMode) return const SizedBox();
    
    final milestones = widget.gameSettings['rocket_win_milestones'] as List?;
    if (milestones == null || milestones.isEmpty) return const SizedBox();
    
    // Find nearest upcoming milestone
    int? nearestAlt;
    for (var m in milestones) {
        int alt = m['altitude'] as int;
        if (alt > _maxAltitudeReached && !widget.wonMilestones.contains(alt) && (nearestAlt == null || alt < nearestAlt)) {
            nearestAlt = alt;
        }
    }
    
    if (nearestAlt == null) return const SizedBox();
    if ((nearestAlt - _altitude).abs() > 1500) return const SizedBox();
    
    final screenY = MediaQuery.of(context).size.height * 0.6 - (nearestAlt - _altitude);
    
    return Positioned(
      top: screenY,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.yellow.withOpacity(0.0), Colors.yellow, Colors.black, Colors.yellow, Colors.yellow.withOpacity(0.0)],
              ),
              boxShadow: const [BoxShadow(color: Colors.yellow, blurRadius: 30)],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
            child: Text(
               "🏁 الجائزة التالية عند ($nearestAlt متر)",
               style: GoogleFonts.cairo(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroundAtmosphere() {
    if (_altitude > 800) return const SizedBox();
    return Positioned(
      bottom: -(_altitude * 1.5), 
      left: 0,
      right: 0,
      child: Container(
         height: 400,
         decoration: BoxDecoration(
            gradient: LinearGradient(
               begin: Alignment.topCenter,
               end: Alignment.bottomCenter,
               colors: [Colors.transparent, Colors.orange.withOpacity(0.2), Colors.deepOrange[900]!.withOpacity(0.8)],
            ),
         ),
      ),
    );
  }

  Widget _buildPlatform() {
    if (_altitude > 500) return const SizedBox();
    return Positioned(
      bottom: -(_altitude * 2),
      left: 0,
      right: 0,
      child: SizedBox(
        height: 300,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Launch Pad Ground Surface
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Container(
                height: 20,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isAdvancedMode 
                        ? [Colors.blueGrey[900]!, Colors.blueGrey[800]!] 
                        : [Colors.grey[800]!, Colors.grey[700]!],
                  ),
                ),
                child: widget.isAdvancedMode ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(20, (i) => Container(width: 4, height: 20, color: i % 2 == 0 ? Colors.cyan.withOpacity(0.3) : Colors.transparent)),
                ) : null,
              ),
            ),

            // Base structure
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: widget.isAdvancedMode ? Colors.blueGrey[900] : Colors.grey[850], 
                  border: Border(top: BorderSide(color: widget.isAdvancedMode ? Colors.cyanAccent : Colors.amberAccent, width: 4)),
                  boxShadow: widget.isAdvancedMode ? [
                    BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 15, spreadRadius: 2),
                    BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 40, spreadRadius: 5),
                  ] : null,
                ),
                child: Stack(
                   children: [
                      if (widget.isAdvancedMode) 
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.1,
                            child: CachedNetworkImage(
                              imageUrl: "https://www.transparenttextures.com/patterns/carbon-fibre.png",
                              repeat: ImageRepeat.repeat,
                              errorWidget: (context, url, error) => const SizedBox(),
                            ),
                          ),
                        ),
                      Center(
                        child: Text(
                          widget.isAdvancedMode ? "NEO-SPACE HUB" : "STARHAT PORT", 
                          style: GoogleFonts.cairo(
                            color: widget.isAdvancedMode ? Colors.cyanAccent : Colors.grey[400], 
                            fontSize: 20, 
                            fontWeight: FontWeight.bold, 
                            letterSpacing: 5,
                            shadows: widget.isAdvancedMode ? [const Shadow(color: Colors.cyan, blurRadius: 10)] : null,
                          ),
                        ),
                      ),
                   ],
                ),
              ),
            ),

            // Advanced Launch Tower (Left)
            if (widget.isAdvancedMode)
              Positioned(
                bottom: 0,
                left: MediaQuery.of(context).size.width / 2 - 140,
                child: Container(
                   width: 30, height: 280,
                   decoration: BoxDecoration(
                      color: Colors.blueGrey[900],
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 1),
                   ),
                   child: Stack(
                      children: [
                         ...List.generate(10, (i) => Positioned(
                            top: i * 25.0,
                            left: 0, right: 0,
                            child: Container(height: 1, color: Colors.cyanAccent.withOpacity(0.2)),
                         )),
                         // Blinking Light
                         Positioned(
                            top: 5, left: 10,
                            child: _BlinkingLight(color: Colors.redAccent),
                         ),
                      ],
                   ),
                ),
              ),

            // Launch Pedestal
            Positioned(
              bottom: 60,
              child: Container(
                width: 180,
                height: 20,
                decoration: BoxDecoration(
                  color: widget.isAdvancedMode ? Colors.blueGrey[800] : Colors.grey[400],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  border: Border.all(color: widget.isAdvancedMode ? Colors.cyanAccent : Colors.grey[600]!, width: 2),
                  boxShadow: widget.isAdvancedMode ? [const BoxShadow(color: Colors.cyanAccent, blurRadius: 10)] : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(10, (i) => Container(width: 8, color: widget.isAdvancedMode ? Colors.cyan : Colors.amber)),
                ),
              ),
            ),
            
            // Supportive Structures
            Positioned(bottom: 0, left: MediaQuery.of(context).size.width / 2 - 70, child: Container(width: 20, height: 60, color: widget.isAdvancedMode ? Colors.black : Colors.grey[800])),
            Positioned(bottom: 0, right: MediaQuery.of(context).size.width / 2 - 70, child: Container(width: 20, height: 60, color: widget.isAdvancedMode ? Colors.black : Colors.grey[800])),
            
            // Decorative Advanced Elements
            if (widget.isAdvancedMode) ...[
              Positioned(
                bottom: 60,
                left: MediaQuery.of(context).size.width / 2 + 100,
                child: Container(
                  width: 4, height: 180,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.cyanAccent, Colors.cyanAccent.withOpacity(0.0)],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter
                    )
                  ),
                )
              ),
              Positioned(
                bottom: 240,
                left: MediaQuery.of(context).size.width / 2 + 94,
                child: const Text("📡", style: TextStyle(fontSize: 24)),
              ),
              // Warning Stripes on ground
              Positioned(
                bottom: 0,
                left: 0, right: 0,
                child: Row(
                   children: List.generate(40, (i) => Expanded(
                      child: Container(
                         height: 5,
                         color: i % 2 == 0 ? Colors.amber[700] : Colors.black,
                      ),
                   )),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildRocket() {
    // Load Dynamic Definition
    final definitions = widget.gameSettings['rocket_custom_definitions'] as List?;
    Map<String, dynamic>? currentDef;
    if (definitions != null && widget.rocketTier <= definitions.length) {
       currentDef = definitions[widget.rocketTier - 1];
    }

    // Determine visual style
    Map<String, dynamic>? stageData = _isStaged 
        ? (currentDef?['capsule'] as Map<String, dynamic>?) 
        : (currentDef?['full'] as Map<String, dynamic>?);
    String? imageUrl = stageData?['image_url'];
    Color rocketColor = Color(int.tryParse(stageData?['color'] ?? '0xFFE53935') ?? 0xFFE53935);
    
    // Default fallback visual if no definition exists
    if (currentDef == null) {
       rocketColor = widget.rocketTier == 3 ? Colors.cyanAccent : (widget.rocketTier == 2 ? Colors.blueAccent : Colors.redAccent);
    }

    return Align(
      alignment: Alignment(_playerX - _cameraX, 0.6),
      child: Transform.rotate(
        angle: _tiltAngle,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Engine Flame — positioned directly BELOW the rocket body
            if (_isEngineOn && !_isGameOver && _fuel > 0)
              Positioned(
                // Place flame right at the bottom edge of the rocket visual
                top: _isStaged ? (_rocketHeight * 0.55) : _rocketHeight,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 100),
                  builder: (context, value, child) {
                    double flameW = _isStaged ? (_rocketWidth * 0.35) : (_rocketWidth * 0.42);
                    double flameH = (_isStaged ? 22.0 : 55.0) + (math.Random().nextDouble() * 20);
                    return Container(
                      width: flameW,
                      height: flameH,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Colors.yellow, Colors.deepOrange, Colors.transparent],
                          stops: [0.0, 0.2, 0.6, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.orangeAccent.withOpacity(0.6), blurRadius: 15, spreadRadius: 2),
                        ],
                      ),
                    );
                  },
                ),
              ),
            
            // Expected Falling Booster (Separation Animation)
            if (_isStaged && currentDef != null && currentDef['booster'] != null && currentDef['booster']['image_url'] != null && currentDef['booster']['image_url'].toString().isNotEmpty)
              TweenAnimationBuilder<double>(
                key: const ValueKey('booster_separation_animation'),
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 2500),
                curve: Curves.easeIn,
                builder: (context, value, child) {
                  return Positioned(
                    top: 60 + (value * 800), // Falls away 800 pixels
                    child: Opacity(
                      opacity: (1.0 - value).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: value * math.pi * 1.5, // Spins as it falls
                        child: Container(
                          width: 60,
                          height: 60,
                        child: ImageUtils.proxyUrl((currentDef?['booster'] as Map<String, dynamic>?)?['image_url']) != null
                            ? CachedNetworkImage(
                                imageUrl: ImageUtils.proxyUrl((currentDef?['booster'] as Map<String, dynamic>?)?['image_url'])!,
                                fit: BoxFit.contain,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                errorWidget: (context, url, error) => Container(color: Colors.grey),
                              )
                            : Container(color: Colors.grey),
                        ),
                      ),
                    ),
                  );
                },
              ),
              
            // Rocket Body (Image or Shape)
            Container(
              width: _isStaged ? (_rocketWidth * 0.66) : _rocketWidth,
              height: _isStaged ? (_rocketHeight * 0.55) : _rocketHeight,
              child: imageUrl != null && imageUrl.isNotEmpty && ImageUtils.proxyUrl(imageUrl) != null
                  ? CachedNetworkImage(
                      imageUrl: ImageUtils.proxyUrl(imageUrl)!,
                      fit: BoxFit.contain,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (context, url) => const SizedBox(),
                      errorWidget: (context, url, error) => _buildFallbackShape(rocketColor),
                    )
                  : _buildFallbackShape(rocketColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackShape(Color color) {
    if (_isStaged) {
      return Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 2),
        ),
      );
    }
    return Column(
      children: [
        // Nose cone
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        ),
        // Body
        Container(width: 50, height: 60, color: color),
        // Fins
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Container(width: 15, height: 20, color: color.withOpacity(0.7)),
             const SizedBox(width: 20),
             Container(width: 15, height: 20, color: color.withOpacity(0.7)),
          ],
        )
      ],
    );
  }




  Widget _buildControls() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        Positioned(
          left: 20,
          bottom: 30 + bottomPadding,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                 _controlBtn(Icons.arrow_back_ios_new_rounded, (val) => setState(() => _movingLeft = val)),
                 const SizedBox(width: 40),
                 _controlBtn(Icons.arrow_forward_ios_rounded, (val) => setState(() => _movingRight = val)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 30 + bottomPadding,
          child: _controlBtn(Icons.arrow_downward_rounded, (val) => setState(() => _movingDown = val)),
        ),
      ],
    );
  }

  Widget _controlBtn(IconData icon, Function(bool) onPush) {
    return Listener(
      onPointerDown: (_) => onPush(true),
      onPointerUp: (_) => onPush(false),
      onPointerCancel: (_) => onPush(false),
      child: Container(
        width: 65,
        height: 65,
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }

  Widget _buildAltitudeMap() {
    return Positioned(
      right: 15,
      top: 120,
      bottom: 150,
      child: Container(
        width: 30,
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24, width: 1.5)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Gradient (Atmosphere)
            Container(
              width: 15,
              margin: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Color(0xFF1A1A40), Colors.blue, Colors.lightBlue],
                  stops: [0.0, 0.4, 0.8, 1.0],
                ),
              ),
            ),
            const Positioned(top: 5, child: Text("🌕", style: TextStyle(fontSize: 12))),
            const Positioned(bottom: 5, child: Text("🌍", style: TextStyle(fontSize: 12))),
            Align(
              // Progress against Deep Space Goal (100,000m)
              alignment: Alignment(0, 1.0 - (_altitude / 100000.0).clamp(0, 1) * 2),
              child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red, blurRadius: 4)])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        builder: (context, value, child) {
          return Transform.scale(
            scale: value * 2.0,
            child: Text(
              _countdownValue > 0 ? "$_countdownValue" : "انطلاق!",
              style: GoogleFonts.cairo(color: Colors.redAccent, fontSize: 80, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
            ),
          );
        },
      ),
    );
  }

  void _endGame(int finalAlt, List<int> newMilestones) {
    if (_isGameOver) return;
    setState(() => _isGameOver = true);
    _controller.stop();
    // Final score = Only Gifts points (altitude excluded)
    widget.onGameOver(_starsEarned, _coinsEarned, _giftsCollectedCount, _coinsCollectedCount, finalAlt, newMilestones);
  }
}

class _SkyItem {
  final String type;
  final double x;
  final double y;
  final int? coinValue;
  _SkyItem({required this.type, required this.x, required this.y, this.coinValue});
}

class _BackgroundObj {
  final String type;
  final double x;
  final double y;
  final double size;
  _BackgroundObj({required this.type, required this.x, required this.y, required this.size});
}

class _BlinkingLight extends StatefulWidget {
  final Color color;
  const _BlinkingLight({required this.color});
  @override
  State<_BlinkingLight> createState() => _BlinkingLightState();
}

class _BlinkingLightState extends State<_BlinkingLight> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: widget.color, blurRadius: 4)]),
      ),
    );
  }
}
