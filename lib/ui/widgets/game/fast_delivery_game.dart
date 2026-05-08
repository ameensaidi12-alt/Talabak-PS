import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';

class FastDeliveryGame extends StatefulWidget {
  final Function(int score) onGameOver;
  final Function(int score) onGameWin;
  final double initialSpeed;
  final double accelerationRate;
  final double maxSpeed;
  final int minScoreForReward;   // عتبة الفوز والجائزة فقط
  final int themeScoreThreshold; // عتبة تغيير الثيم ووضع النار (مستقلة)
  final int accelerationInterval;
  final double accelerationStep;
  final int accelerationDelay;
  final bool isCompetitionMode;
  final double speedMultiplier;
  final int giftsPer5Seconds;

  const FastDeliveryGame({
    super.key,
    required this.onGameOver,
    required this.onGameWin,
    this.initialSpeed = 1.0,
    this.accelerationRate = 0.0001,
    this.maxSpeed = 30.0,
    this.minScoreForReward = 500,
    this.themeScoreThreshold = 50,
    this.accelerationInterval = 5,
    this.accelerationStep = 0.5,
    this.accelerationDelay = 10,
    this.isCompetitionMode = false,
    this.speedMultiplier = 1.0,
    this.giftsPer5Seconds = 1,
  });

  @override
  State<FastDeliveryGame> createState() => _FastDeliveryGameState();
}

class GameTheme {
  final List<Color> roadColors;
  final Color lineColor;
  final Color boundaryColor;
  final Color trailColor;
  final Color backgroundColor;
  final String label;

  GameTheme({
    required this.roadColors,
    required this.lineColor,
    required this.boundaryColor,
    required this.trailColor,
    required this.backgroundColor,
    required this.label,
  });
}

enum GameObjectType { car, truck, van, sportCar, gift, bullet, ammo }

class GameObject {
  double x;
  double y;
  final GameObjectType type;
  final Color color;
  bool isCollected = false;
  bool isDestroyed = false;

  GameObject({
    required this.x,
    required this.y,
    required this.type,
    this.color = Colors.red,
  });

  bool get isObstacle =>
    type == GameObjectType.car ||
    type == GameObjectType.truck ||
    type == GameObjectType.van ||
    type == GameObjectType.sportCar;

  bool get isItem => type == GameObjectType.gift || type == GameObjectType.ammo;
  bool get isBullet => type == GameObjectType.bullet;
}

