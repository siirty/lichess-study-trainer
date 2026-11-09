import 'package:test/test.dart';
import 'package:trainer_core/trainer_core.dart';

void main() {
  test('size limit counts UTF-8 bytes including surrogate pairs', () {
    checkTextBytes('é😀', 6);
    expect(() => checkTextBytes('é😀', 5), throwsA(isA<InputLimitException>()));
  });
  test('JSON depth guard ignores brackets and escaped quotes in strings', () {
    checkJsonInput('{"text":"[\\\"{]"}');
    checkJsonInput('${'[' * maxJsonDepth}0${']' * maxJsonDepth}');
    expect(
      () => checkJsonInput(
        '${'[' * (maxJsonDepth + 1)}0${']' * (maxJsonDepth + 1)}',
      ),
      throwsA(isA<InputLimitException>()),
    );
  });
  test(
    'PGN rejects deep variations and excessive move text before parsing',
    () {
      expect(
        () => importPgn('1. e4 ${'(' * 65}${')' * 65} *', 'local'),
        throwsA(isA<InputLimitException>()),
      );
      expect(
        () => importPgn('e4 ' * 400000, 'local'),
        throwsA(isA<InputLimitException>()),
      );
    },
  );
  test('restored schedules reject invalid stability, difficulty and steps', () {
    final baseline = schedule(
      null,
      Rating.good,
      DateTime.utc(2026),
    ).state.toJson();
    for (final entry in <String, Object>{
      'stability': -1.0,
      'difficulty': 11.0,
      'step': -1,
    }.entries) {
      final json = {
        ...baseline,
        'card': {
          ...baseline['card'] as Map<String, dynamic>,
          entry.key: entry.value,
        },
      };
      expect(() => ReviewState.fromJson(json), throwsFormatException);
    }
    expect(
      () => schedule(
        null,
        Rating.good,
        DateTime.utc(2026),
        retention: double.nan,
      ),
      throwsArgumentError,
    );
  });
  test('long blank-line runs parse without regex backtracking', () {
    final result = importPgn('${'\n' * 200000}1. e4 *', 'local');
    expect(result.decisions.length, 1);
  }, timeout: const Timeout(Duration(seconds: 5)));
  test('PGN chapter budget applies to the whole import', () {
    final pgn = List.generate(
      maxPgnChapters + 1,
      (i) => '[Event "$i"]\n\n1. e4 *',
    ).join('\n\n');
    expect(() => importPgn(pgn, 'local'), throwsA(isA<InputLimitException>()));
  });
}
