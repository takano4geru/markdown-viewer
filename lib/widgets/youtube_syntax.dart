import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'youtube_player.dart';

class YoutubeSyntax extends md.InlineSyntax {
  // Pattern matches: @[youtube](URL or ID)
  YoutubeSyntax() : super(r'@\[youtube\]\((.*?)\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final urlOrId = match.group(1);
    final element = md.Element.empty('youtube');
    element.attributes['url'] = urlOrId ?? '';
    parser.addNode(element);
    return true;
  }
}

class YoutubeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final urlOrId = element.attributes['url'] ?? '';
    if (urlOrId.isEmpty) return const SizedBox.shrink();

    String videoId = urlOrId;
    String videoUrl = urlOrId;

    // Check if the input is a URL or a direct 11-character ID
    if (urlOrId.contains('/') || urlOrId.contains('?')) {
      final id = _extractYoutubeId(urlOrId);
      if (id != null) {
        videoId = id;
      } else {
        return Text(
          'Invalid YouTube Link: $urlOrId',
          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        );
      }
    } else {
      videoUrl = 'https://www.youtube.com/watch?v=$videoId';
    }

    return Builder(
      builder: (context) => buildYoutubePlayer(context, videoId, videoUrl),
    );
  }

  String? _extractYoutubeId(String url) {
    final regExp = RegExp(
      r'^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 2) {
      final id = match.group(2);
      if (id != null && id.length == 11) {
        return id;
      }
    }
    return null;
  }
}