class _FastDeliveryGameState extends State<FastDeliveryGame> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _playerX = 0; // -1 to 1
  int _score = 0;
  bool _isGameOver = false;
  bool _gameStarted = false; // New state for pre-game tutorial
  final List<GameObject> _obstacles = [];
  final List<GameObject> _items = [];
  final List<GameObject> _bullets = [];
  double _speed = 0;
  double _spawnTimer = 0;
  double _gameTime = 0;
  bool _isFieryMode = false;
  int _playerTier = 0; // 0: Scooter, 1: Car, 2: Truck, 3: Tank
  int _ammoCount = 0;
  int _currentThemeIndex = 0;
  double _gift5sTimer = 0; // Timer for 5-second gift spawn
  final AudioPlayer _audioPlayer = AudioPlayer();

  final List<GameTheme> _themes = [
    GameTheme(
      label: "البداية الهادئة",
      backgroundColor: const Color(0xFF2C3E50),
      roadColors: [const Color(0xFF2C3E50), const Color(0xFF1A252F)],
      lineColor: Colors.white24,
      boundaryColor: Colors.white10,
      trailColor: Colors.orange,
    ),
    GameTheme(
      label: "تسخين المحركات",
      backgroundColor: const Color(0xFF1E3A5F),
      roadColors: [const Color(0xFF1E3A5F), const Color(0xFF0F172A)],
      lineColor: Colors.blueAccent.withOpacity(0.4),
      boundaryColor: Colors.blue,
      trailColor: Colors.blue,
    ),
    GameTheme(
      label: "اندفاع الأدرينالين",
      backgroundColor: const Color(0xFF3D1505),
      roadColors: [const Color(0xFF3D1505), const Color(0xFF1A0A05)],
      lineColor: Colors.orangeAccent.withOpacity(0.4),
      boundaryColor: Colors.orange,
      trailColor: Colors.deepOrange,
    ),
    GameTheme(
      label: "سرعة البرق",
      backgroundColor: const Color(0xFF2C1A1A),
      roadColors: [const Color(0xFF2C1A1A), const Color(0xFF1A1110)],
      lineColor: Colors.yellowAccent.withOpacity(0.5),
      boundaryColor: Colors.yellow,
      trailColor: Colors.yellow,
    ),
    GameTheme(
      label: "الوضع الناري",
      backgroundColor: const Color(0xFF4A0E0E),
      roadColors: [const Color(0xFF4A0E0E), const Color(0xFF260505)],
      lineColor: Colors.redAccent.withOpacity(0.6),
      boundaryColor: Colors.red,
      trailColor: Colors.redAccent,
    ),
    GameTheme(
      label: "السرعة القصوى",
      backgroundColor: const Color(0xFF2E0942),
      roadColors: [const Color(0xFF2E0942), const Color(0xFF150421)],
      lineColor: Colors.purpleAccent.withOpacity(0.6),
      boundaryColor: Colors.purple,
      trailColor: Colors.purpleAccent,
    ),
    GameTheme(
      label: "الخطر المحدق",
      backgroundColor: const Color(0xFF0D3B1C),
      roadColors: [const Color(0xFF0D3B1C), const Color(0xFF051C0D)],
      lineColor: Colors.greenAccent.withOpacity(0.6),
      boundaryColor: Colors.green,
      trailColor: Colors.greenAccent,
    ),
    GameTheme(
      label: "المستوى الأسطوري",
      backgroundColor: const Color(0xFF000000),
      roadColors: [const Color(0xFF1A1A1A), const Color(0xFF000000)],
      lineColor: Colors.cyanAccent.withOpacity(0.8),
      boundaryColor: Colors.cyan,
      trailColor: Colors.cyanAccent,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _controller.addListener(_update);
    _speed = widget.initialSpeed * widget.speedMultiplier;
    
    // Pre-load audio source for low latency
    _audioPlayer.setSource(AssetSource('sounds/collect.mp3'));
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _update() {
    if (_isGameOver || !_gameStarted) return;

    setState(() {
      _gameTime += 0.016; 
      
      // Grace period: Speed stays at initialSpeed for the specified delay in seconds
      if (_gameTime < widget.accelerationDelay) {
        _speed = widget.initialSpeed * widget.speedMultiplier;
      } else {
        // Use the passed accelerationRate (per-frame delta) and convert to per-second
        double accelerationPerSecond = widget.accelerationRate * 60 * widget.speedMultiplier; 
        double timeSinceDelay = _gameTime - widget.accelerationDelay;
        double startSpeed = widget.initialSpeed * widget.speedMultiplier;
        double maxSpeedAdj = widget.maxSpeed * widget.speedMultiplier;
        _speed = (startSpeed + (timeSinceDelay * accelerationPerSecond)).clamp(startSpeed, maxSpeedAdj);
      }
      
      // Update Tier based on score (Progressive Tiers)
      int newTier = 0;
      if (_score >= 200) newTier = 3;      // Lowered from 500 for better visibility
      else if (_score >= 100) newTier = 2; // Lowered from 250
      else if (_score >= 40) newTier = 1;  // Lowered from 100

      if (newTier != _playerTier) {
        _playerTier = newTier;
      }

      // Update Theme based on score (Progressive 8 Themes)
      // Switch every multiple of themeScoreThreshold (مستقل عن عتبة الفوز)
      int themeThreshold = widget.themeScoreThreshold;
      int newThemeIndex = 0;
      if (_score >= themeThreshold * 50) newThemeIndex = 7;
      else if (_score >= themeThreshold * 25) newThemeIndex = 6;
      else if (_score >= themeThreshold * 12) newThemeIndex = 5;
      else if (_score >= themeThreshold * 6) newThemeIndex = 4;
      else if (_score >= themeThreshold * 3) newThemeIndex = 3;
      else if (_score >= themeThreshold * 2) newThemeIndex = 2;
      else if (_score >= themeThreshold * 1) newThemeIndex = 1;
      
      if (newThemeIndex != _currentThemeIndex) {
        _currentThemeIndex = newThemeIndex;
      }

      // وضع النار يُفعَّل بناءً على عتبة الثيم (مستقل عن عتبة الفوز)
      _isFieryMode = _score >= widget.themeScoreThreshold;

      // Update bullets
      for (var bullet in _bullets) {
        bullet.y -= 0.05;
      }
      _bullets.removeWhere((b) => b.y < -0.1 || b.isDestroyed);

      // Check bullet collisions with obstacles
      for (var bullet in _bullets) {
        for (var obj in _obstacles) {
          if (obj.isObstacle && !obj.isDestroyed) {
             if ((bullet.x - obj.x).abs() < 0.2 && (bullet.y - obj.y).abs() < 0.1) {
               bullet.isDestroyed = true;
               obj.isDestroyed = true;
               _score += 15; // Bonus for destroying
             }
          }
        }
      }

      // Move and spawn obstacles/items
      double frameSpeed = _speed / 100;
      for (var obj in _obstacles) {
        obj.y += frameSpeed;
      }
      for (var item in _items) {
        item.y += frameSpeed;
      }

      _obstacles.removeWhere((obj) => obj.y > 1.2 || obj.isDestroyed);
      _items.removeWhere((item) => item.y > 1.2 || item.isCollected);

      _spawnTimer += 0.016;
      double spawnInterval = (1.5 / (_speed / 3)).clamp(0.3, 1.5);
      
      if (_spawnTimer >= spawnInterval) {
        _createRandomObstacle();
        _spawnTimer = 0;
        
        // Randomly spawn gifts or ammo (Original mechanic slightly reduced if using 5s timer)
        if (math.Random().nextDouble() < 0.2) { 
           double spawnX = (math.Random().nextDouble() * 1.6) - 0.8;
           bool tooClose = _obstacles.any((obs) => obs.y < 0.3 && (obs.x - spawnX).abs() < 0.4);
           if (!tooClose) {
             _items.add(GameObject(
               x: spawnX,
               y: -0.1,
               type: (_playerTier == 3 && math.Random().nextDouble() < 0.4) 
                  ? GameObjectType.ammo 
                  : GameObjectType.gift,
             ));
           }
        }
      }

      // 5-Second Gift Spawn Mechanic
      _gift5sTimer += 0.016;
      if (_gift5sTimer >= 5.0) {
        _gift5sTimer = 0;
        final rand = math.Random();
        for (int i = 0; i < widget.giftsPer5Seconds; i++) {
          _items.add(GameObject(
            x: (rand.nextDouble() * 1.6) - 0.8,
            y: -0.1 - (rand.nextDouble() * 0.3), // staggered spawn
            type: GameObjectType.gift,
          ));
        }
      }

      _checkCollisions();
    });
  }

  void _createRandomObstacle() {
    final types = [GameObjectType.car, GameObjectType.truck, GameObjectType.van, GameObjectType.sportCar];
    final colors = [Colors.red, Colors.blue, Colors.orange, Colors.yellow, Colors.purple, Colors.green];
    
    _obstacles.add(GameObject(
      x: (math.Random().nextDouble() * 1.6) - 0.8,
      y: -0.1,
      type: types[math.Random().nextInt(types.length)],
      color: colors[math.Random().nextInt(colors.length)],
    ));
  }

  void _shoot() {
    if (_playerTier < 3 || _ammoCount <= 0 || _isGameOver) return;
    setState(() {
      _ammoCount--;
      _bullets.add(GameObject(
        x: _playerX,
        y: 0.8,
        type: GameObjectType.bullet,
      ));
    });
  }

  void _checkCollisions() {
    for (var obj in _items) {
      if (!obj.isCollected && (obj.x - _playerX).abs() < 0.15 && (obj.y - 0.80).abs() < 0.10) {
        obj.isCollected = true;
        
        // Play collect sound (optimized for low latency)
        _audioPlayer.seek(Duration.zero).then((_) => _audioPlayer.resume());

        if (obj.type == GameObjectType.gift) {
          _score += 10;
        } else if (obj.type == GameObjectType.ammo) {
          _ammoCount += 5;
        }
      }
    }

    for (var obj in _obstacles) {
      if (obj.isObstacle && !obj.isDestroyed) {
        // Hitbox size depends on tier/vehicle size slightly
        double hitX = _playerTier >= 2 ? 0.18 : 0.14; 
        if ((obj.x - _playerX).abs() < hitX && (obj.y - 0.80).abs() < 0.04) {
          _endGame();
          return;
        }
      }
    }
  }

  void _endGame() {
    _isGameOver = true;
    _controller.stop();
    widget.onGameOver(_score);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!_gameStarted) {
          setState(() => _gameStarted = true);
        } else {
          _shoot();
        }
      },
      onHorizontalDragUpdate: (details) {
        if (_isGameOver || !_gameStarted) return;
        setState(() {
          _playerX += details.delta.dx / (MediaQuery.of(context).size.width / 2);
          _playerX = _playerX.clamp(-0.8, 0.8);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        color: _themes[_currentThemeIndex].backgroundColor,
        child: Stack(
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: GamePainter(
                playerX: _playerX,
                obstacles: _obstacles,
                items: _items,
                bullets: _bullets,
                speed: _speed,
                playerTier: _playerTier,
                isFieryMode: _isFieryMode,
                isCompetitionMode: widget.isCompetitionMode,
                currentTheme: _themes[_currentThemeIndex],
                gameStarted: _gameStarted,
              ),
            ),
            // UI Overlay
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatTile(
                        widget.isCompetitionMode ? "نقاط المسابقة" : "النقاط", 
                        widget.isCompetitionMode ? "$_score 🏆" : "$_score", 
                        _getScoreColor()
                      ),
                      if (widget.minScoreForReward > 0)
                        _buildStatTile(
                          widget.isCompetitionMode ? "الهدف الذهبي" : "الهدف", 
                          "${widget.minScoreForReward}", 
                          Colors.amber
                        ),
                      if (_playerTier == 3)
                        _buildStatTile("الذخيرة", "$_ammoCount 🔫", Colors.greenAccent),
                      _buildStatTile("السرعة", "${(1 + (_speed - widget.initialSpeed) * 17).round()} كم/س", _getSpeedColor()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Theme Label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _themes[_currentThemeIndex].lineColor, width: 2),
                    ),
                    child: Text(
                      _themes[_currentThemeIndex].label,
                      style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tier Label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getTierLabelColor().withOpacity(0.8),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _getTierLabel(),
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),

                ],
              ),
            ),
            // Tutorial Overlay
            if (!_gameStarted && !_isGameOver)
              Container(
                color: Colors.black45,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amber, width: 2),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 60),
                            const SizedBox(height: 16),
                            Text(
                              widget.isCompetitionMode ? "🏆 وضع المسابقة نشط 🏆" : "اسحب يميناً ويساراً للتوجيه",
                              style: GoogleFonts.cairo(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            if (widget.isCompetitionMode) ...[
                              const SizedBox(height: 8),
                              Text(
                                "حطم الرقم القياسي لتتصدر القائمة!",
                                style: GoogleFonts.cairo(color: Colors.amberAccent, fontSize: 14),
                              ),
                            ],
                            Text(
                              "اضغط بيدك للبدء",
                              style: GoogleFonts.cairo(color: Colors.amberAccent, fontSize: 16),
                            ),
                            const SizedBox(height: 20),
                             Builder(
                               builder: (context) {
                                 double anim = (math.sin(DateTime.now().millisecondsSinceEpoch / 300).abs() * 15);
                                 return Row(
                                   mainAxisSize: MainAxisSize.min,
                                   children: [
                                     Transform.translate(offset: Offset(-anim, 0), child: const Icon(Icons.arrow_back, color: Colors.amber)),
                                     const SizedBox(width: 40),
                                     Transform.translate(offset: Offset(anim, 0), child: const Icon(Icons.arrow_forward, color: Colors.amber)),
                                   ],
                                 );
                               }
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
      ),
    );
  }

  Color _getScoreColor() {
    if (_playerTier == 3) return Colors.red;
    if (_playerTier == 2) return Colors.deepOrange;
    if (_playerTier == 1) return Colors.orangeAccent;
    return Colors.amber;
  }

  Color _getSpeedColor() {
    if (_playerTier == 3) return Colors.purpleAccent;
    return Colors.blue;
  }

  String _getTierLabel() {
    if (_playerTier == 3) return "⚡ وضع التدمير النهائي ⚡";
    if (_playerTier == 2) return "🔥 حمولة ثقيلة 🔥";
    if (_playerTier == 1) return "🏎️ سرعة التطور 🏎️";
    return "🛵 رحلة التوصيل السريع 🛵";
  }

  Color _getTierLabelColor() {
    if (_playerTier == 3) return Colors.purple;
    if (_playerTier == 2) return Colors.deepOrange;
    return Colors.red;
  }


  Widget _buildStatTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12)),
          Text(value, style: GoogleFonts.cairo(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }
}

