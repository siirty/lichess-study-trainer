import 'package:test/test.dart';
import 'package:dartchess/dartchess.dart';
import 'package:trainer_core/trainer_core.dart';

void main() {
  test('one parse retains both sides, comments, glyphs and legal opponent replies with stable IDs', () {
    const text =
        '[Event "Repertoire"]\n\n{Chapter context} 1. e4! {Control the center} (1. d4 {Another answer} d5) e5 {Reply context} 2. Nf3 *';
    final imported = importPgn(text, 's');
    expect(imported.complete, true);
    expect(imported.decisions.map((d) => d.side).toSet(), Side.values.toSet());
    final white = imported.decisions.firstWhere(
      (d) => d.moves.contains('e2e4'),
    );
    expect(white.annotations['e2e4'], contains('Control the center'));
    expect(white.contextComments, contains('Chapter context'));
    expect(white.glyphs['e2e4'], contains(1));
    expect(white.replies['e2e4'], {'e7e5'});
    expect(white.replies['d2d4'], {'d7d5'});
    expect(Decision.fromJson(white.toJson()).toJson(), white.toJson());
    for (final side in Side.values) {
      final scoped = importPgn(text, 's', side);
      expect(scoped.complete, false);
      expect(
        scoped.decisions.map((d) => d.id).toSet(),
        imported.decisions
            .where((d) => d.side == side)
            .map((d) => d.id)
            .toSet(),
      );
    }
  });
  test('revision ignores title, annotations and move ordering but changes with accepted answers', () {
    const site = '[Site "https://lichess.org/study/abcd1234/efgh5678"]\n';
    final a = importPgn(
      '$site[Event "Old"]\n\n1. e4 (1. d4) *',
      's',
    ).decisions.single;
    final b = importPgn(
      '$site[Event "New"]\n\n1. d4 {Note} (1. e4!) *',
      's',
    ).decisions.single;
    final c = importPgn('$site[Event "New"]\n\n1. e4 *', 's').decisions.single;
    expect(a.id, b.id);
    expect(a.revision, b.revision);
    expect(c.id, a.id);
    expect(c.revision, isNot(a.revision));
  });
  test(
    'queue side selection isolates reviews without duplicating source content',
    () {
      final imported = importPgn('1. e4 e5 2. Nf3 Nc6 *', 's');
      for (final side in Side.values) {
        final queue = trainingQueue(
          decisions: imported.decisions,
          states: {},
          today: [],
          now: DateTime.utc(2026),
          side: side,
        );
        expect(queue, hasLength(2));
        expect(queue.every((d) => d.side == side), true);
      }
    },
  );
  test('truncated PGN is rejected while delimiters in comments and headers remain harmless', () {
    for (final input in [
      '1. e4 (1. d4',
      '1. e4 {unfinished',
      '[Event "unfinished',
      '1. e4 ) *',
    ]) {
      expect(() => importPgn(input, 's'), throwsFormatException);
    }
    final valid = importPgn(
      '[Event "(Example) \\"quoted\\" title"]\n\n% ignored (escape line\n1. e4 {Text (including brackets [here])\n% comment text, not an escape line } e5 ; ignored (comment\n2. Nf3 *',
      's',
    );
    expect(valid.decisions.length, 3);
  });
}
