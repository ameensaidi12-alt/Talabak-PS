import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnimatedDiscountBadge extends StatefulWidget {
  final double originalPrice;
  final double salePrice;
  final Color primaryColor;
  final double salePriceFontSize;
  final double originalPriceFontSize;

  const AnimatedDiscountBadge({
    Key? key,
    required this.originalPrice,
    required this.salePrice,
    required this.primaryColor,
    this.salePriceFontSize = 14,
    this.originalPriceFontSize = 11,
  }) : super(key: key);

  @override
  State<AnimatedDiscountBadge> createState() => _AnimatedDiscountBadgeState();
}

class _AnimatedDiscountBadgeState extends State<AnimatedDiscountBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.salePrice >= widget.originalPrice) return const SizedBox.shrink();

    final discountPercent =
        (((widget.originalPrice - widget.salePrice) / widget.originalPrice) * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // السعر الأصلي مع خط وكلمة خصم متحركة
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withOpacity(0.5), width: 0.5),
                ),
                child: Text(
                  'خصم $discountPercent%',
                  style: GoogleFonts.cairo(
                    color: Colors.red,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  "${widget.originalPrice} ₪",
                  style: GoogleFonts.cairo(
                    color: Colors.grey[500],
                    fontSize: widget.originalPriceFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // خط أحمر احترافي لافت للنظر يقطع السعر
                Positioned(
                  child: Transform.rotate(
                    angle: -0.1,
                    child: Container(
                      height: 1.5,
                      width: 25,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        // السعر الجديد الفخم
        Text(
          "${widget.salePrice} ₪",
          style: GoogleFonts.cairo(
            color: widget.primaryColor,
            fontWeight: FontWeight.w900,
            fontSize: widget.salePriceFontSize,
            shadows: [
              Shadow(
                color: widget.primaryColor.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