class GamePainter extends CustomPainter {
  final double playerX;
  final List<GameObject> obstacles;
  final List<GameObject> items;
  final List<GameObject> bullets;
  final double speed;
  final int playerTier;
  final bool isFieryMode;
  final bool isCompetitionMode; // الجديد
  final GameTheme currentTheme;
  final bool gameStarted;

  GamePainter({
    required this.playerX,
    required this.obstacles,
    required this.items,
    required this.bullets,
    required this.speed,
    required this.playerTier,
    required this.isFieryMode,
    required this.isCompetitionMode, // الجديد
    required this.currentTheme,
    required this.gameStarted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawRoad(canvas, size);
    _drawLaneLines(canvas, size);
    _drawSideBoundaries(canvas, size);

    if (isFieryMode) {
      _drawTrail(canvas, size);
    }

    _drawPlayer(canvas, size);

    for (var obj in obstacles) {
      if (!obj.isDestroyed) {
        _drawVehicle(canvas, size, obj);
      }
    }

    for (var item in items) {
      if (!item.isCollected) {
        if (item.type == GameObjectType.gift) {
          _drawPremiumGift(canvas, size, item);
        } else if (item.type == GameObjectType.ammo) {
          _drawAmmo(canvas, size, item);
        }
      }
    }

    for (var bullet in bullets) {
      _drawBullet(canvas, size, bullet);
    }
  }

  void _drawRoad(Canvas canvas, Size size) {
    List<Color> colors = currentTheme.roadColors;
    if (isCompetitionMode) {
      // الوان المسابقة: برتقالي ذهبي غامق
      colors = [const Color(0xFF432C03), const Color(0xFF1A1A1A)];
    }

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawLaneLines(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = currentTheme.lineColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    double dashHeight = 40;
    double dashSpace = 30;
    double offset = (DateTime.now().millisecondsSinceEpoch * speed / 10) % (dashHeight + dashSpace);

    for (int i = 1; i < 3; i++) {
      double x = size.width * (i / 3);
      double currentY = -offset;
      while (currentY < size.height) {
        canvas.drawLine(Offset(x, currentY), Offset(x, currentY + dashHeight), paint);
        currentY += dashHeight + dashSpace;
      }
    }
  }

  void _drawSideBoundaries(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = currentTheme.boundaryColor
      ..strokeWidth = 8;

    canvas.drawLine(const Offset(5, 0), Offset(5, size.height), paint);
    canvas.drawLine(Offset(size.width - 5, 0), Offset(size.width - 5, size.height), paint);
  }


  void _drawPlayer(Canvas canvas, Size size) {
    double x = size.width / 2 + (playerX * size.width / 2.5);
    double y = size.height * 0.80;
 
    // الهالة الذهبية في وضع المسابقات
    if (isCompetitionMode) {
      final competitionGlow = Paint()
        ..color = Colors.amber.withOpacity(0.3 + (math.sin(DateTime.now().millisecondsSinceEpoch / 200).abs() * 0.2))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawCircle(Offset(x, y), 35, competitionGlow);
    }

    // Draw Fingerprint Icon Underneath (Only before game starts)
    if (!gameStarted) {
      _drawFingerprint(canvas, Offset(x, y + 25)); // Raised closer to the bike
      _drawFingerprintText(canvas, Offset(x, y + 55)); // Text right under icon
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: _getPlayerEmoji(),
        style: TextStyle(fontSize: _getPlayerSize()),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
  }

  String _getPlayerEmoji() {
    if (playerTier == 3) return "🎖️"; // Tank/Armored
    if (playerTier == 2) return "🚚"; // Truck
    if (playerTier == 1) return "🚗"; // Car
    return "🛵";
  }

  double _getPlayerSize() {
    if (playerTier == 3) return 70;
    if (playerTier == 2) return 60;
    if (playerTier == 1) return 50;
    return 45;
  }

  void _drawFingerprint(Canvas canvas, Offset center) {
    // Pulse effect
    double pulse = 0.8 + (math.sin(DateTime.now().millisecondsSinceEpoch / 400).abs() * 0.4);
    
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3 * pulse)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(pulse); // Scale the fingerprint
    canvas.rotate(math.pi / 6); // Slanted

    // Draw a simple fingerprint-like oval pattern
    for (int i = 0; i < 4; i++) {
       canvas.drawOval(
         Rect.fromCenter(center: Offset.zero, width: 20.0 + (i * 8), height: 35.0 + (i * 8)),
         paint,
       );
    }
    
    // Draw center lines
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1.5;
    
    canvas.drawLine(const Offset(-10, 0), const Offset(10, 0), linePaint);
    canvas.drawLine(const Offset(0, -15), const Offset(0, 15), linePaint);

    canvas.restore();
  }

  void _drawTrail(Canvas canvas, Size size) {
    double x = size.width / 2 + (playerX * size.width / 2.5);
    double y = size.height * 0.80; // Updated to match player

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          currentTheme.trailColor.withOpacity(0.6),
          currentTheme.trailColor.withOpacity(0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(x, y + 20), radius: 40));

    canvas.drawCircle(Offset(x, y + 20), 40, paint);
  }

  void _drawVehicle(Canvas canvas, Size size, GameObject obj) {
    double x = size.width / 2 + (obj.x * size.width / 2.5);
    double y = obj.y * size.height;

    String emoji = "🚗";
    if (obj.type == GameObjectType.truck) emoji = "🚚";
    if (obj.type == GameObjectType.van) emoji = "🚐";
    if (obj.type == GameObjectType.sportCar) emoji = "🏎️";

    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: 55, color: obj.color), // Enlarged
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
  }

