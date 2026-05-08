import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/supabase_service.dart';
import 'single_game_launch_screen.dart';

class GameLaunchScreen extends StatefulWidget {
  final String? initialGameSlug;
  const GameLaunchScreen({super.key, this.initialGameSlug});

  @override
  State<GameLaunchScreen> createState() => _GameLaunchScreenState();
}

class _GameLaunchScreenState extends State<GameLaunchScreen> {
  final _supabaseService = SupabaseService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _games = [];

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    setState(() => _isLoading = true);
    final games = await _supabaseService.getActiveGames();
    if (mounted) {
      setState(() {
        _games = games;
        _isLoading = false;
      });

      // Auto-launch specific game if slug provided
      if (widget.initialGameSlug != null && widget.initialGameSlug!.isNotEmpty) {
        final targetGame = _games.firstWhere(
          (g) => g['slug'] == widget.initialGameSlug, 
          orElse: () => {},
        );
        if (targetGame.isNotEmpty && targetGame['is_active'] == true) {
          debugPrint("🚀 [Game] Auto-launching specific game: ${widget.initialGameSlug}");
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SingleGameLaunchScreen(gameData: targetGame),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("مجمع الألعاب", style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1.5, color: Colors.white)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)], // Deep premium space/tech gradient
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.amberAccent))
            : _games.isEmpty
                ? Center(
                    child: Text("لا توجد ألعاب متاحة حالياً", style: GoogleFonts.cairo(fontSize: 18, color: Colors.white70)),
                  )
                : SafeArea(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75, // Taller cards
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                      ),
                      itemCount: _games.length,
                      itemBuilder: (context, index) {
                        return _buildPremiumGameCard(context, _games[index]);
                      },
                    ),
                  ),
      ),
    );
  }


  Widget _buildPremiumGameCard(BuildContext context, Map<String, dynamic> game) {
    bool isSpace = game['slug'] == 'into-space';
    bool isActive = game['is_active'] == true;
    
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("هذه اللعبة غير متاحة حالياً، ترقبونا قريباً!", style: GoogleFonts.cairo())));
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SingleGameLaunchScreen(gameData: game),
          ),
        );
      },
      child: Opacity(
        opacity: isActive ? 1.0 : 0.6,
        child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
             begin: Alignment.topLeft,
             end: Alignment.bottomRight,
             colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
             ]
          ),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: isSpace ? Colors.blueAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
               // Background Glow
               Positioned(
                 right: -20,
                 top: -20,
                 child: Container(
                   width: 100,
                   height: 100,
                   decoration: BoxDecoration(
                     color: isSpace ? Colors.blue.withOpacity(0.4) : Colors.orange.withOpacity(0.4),
                     shape: BoxShape.circle,
                   ),
                 ),
               ),
               // Content
               Padding(
                 padding: const EdgeInsets.all(12.0),
                 child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                         color: Colors.black.withOpacity(0.2),
                         shape: BoxShape.circle,
                      ),
                      child: Text(
                        game['icon_emoji'] ?? "🎮",
                        style: const TextStyle(fontSize: 40),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Text(
                          game['name'] ?? "لعبة",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                         color: isActive ? Colors.white.withOpacity(0.1) : Colors.red.withOpacity(0.2),
                         borderRadius: BorderRadius.circular(20),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             Icon(isActive ? Icons.play_arrow_rounded : Icons.lock_clock_rounded, 
                                  color: isActive ? Colors.amberAccent : Colors.redAccent, size: 16),
                             const SizedBox(width: 4),
                             Text(isActive ? "إلعب الآن" : "قريباً", 
                                  style: GoogleFonts.cairo(color: isActive ? Colors.white : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                           ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                 ),
                 ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
