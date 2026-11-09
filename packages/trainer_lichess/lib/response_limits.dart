import 'dart:async';
import 'dart:typed_data';

/// Enforce a total deadline and cancel the response subscription on every exit.
Future<Uint8List> readResponseBytes(
  Stream<List<int>> stream,
  int maxBytes,
) async {
  final iterator = StreamIterator(stream);
  final bytes = BytesBuilder(copy: false);
  final elapsed = Stopwatch()..start();
  try {
    while (true) {
      final remaining = const Duration(seconds: 30) - elapsed.elapsed;
      if (remaining <= Duration.zero)
        throw TimeoutException('Download timed out');
      if (!await iterator.moveNext().timeout(remaining)) break;
      final chunk = iterator.current;
      if (chunk.length > maxBytes - bytes.length) {
        throw const FormatException('Response exceeds supported size');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    await iterator.cancel();
  }
}
