import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/models.dart';
import 'package:intl/intl.dart';

class StarPointsHistoryScreen extends StatefulWidget {
  const StarPointsHistoryScreen({super.key});

  @override
  State<StarPointsHistoryScreen> createState() => _StarPointsHistoryScreenState();
}

class _StarPointsHistoryScreenState extends State<StarPointsHistoryScreen> {
  final _supabaseService = SupabaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "سجل النجوم",
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<List<StarPointsTransaction>>(
        future: _supabaseService.getStarPointsHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "خطأ في تحميل البيانات",
                style: GoogleFonts.cairo(color: Colors.red),
              ),
            );
          }

          final transactions = snapshot.data ?? [];

          if (transactions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 80, color: Colors.grey[200]),
                  const SizedBox(height: 16),
                  Text(
                    "لا يوجد سجل مكافآت بعد",
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final isPositive = tx.amount > 0;
              final isGameReward = tx.description?.contains("اللعبة") ?? false;
              
              return Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isGameReward ? Colors.blue[50]?.withOpacity(0.5) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isGameReward ? Colors.blue[100]! : Colors.grey[100]!,
                    width: isGameReward ? 1.5 : 1,
                  ),
                  boxShadow: isGameReward ? [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ] : null,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isGameReward 
                             ? Colors.blue 
                             : (isPositive ? Colors.green : Colors.red)).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isGameReward 
                            ? Icons.videogame_asset_rounded 
                            : (isPositive ? Icons.add_rounded : Icons.remove_rounded),
                        color: isGameReward 
                             ? Colors.blue[700] 
                             : (isPositive ? Colors.green : Colors.red),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            tx.description ?? (isPositive ? "ربح نقاط" : "استبدال نقاط"),
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('yyyy/MM/dd HH:mm').format(tx.createdAt),
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "${isPositive ? '+' : '-'}${tx.amount.abs()}",
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: isPositive ? Colors.green[700] : Colors.red[700],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
