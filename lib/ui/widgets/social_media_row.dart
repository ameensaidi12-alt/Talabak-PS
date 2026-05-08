import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

class SocialMediaRow extends StatelessWidget {
  final String? facebookUrl;
  final String? instagramUrl;
  final String? whatsappUrl;
  final Color? labelColor;
  final bool showLabel;

  const SocialMediaRow({
    super.key,
    this.facebookUrl,
    this.instagramUrl,
    this.whatsappUrl,
    this.labelColor,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(
            "تابعنا على",
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: labelColor ?? Colors.grey[600],
            ),
          ),
          const SizedBox(height: 15),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialIcon(
              context,
              FontAwesomeIcons.whatsapp,
              const Color(0xFF25D366),
              whatsappUrl,
            ),
            const SizedBox(width: 25),
            _buildSocialIcon(
              context,
              FontAwesomeIcons.instagram,
              const Color(0xFFE4405F),
              instagramUrl,
            ),
            const SizedBox(width: 25),
            _buildSocialIcon(
              context,
              FontAwesomeIcons.facebook,
              const Color(0xFF1877F2),
              facebookUrl,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialIcon(BuildContext context, IconData icon, Color color, String? url) {
    return InkWell(
      onTap: () => _launchURL(context, url),
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.1), width: 1),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }

  Future<void> _launchURL(BuildContext context, String? urlString) async {
    if (urlString == null || urlString.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("هذا الرابط غير متوفر حالياً", textAlign: TextAlign.center),
          backgroundColor: Colors.black87,
        ),
      );
      return;
    }

    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تعذر فتح الرابط")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error launching URL: $e");
    }
  }
}
