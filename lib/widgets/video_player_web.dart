import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildVideoPlayer(BuildContext context, String url, bool isDriveFile, Uint8List? driveBytes, String? fileId) {
  final viewType = isDriveFile ? 'drive-video-player-$fileId' : 'web-video-player-${url.hashCode}';

  // Register the video view factory dynamically
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final videoElement = web.HTMLVideoElement()
        ..controls = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none';

      if (isDriveFile) {
        if (driveBytes != null && driveBytes.isNotEmpty) {
          // Convert bytes to a Blob and create a temporary Object URL
          final parts = [driveBytes.toJS].toJS;
          final blob = web.Blob(parts, web.BlobPropertyBag(type: 'video/mp4'));
          final objectUrl = web.URL.createObjectURL(blob);
          videoElement.src = objectUrl;
        }
      } else {
        videoElement.src = url;
      }

      return videoElement;
    },
  );

  return Align(
    alignment: Alignment.center,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      constraints: const BoxConstraints(maxWidth: 640),
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
    ),
  );
}
