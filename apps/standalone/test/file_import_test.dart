import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_trainer/file_import.dart';
import 'package:study_trainer/main.dart';
import 'package:trainer_core/trainer_core.dart';

void main() {
  test(
    'file reader accepts exact byte boundary and decodes split UTF-8',
    () async {
      final bytes = utf8.encode('e4 é😀');
      expect(
        await readBoundedUtf8(
          Stream.fromIterable(bytes.map((b) => [b])),
          maxBytes: bytes.length,
        ),
        'e4 é😀',
      );
    },
  );
  test('file reader cancels when streamed size exceeds limit', () async {
    var cancelled = false;
    final input = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final result = readBoundedUtf8(input.stream, maxBytes: 5);
    final expectation = expectLater(
      result,
      throwsA(isA<InputLimitException>()),
    );
    input.add([1, 2, 3]);
    input.add([4, 5, 6]);
    await expectation;
    expect(cancelled, true);
    await input.close();
  });
  test(
    'raw decoder, filesystem and state errors cannot expose private text',
    () {
      for (final error in [
        FormatException('secret', 'private study'),
        StateError('private token'),
        Exception('/private/path'),
      ]) {
        expect(safeActionError(error), isNot(contains('private')));
        expect(safeActionError(error), isNot(contains('secret')));
      }
    },
  );
}
