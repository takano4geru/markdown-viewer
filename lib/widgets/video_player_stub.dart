import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildVideoPlayer(BuildContext context, String url, bool isDriveFile, Uint8List? driveBytes, String? fileId) {
  final displayUrl = isDriveFile ? 'https://drive.google.com/file/d/$fileId/view' : url;
  
  return Align(
    alignment: Alignment.center,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      constraints: const BoxConstraints(maxWidth: 640),
      decoration: BoxDecoration(
        color: const Color(0x1F334155),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x3394A3B8), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFF0F172A),
                child: const Center(
                  child: Icon(Icons.video_library_outlined, size: 48, color: Color(0xFF475569)),
                ),
              ),
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      final uri = Uri.parse(displayUrl);
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
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Text(
                  isDriveFile ? 'Play Google Drive Video' : 'Play Web Video',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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
