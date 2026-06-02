import 'dart:typed_data';

class PickedFile {
  final String name;
  final Uint8List bytes;
  final String mimeType;

  PickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
}

Future<PickedFile?> pickMediaFile() async {
  return null;
}
