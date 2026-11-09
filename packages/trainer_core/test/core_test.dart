import 'package:test/test.dart';
import 'package:dartchess/dartchess.dart';
import 'package:trainer_core/trainer_core.dart';

void main() {
  test('nested alternatives, both sides and refresh identities', () {
    final a = importPgn(
      '[Event "A"]\n\n1. e4 (1. d4 d5 (1... Nf6)) e5 2. Nf3 *',
      'local:a',
      Side.white,
    );
    expect(a.decisions.first.moves, containsAll(['e2e4', 'd2d4']));
    final b = importPgn(
      '[Event "A"]\n\n1. d4 (1. e4 e5 2. Nf3) d5 *',
      'local:a',
      Side.white,
    );
    expect(
      b.decisions.map((d) => d.id).toSet(),
      a.decisions.map((d) => d.id).toSet(),
    );
    expect(importPgn(a.pgn, 'a', Side.black).decisions.first.moves, isNotEmpty);
  });
  test('transpositions merge only within a chapter', () {
    final r = importPgn(
      '[Event "A"]\n\n1. Nf3 (1. g3 d5 2. Nf3 Nf6 3. Bg2) d5 2. g3 Nf6 3. Bg2 *',
      'a',
      Side.white,
    );
    expect(r.decisions.where((d) => d.moves.contains('f1g2')).length, 1);
  });
  test('illegal SAN and empty data rejected', () {
    expect(() => importPgn('1. e5 *', 'a', Side.white), throwsFormatException);
    expect(() => importPgn('', 'a', Side.white), throwsFormatException);
  });
  test('FEN starting positions and legal move validation', () {
    final r = importPgn(
      '[Event "end"]\n[FEN "8/8/8/8/8/4k3/8/4K3 w - - 0 1"]\n\n1. Kd1 *',
      'a',
      Side.white,
    );
    expect(r.decisions.single.accepts(Move.parse('e1d1')!), true);
  });
  test('published dart-fsrs 2.0.1 interval vector', () {
    ReviewState? s;
    var now = DateTime.utc(2022, 11, 29, 12, 30);
    final intervals = <int>[];
    for (final rating in [
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.again,
      Rating.again,
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.good,
      Rating.good,
    ]) {
      s = schedule(s, rating, now).state;
      intervals.add(s.card.due.difference(now).inDays);
      now = s.card.due;
    }
    expect(intervals, [0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40]);
  });
}
