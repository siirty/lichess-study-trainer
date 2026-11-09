import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:trainer_core/trainer_core.dart';

/// A reported size is only a fast rejection; the stream limit is authoritative.
Future<String> readImportFile(
  PlatformFile file, {
  required int maxBytes,
}) async {
  final reported = file.lengthSync();
  if (reported != null && reported > maxBytes) {
    throw const InputLimitException('File exceeds the supported size limit.');
  }
  return readBoundedUtf8(file.readAsByteStream(), maxBytes: maxBytes);
}

Future<String> readBoundedUtf8(
  Stream<List<int>> input, {
  required int maxBytes,
}) async {
  final bytes = BytesBuilder(copy: false);
  final iterator = StreamIterator(input);
  final deadline = Stopwatch()..start();
  try {
    while (true) {
      final remaining = const Duration(seconds: 30) - deadline.elapsed;
      if (remaining <= Duration.zero)
        throw TimeoutException('File read timed out');
      if (!await iterator.moveNext().timeout(remaining)) break;
      final chunk = iterator.current;
      if (chunk.length > maxBytes - bytes.length) {
        throw const InputLimitException(
          'File exceeds the supported size limit.',
        );
      }
      bytes.add(chunk);
    }
  } finally {
    await iterator.cancel();
  }
  return utf8.decode(bytes.takeBytes());
}
