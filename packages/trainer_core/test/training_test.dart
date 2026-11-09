import 'package:test/test.dart';
import 'package:dartchess/dartchess.dart';
import 'package:trainer_core/trainer_core.dart';

ReviewEvent event(
  String id, {
  bool isNew = false,
  Rating rating = Rating.good,
  int hour = 12,
}) => ReviewEvent(
  id: '$id:$hour',
  decisionId: id,
  source: 's',
  chapter: 'c',
  at: DateTime.utc(2026, 11, 9, hour),
  day: '2026-11-09',
  wasNew: isNew,
  rating: rating,
);
void main() {
  test(
    'daily budget counts distinct items and permits repeated learning steps',
    () {
      final b = DailyBudget(
        [event('new', isNew: true), event('new'), event('old'), event('old')],
        newLimit: 1,
        reviewLimit: 1,
      );
      expect(b.newRemaining, 0);
      expect(b.reviewRemaining, 0);
      expect(b.allows('new', isNew: false), true);
      expect(b.allows('old', isNew: false), true);
      expect(b.allows('another', isNew: true), false);
      expect(b.allows('another', isNew: false), false);
      expect(
        DailyBudget([], newLimit: 1).allows('tomorrow', isNew: true),
        true,
      );
    },
  );
  test(
    'queue prioritizes due reviews, excludes suspended/future and honors slots',
    () {
      final decisions = importPgn(
        '[Event "A"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 *',
        's',
        Side.white,
      ).decisions;
      final now = DateTime.utc(2026, 11, 9, 12);
      final due = schedule(
        null,
        Rating.good,
        now.subtract(const Duration(days: 2)),
      ).state;
      final future = schedule(
        null,
        Rating.good,
        now.add(const Duration(days: 2)),
      ).state;
      final states = {
        decisions[0].id: due,
        decisions[1].id: future,
        decisions[2].id: ReviewState(due.card, suspended: true),
      };
      final q = trainingQueue(
        decisions: decisions,
        states: states,
        today: [],
        now: now,
        newLimit: 1,
        reviewLimit: 1,
      );
      expect(q.map((d) => d.id), [decisions[0].id, decisions[3].id]);
      expect(
        trainingQueue(
          decisions: decisions,
          states: states,
          today: [event(decisions[3].id, isNew: true)],
          now: now,
          newLimit: 1,
          reviewLimit: 0,
        ).map((d) => d.id),
        [decisions[3].id],
      );
    },
  );
  test('session serialization preserves penalties and stable review event identity', () {
    var s = TrainingSession(token: 'session', remaining: ['a', 'b']);
    s = s.record('a', const AttemptEvidence(hinted: true, mistakes: 2));
    s = s.record('a', const AttemptEvidence());
    final restored = TrainingSession.decode(s.encode());
    expect(restored.evidence('a').rating, Rating.again);
    expect(restored.evidence('a').mistakes, 2);
    expect(restored.eventId('a'), s.eventId('a'));
    expect(restored.advance().remaining, ['b']);
    expect(() => s.record('b', const AttemptEvidence()), throwsStateError);
    expect(TrainingSession.decode('["a"]').remaining, ['a']);
  });
  test('mistakes practice includes latest Again across earlier days, not later Good', () {
    final d = importPgn('1. e4 *', 's', Side.white).decisions.single;
    final old = event(d.id, rating: Rating.again, hour: 10),
        success = event(d.id, hour: 11);
    final args = [d];
    expect(
      trainingQueue(
        decisions: args,
        states: {},
        today: [],
        outcomes: [old],
        now: DateTime.utc(2026, 11, 10),
        mistakesOnly: true,
      ),
      [d],
    );
    expect(
      trainingQueue(
        decisions: args,
        states: {},
        today: [],
        outcomes: [old, success],
        now: DateTime.utc(2026, 11, 10),
        mistakesOnly: true,
      ),
      isEmpty,
    );
  });
  test('statistics and calendar dates are deterministic', () {
    final stats = ReviewStatistics([
      event('a', isNew: true),
      event('a', rating: Rating.again),
      event('b'),
    ]);
    expect(stats.completed, 3);
    expect(stats.accuracy, closeTo(2 / 3, .0001));
    expect(stats.byDay, {'2026-11-09': 3});
    expect(ReviewStatistics([]).accuracy, isNull);
    expect(reviewDay(DateTime(2026, 11, 9, 23, 59)), '2026-11-09');
    expect(reviewDay(DateTime(2026, 11, 10)), '2026-11-10');
  });
}
