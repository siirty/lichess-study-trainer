import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:dartchess/dartchess.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_storage/trainer_storage.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteTrainerStore store;
  late List<Decision> decisions;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('durable-training');
    store = await SqliteTrainerStore.open(databaseFactoryFfi, '${dir.path}/db');
    final imported = importPgn('1. e4 e5 2. Nf3 Nc6 3. Bb5 *', 's', Side.white);
    await store.replaceSource('s', imported);
    decisions = imported.decisions;
  });
  tearDown(() async {
    await store.db.close();
    await dir.delete(recursive: true);
  });
  Future<void> commit(
    String eventId,
    String id,
    DateTime at, {
    String? cursor,
    Rating rating = Rating.good,
  }) async {
    final old = (await store.states())[id];
    final result = schedule(
      old,
      rating,
      at,
      decision: decisions.firstWhere((d) => d.id == id),
    );
    await store.review(
      eventId,
      id,
      ScheduledReview(
        result.state,
        result.log,
        session: cursor,
        previousReview: result.previousReview,
        decisionRevision: result.decisionRevision,
      ),
    );
  }

  test(
    'daily limit survives new sessions, reopen, backup and resets on next calendar day',
    () async {
      await store.setSetting('newLimit', '1');
      await store.setSetting('reviewLimit', '0');
      final at = DateTime(2026, 11, 9, 23, 58);
      await commit('first', decisions[0].id, at);
      await expectLater(
        commit('second', decisions[1].id, at),
        throwsA(isA<DailyLimitException>()),
      );
      expect((await store.history()).length, 1);
      expect((await store.states()).length, 1);
      final backup = await store.backup();
      await store.db.close();
      store = await SqliteTrainerStore.open(
        databaseFactoryFfi,
        '${dir.path}/db',
      );
      await store.restore(backup);
      await expectLater(
        commit('third', decisions[1].id, at),
        throwsA(isA<DailyLimitException>()),
      );
      // Learning today's introduced item costs no review slot, despite zero review budget.
      await commit(
        'repeat',
        decisions[0].id,
        at.add(const Duration(minutes: 1)),
      );
      await commit('tomorrow', decisions[1].id, DateTime(2026, 11, 10));
      expect((await store.history(day: '2026-11-09')).length, 2);
      expect((await store.history(day: '2026-11-10')).single.wasNew, true);
    },
  );
  test(
    'session evidence survives close; clean grade rejected; event/cursor atomic and idempotent',
    () async {
      final id = decisions[0].id;
      var session = TrainingSession(
        token: 'session',
        remaining: [id, decisions[1].id],
      );
      await store.setSetting('session', session.encode());
      session = await store.recordAttempt(
        'session',
        id,
        const AttemptEvidence(hinted: true, mistakes: 1),
      );
      await store.db.close();
      store = await SqliteTrainerStore.open(
        databaseFactoryFfi,
        '${dir.path}/db',
      );
      final restored = TrainingSession.decode(
        (await store.setting('session'))!,
      );
      expect(restored.evidence(id).hinted, true);
      final now = DateTime(2026, 11, 9, 12);
      final cursor = restored.advance().encode();
      await expectLater(
        commit(restored.eventId(id), id, now, cursor: cursor),
        throwsStateError,
      );
      expect(await store.history(), isEmpty);
      expect(await store.setting('session'), restored.encode());
      await commit(
        restored.eventId(id),
        id,
        now,
        cursor: cursor,
        rating: Rating.again,
      );
      // Retry a delivered request: ignored before checking stale schedule/session.
      final duplicate = schedule(null, Rating.again, now);
      await store.review(
        restored.eventId(id),
        id,
        ScheduledReview(duplicate.state, duplicate.log, session: cursor),
      );
      final e = (await store.history()).single;
      expect(e.evidence.mistakes, 1);
      expect(e.evidence.hinted, true);
      expect(e.rating, Rating.again);
      expect(e.source, 's');
      expect(await store.setting('session'), cursor);
      final stats = ReviewStatistics(await store.history());
      expect(stats.hinted, 1);
      expect(stats.mistakes, 1);
    },
  );
  test(
    'stale callbacks cannot overwrite another session or schedule',
    () async {
      final id = decisions[0].id;
      final old = TrainingSession(token: 'old', remaining: [id]);
      final current = TrainingSession(token: 'current', remaining: [id]);
      await store.setSetting('session', current.encode());
      await expectLater(
        store.recordAttempt('old', id, const AttemptEvidence(hinted: true)),
        throwsStateError,
      );
      await expectLater(
        commit(
          old.eventId(id),
          id,
          DateTime(2026, 11, 9),
          cursor: old.advance().encode(),
        ),
        throwsStateError,
      );
      expect(await store.history(), isEmpty);
      expect(await store.setting('session'), current.encode());
      await commit(
        current.eventId(id),
        id,
        DateTime(2026, 11, 9),
        cursor: current.advance().encode(),
      );
      final stale = schedule(null, Rating.good, DateTime(2026, 11, 10));
      await expectLater(store.review('stale', id, stale), throwsStateError);
      expect((await store.history()).length, 1);
    },
  );
  test(
    'v2 backup history is backfilled and corrupt restore rolls back all changes',
    () async {
      final id = decisions[0].id;
      await commit('one', id, DateTime(2026, 11, 9));
      final snapshot = jsonDecode(await store.backup()) as Map<String, dynamic>;
      snapshot['version'] = 2;
      for (final row in snapshot['events']) {
        for (final col in ['at', 'day', 'is_new', 'source', 'chapter']) {
          row.remove(col);
        }
      }
      await store.restore(jsonEncode(snapshot));
      final event = (await store.history()).single;
      expect(event.wasNew, true);
      expect(event.source, 's');
      final good = await store.backup();
      snapshot['events'][0]['data'] = 'not JSON';
      await expectLater(
        store.restore(jsonEncode(snapshot)),
        throwsFormatException,
      );
      expect(await store.backup(), good);
      final broken = jsonDecode(good);
      final payload = jsonDecode(broken['decisions'][0]['data']);
      payload['fen'] = 'invalid';
      broken['decisions'][0]['data'] = jsonEncode(payload);
      await expectLater(
        store.restore(jsonEncode(broken)),
        throwsA(isA<Exception>()),
      );
      expect(await store.backup(), good);
    },
  );
}
