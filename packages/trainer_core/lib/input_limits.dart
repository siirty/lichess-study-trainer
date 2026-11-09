/// Limits apply before parsers or database replacement handle untrusted input.
const maxPgnBytes = 5000000;
const maxBackupBytes = 25000000;
const maxBackupRows = 100000;
const maxPgnPositions = 50000;
const maxPgnChapters = 1000;
const maxPgnVariationDepth = 64;
const maxJsonDepth = 64;

class InputLimitException implements Exception {
  const InputLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Count UTF-8 bytes without allocating another copy of a potentially large file.
void checkTextBytes(String text, int limit) {
  if (text.length > limit) {
    throw const InputLimitException('File exceeds the supported size limit.');
  }
  var bytes = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c < 0x80) {
      bytes++;
    } else if (c < 0x800) {
      bytes += 2;
    } else if (c >= 0xd800 &&
        c <= 0xdbff &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) >= 0xdc00 &&
        text.codeUnitAt(i + 1) <= 0xdfff) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
    if (bytes > limit) {
      throw const InputLimitException('File exceeds the supported size limit.');
    }
  }
}

/// Reject deep JSON before jsonDecode (including nested JSON stored in rows).
/// Syntax/type validation remains the responsibility of the JSON/domain parser.
void checkJsonInput(String text, {int maxBytes = maxBackupBytes}) {
  checkTextBytes(text, maxBytes);
  var depth = 0, quoted = false, escaped = false;
  for (final c in text.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (c == 92) {
        escaped = true;
      } else if (c == 34) {
        quoted = false;
      }
    } else if (c == 34) {
      quoted = true;
    } else if (c == 123 || c == 91) {
      if (++depth > maxJsonDepth) {
        throw const InputLimitException(
          'File nesting exceeds the supported limit.',
        );
      }
    } else if (c == 125 || c == 93) {
      if (--depth < 0) throw const FormatException('Invalid JSON nesting');
    }
  }
}
