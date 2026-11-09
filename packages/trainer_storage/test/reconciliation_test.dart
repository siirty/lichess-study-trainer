import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:dartchess/dartchess.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_storage/trainer_storage.dart';

const study = '[Site "https://lichess.org/study/abcd1234/efgh5678"]\n';
const original = '$study[Event "Original"]\n\n1. e4 (1. d4 d5) e5 2. Nf3 *';
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteTrainerStore store;
  final now = DateTime.utc(2026, 11, 9);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('source-refresh');
    store = await SqliteTrainerStore.open(
      databaseFactoryFfi,
      '${dir.path}/db',
      clock: () => now,
    );
  });
  tearDown(() async {
    await store.db.close();
    await dir.delete(recursive: true);
  });
  Future<ReviewState> learn(Decision d, String event) async {
    final result = schedule(
      (await store.states())[d.id],
      Rating.good,
      DateTime.utc(2026, 1, 1),
      decision: d,
    );
    await store.review(event, d.id, result);
    return result.state;
  }

  test(
    'legacy side-scoped import retains both colors, refresh/rename/reorder preserve schedules exactly',
    () async {
      await store.replaceSource('s', importPgn(original, 's', Side.white));
      final before = await store.decisions();
      expect(before.any((d) => d.side == Side.black), true);
      final w = before.firstWhere((d) => d.moves.contains('e2e4'));
      final b = before.firstWhere((d) => d.moves.contains('e7e5'));
      final ws = await learn(w, 'w'), bs = await learn(b, 'b');
      const changed =
          '$study[Event "Renamed"]\n\n1. d4 d5 (1... Nf6) (1... e5) (1... c5) (1... e6) (1... d6) (1... g6) *';
      // A pure reorder/rename with the same branches does not alter either schedule.
      const renamed = '$study[Event "Renamed"]\n\n1. d4 (1. e4 e5 2. Nf3) d5 *';
      await store.replaceSource('s', importPgn(renamed, 's'));
      expect((await store.states())[w.id]!.toJson(), ws.toJson());
      expect((await store.states())[b.id]!.toJson(), bs.toJson());
      expect(
        (await store.decisions()).every((d) => d.title == 'Renamed'),
        true,
      );
      expect((await store.source('s'))!.pgn, renamed);
      expect((await store.sources()).single.importedAt, now);
      final backup = await store.backup();
      await expectLater(
        store.replaceSource(
          's',
          ImportResult([
            Decision(
              id: 'bad',
              source: 's',
              chapter: 'c',
              title: 'Broken',
              fen: w.fen,
              moves: {'e2e5'},
            ),
          ], original),
        ),
        throwsFormatException,
      );
      expect(await store.backup(), backup);
      await store.replaceSource('s', importPgn(changed, 's'));
      expect((await store.states())[b.id]!.suspended, true);
    },
  );
  test(
    'changed answers become due; removals suspend; reintroduction preserves history',
    () async {
      await store.replaceSource('s', importPgn(original, 's'));
      final before = await store.decisions();
      final root = before.firstWhere((d) => d.moves.contains('e2e4'));
      final reply = before.firstWhere((d) => d.moves.contains('e7e5'));
      final state = await learn(root, 'root');
      await learn(reply, 'reply');
      const changed = '$study[Event "Renamed"]\n\n1. d4 d5 *';
      await store.replaceSource('s', importPgn(changed, 's'));
      final updated = (await store.states())[root.id]!;
      expect(updated.card.lastReview, state.card.lastReview);
      expect(updated.card.stability, state.card.stability);
      expect(updated.card.due, now);
      expect((await store.states())[reply.id]!.suspended, true);
      expect((await store.history()).length, 2);
      // A different chapter has the same chess position but never inherits history.
      const other =
          '[Site "https://lichess.org/study/abcd1234/ijkl9012"]\n[Event "Other"]\n\n1. d4 d5 *';
      await store.replaceSource('s', importPgn(other, 's'));
      expect((await store.states())[root.id]!.suspended, true);
      final persisted = await store.states();
      expect(
        (await store.decisions()).every((d) => !persisted.containsKey(d.id)),
        true,
      );
      await store.replaceSource('s', importPgn(original, 's'));
      expect((await store.states())[reply.id]!.suspended, false);
      expect((await store.history()).length, 2);
    },
  );
  test(
    'refresh invalidates stale session and source revision without losing penalties',
    () async {
      await store.replaceSource('s', importPgn(original, 's'));
      final root = (await store.decisions()).firstWhere(
        (d) => d.moves.contains('e2e4'),
      );
      var session = TrainingSession(token: 'before', remaining: [root.id]);
      await store.setSetting('session', session.encode());
      session = await store.recordAttempt(
        session.token,
        root.id,
        const AttemptEvidence(hinted: true),
      );
      final oldReview = schedule(null, Rating.again, now, decision: root);
      await store.replaceSource(
        's',
        importPgn('$study[Event "Changed"]\n\n1. d4 d5 *', 's'),
      );
      final repaired = TrainingSession.decode(
        (await store.setting('session'))!,
      );
      expect(repaired.token, isNot(session.token));
      expect(repaired.evidence(root.id).hinted, true);
      final snapshot = await store.backup();
      await expectLater(
        store.recordAttempt(session.token, root.id, const AttemptEvidence()),
        throwsStateError,
      );
      await expectLater(
        store.review(
          session.eventId(root.id),
          root.id,
          ScheduledReview(
            oldReview.state,
            oldReview.log,
            decisionRevision: oldReview.decisionRevision,
            session: session.advance().encode(),
          ),
        ),
        throwsStateError,
      );
      expect(await store.backup(), snapshot);
    },
  );
  test(
    'v3 migration normalizes both sides and metadata without losing review state',
    () async {
      await store.replaceSource('s', importPgn(original, 's'));
      final root = (await store.decisions()).firstWhere(
        (d) => d.moves.contains('e2e4'),
      );
      final state = await learn(root, 'review');
      // Construct the exact v3 source/cache shape: no imported timestamp, one side,
      // and legacy decision JSON without annotations/replies.
      for (final d in await store.decisions()) {
        if (d.side == Side.black) {
          await store.db.delete(
            'decisions',
            where: 'id = ?',
            whereArgs: [d.id],
          );
          continue;
        }
        final j = d.toJson()
          ..remove('annotations')
          ..remove('glyphs')
          ..remove('replies')
          ..remove('contextComments');
        await store.db.update(
          'decisions',
          {'data': jsonEncode(j)},
          where: 'id = ?',
          whereArgs: [d.id],
        );
      }
      await store.db.execute('ALTER TABLE sources DROP COLUMN imported_at');
      await store.db.execute('DROP INDEX decisions_source');
      await store.db.setVersion(3);
      await store.db.close();
      store = await SqliteTrainerStore.open(
        databaseFactoryFfi,
        '${dir.path}/db',
      );
      expect(await store.db.getVersion(), 4);
      expect((await store.decisions()).any((d) => d.side == Side.black), true);
      expect((await store.states())[root.id]!.toJson(), state.toJson());
      expect((await store.history()).single.id, 'review');
      expect((await store.sources()).single.importedAt, isNotNull);
      final restored = await store.backup();
      await store.restore(restored);
      expect(await store.backup(), restored);
    },
  );
  test(
    'refresh repairs only its source inside a paused multi-study queue',
    () async {
      await store.replaceSource('s', importPgn(original, 's'));
      await store.replaceSource('other', importPgn('1. d4 d5 *', 'other'));
      final all = await store.decisions();
      final a = all.firstWhere(
            (d) => d.source == 's' && d.moves.contains('e2e4'),
          ),
          b = all.firstWhere(
            (d) => d.source == 'other' && d.side == Side.white,
          );
      var session = TrainingSession(token: 'mixed', remaining: [b.id, a.id]);
      await store.setSetting('session', session.encode());
      session = await store.recordAttempt(
        session.token,
        b.id,
        const AttemptEvidence(hinted: true),
      );
      await store.replaceSource('s', importPgn(original, 's'));
      expect((await store.setting('session')), session.encode());
      await store.replaceSource(
        's',
        importPgn('$study[Event "Changed"]\n\n1. d4 d5 *', 's'),
      );
      final changed = TrainingSession.decode((await store.setting('session'))!);
      expect(changed.remaining, [b.id, a.id]);
      expect(changed.evidence(b.id).hinted, true);
      expect(changed.token, isNot(session.token));
      expect((await store.source('other'))!.pgn, '1. d4 d5 *');
    },
  );
}
