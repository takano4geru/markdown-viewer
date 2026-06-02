import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildYoutubePlayer(BuildContext context, String videoId, String videoUrl) {
  final thumbnailUrl = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  
  return Align(
    alignment: Alignment.center,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      constraints: const BoxConstraints(maxWidth: 640),
      decoration: BoxDecoration(
        color: const Color(0x1F334155),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x3394A3B8), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail Image
              Image.network(
                thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFF0F172A),
                  child: const Center(
                    child: Icon(Icons.video_library_outlined, size: 48, color: Color(0xFF475569)),
                  ),
                ),
              ),
              // Glassmorphic Tint & Gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black54, Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              // Play Button Overlay
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      final uri = Uri.parse(videoUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 2),
                      ),
                      child: const Icon(
                        Icons.play_circle_filled,
                        size: 64,
                        color: Color(0xFFEF4444), // YouTube Red
                      ),
                    ),
                  ),
                ),
              ),
              // YouTube Branding Badge
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow, size: 10, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'YouTube',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
    ),
  );
}
