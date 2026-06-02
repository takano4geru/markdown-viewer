import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import '../providers/drive_provider.dart';
import 'video_player.dart';

class WebVideoSyntax extends md.InlineSyntax {
  // Matches: @[video](URL)
  WebVideoSyntax() : super(r'@\[video\]\((.*?)\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final url = match.group(1);
    final element = md.Element.empty('video');
    element.attributes['url'] = url ?? '';
    element.attributes['isDrive'] = 'false';
    parser.addNode(element);
    return true;
  }
}

class DriveVideoSyntax extends md.InlineSyntax {
  // Matches: @[drive_video](drive://FILE_ID) or @[drive_video](FILE_ID)
  DriveVideoSyntax() : super(r'@\[drive_video\]\((.*?)\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final url = match.group(1);
    final element = md.Element.empty('video');
    element.attributes['url'] = url ?? '';
    element.attributes['isDrive'] = 'true';
    parser.addNode(element);
    return true;
  }
}

class VideoElementBuilder extends MarkdownElementBuilder {
  final WidgetRef ref;
  VideoElementBuilder(this.ref);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final url = element.attributes['url'] ?? '';
    final isDrive = element.attributes['isDrive'] == 'true';

    if (url.isEmpty) return const SizedBox.shrink();

    if (isDrive) {
      final fileId = url.replaceAll('drive://', '');
      return DriveVideoWidget(fileId: fileId);
    } else {
      return Builder(
        builder: (context) => buildVideoPlayer(context, url, false, null, null),
      );
    }
  }
}

class DriveImageBuilder extends MarkdownElementBuilder {
  final WidgetRef ref;
  DriveImageBuilder(this.ref);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';

    if (src.startsWith('drive://')) {
      final fileId = src.replaceAll('drive://', '');
      return DriveImageWidget(fileId: fileId, alt: alt);
    }

    // Standard web image
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x3394A3B8), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.network(
            src,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Failed to load image',
                      style: GoogleFonts.inter(color: Colors.redAccent),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class DriveVideoWidget extends ConsumerStatefulWidget {
  final String fileId;
  const DriveVideoWidget({super.key, required this.fileId});

  @override
  ConsumerState<DriveVideoWidget> createState() => _DriveVideoWidgetState();
}

class _DriveVideoWidgetState extends ConsumerState<DriveVideoWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(driveProvider.notifier).downloadMedia(widget.fileId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final driveState = ref.watch(driveProvider);
    final bytes = driveState.mediaCache[widget.fileId];

    if (bytes == null) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          constraints: const BoxConstraints(maxWidth: 640),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x3394A3B8)),
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Downloading video...',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return buildVideoPlayer(context, 'drive://${widget.fileId}', true, bytes, widget.fileId);
  }
}

class DriveImageWidget extends ConsumerStatefulWidget {
  final String fileId;
  final String alt;
  const DriveImageWidget({super.key, required this.fileId, required this.alt});

  @override
  ConsumerState<DriveImageWidget> createState() => _DriveImageWidgetState();
}

class _DriveImageWidgetState extends ConsumerState<DriveImageWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(driveProvider.notifier).downloadMedia(widget.fileId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final driveState = ref.watch(driveProvider);
    final bytes = driveState.mediaCache[widget.fileId];

    if (bytes == null) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0x1F334155),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x2294A3B8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Loading image: ${widget.alt}...',
                style: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x3394A3B8), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Failed to render image',
                      style: GoogleFonts.inter(color: Colors.redAccent),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
