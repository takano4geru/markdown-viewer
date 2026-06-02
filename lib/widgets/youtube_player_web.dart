import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildYoutubePlayer(BuildContext context, String videoId, String videoUrl) {
  final viewType = 'youtube-player-$videoId';

  // Register the iframe view factory dynamically for the video ID
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) => web.HTMLIFrameElement()
      ..src = 'https://www.youtube.com/embed/$videoId'
      ..style.border = 'none'
      ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture'
      ..allowFullscreen = true,
  );

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x3394A3B8), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: HtmlElementView(viewType: viewType),
      ),
    ),
  );
}