  void _drawPremiumGift(Canvas canvas, Size size, GameObject item) {
    double x = size.width / 2 + (item.x * size.width / 2.5);
    double y = item.y * size.height;

    final glowPaint = Paint()
      ..color = Colors.amber.withOpacity(0.3 + (math.sin(DateTime.now().millisecondsSinceEpoch / 200).abs() * 0.4))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(Offset(x, y), 25, glowPaint);

    final textPainter = TextPainter(
      text: const TextSpan(text: "🎁", style: TextStyle(fontSize: 40)),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
  }

  void _drawAmmo(Canvas canvas, Size size, GameObject item) {
    double x = size.width / 2 + (item.x * size.width / 2.5);
    double y = item.y * size.height;

    final glowPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(Offset(x, y), 20, glowPaint);

    final textPainter = TextPainter(
      text: const TextSpan(text: "🔫", style: TextStyle(fontSize: 35)),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
  }

  void _drawBullet(Canvas canvas, Size size, GameObject bullet) {
    double x = size.width / 2 + (bullet.x * size.width / 2.5);
    double y = bullet.y * size.height;

    final paint = Paint()
      ..color = Colors.yellow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    
    canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 10, height: 20), paint);
    
    final corePaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 4, height: 12), corePaint);
  }

  void _drawFingerprintText(Canvas canvas, Offset position) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: "ضع اصبعك هنا 👆",
        style: GoogleFonts.cairo(
          color: Colors.amber.withOpacity(0.9),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.rtl,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(position.dx - textPainter.width / 2, position.dy));
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
