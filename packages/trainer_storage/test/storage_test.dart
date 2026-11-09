import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:dartchess/dartchess.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_storage/trainer_storage.dart';

void main() {
  test('v1 database upgrades to v4 without removing existing tables', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('trainer-migration');
    final path = '${dir.path}/db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE decisions(id TEXT PRIMARY KEY, source TEXT NOT NULL, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE states(id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE events(id TEXT PRIMARY KEY, decision TEXT NOT NULL, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE sources(id TEXT PRIMARY KEY, pgn TEXT NOT NULL)',
          );
          await db.insert('sources', {'id': 'existing', 'pgn': '1. e4 *'});
          final event = schedule(null, Rating.good, DateTime.utc(2026, 11, 8));
          await db.insert('events', {
            'id': 'legacy',
            'decision': 'removed-decision',
            'data': jsonEncode(event.log),
          });
        },
      ),
    );
    await old.close();
    final upgraded = await SqliteTrainerStore.open(databaseFactoryFfi, path);
    expect(await upgraded.db.getVersion(), 4);
    expect((await upgraded.db.query('sources')).single['id'], 'existing');
    await upgraded.setSetting('session', '[]');
    expect(await upgraded.setting('session'), '[]');
    final legacy = (await upgraded.history()).single;
    expect(legacy.wasNew, true);
    expect(legacy.source, 'Archived source');
    expect(legacy.day, '2026-11-08');
    await upgraded.db.close();
    await dir.delete(recursive: true);
  });
  sqfliteFfiInit();
  test(
    'review survives reopen, refresh, deletion, backup; duplicate delivery is idempotent',
    () async {
      final dir = await Directory.systemTemp.createTemp('trainer-test');
      final path = '${dir.path}/db';
      var s = await SqliteTrainerStore.open(databaseFactoryFfi, path);
      final r = importPgn('[Event "A"]\n\n1. e4 e5 2. Nf3 *', 'a', Side.white);
      await s.replaceSource('a', r);
      final id = r.decisions.first.id;
      final review = schedule(null, Rating.good, DateTime.utc(2026));
      await s.review('event', id, review);
      await s.review('event', id, review);
      final backup = await s.backup();
      await s.db.close();
      s = await SqliteTrainerStore.open(databaseFactoryFfi, path);
      expect((await s.states())[id]!.card.toMap(), review.state.card.toMap());
      await s.replaceSource(
        'a',
        importPgn('[Event "A"]\n\n1. d4 *', 'a', Side.white),
      );
      expect((await s.states())[id]!.suspended, false);
      await s.replaceSource(
        'a',
        importPgn('[Event "B"]\n\n1. d4 *', 'a', Side.white),
      );
      expect((await s.states())[id]!.suspended, true);
      await s.restore(backup);
      expect((await s.decisions()).length, 3);
      expect((await s.db.query('events')).length, 1);
      await expectLater(s.restore('{"version":99}'), throwsFormatException);
      expect((await s.decisions()).length, 3);
      await s.db.close();
      await dir.delete(recursive: true);
    },
  );
}
