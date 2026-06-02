import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

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
  final completer = Completer<PickedFile?>();

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*,video/*';

  input.addEventListener(
    'change',
    (web.Event event) {
      final files = input.files;
      if (files == null || files.length == 0) {
        completer.complete(null);
        return;
      }

      final file = files.item(0)!;
      final reader = web.FileReader();

      reader.onload = ((web.Event e) {
        final result = reader.result;
        if (result != null) {
          final arrayBuffer = result as JSArrayBuffer;
          final bytes = arrayBuffer.toDart.asUint8List();
          completer.complete(PickedFile(
            name: file.name,
            bytes: bytes,
            mimeType: file.type,
          ));
        } else {
          completer.complete(null);
        }
      }).toJS;

      reader.onerror = ((web.Event e) {
        completer.complete(null);
      }).toJS;

      reader.readAsArrayBuffer(file);
    }.toJS,
  );

  input.click();
  return completer.future;
}
