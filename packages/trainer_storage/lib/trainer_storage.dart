import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:trainer_core/trainer_core.dart';
part 'backup_validation.dart';

class SqliteTrainerStore implements TrainerStore {
  SqliteTrainerStore(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final Database db;
  final DateTime Function() _clock;
  static Future<SqliteTrainerStore> open(
    DatabaseFactory factory,
    String path, {
    DateTime Function()? clock,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onUpgrade: (db, old, next) async {
          if (old < 2)
            await db.execute(
              'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
          if (old < 3) await _upgradeEvents(db);
          if (old < 4) {
            await db.execute(
              'CREATE INDEX decisions_source ON decisions(source)',
            );
            await db.execute(
              "ALTER TABLE sources ADD COLUMN imported_at TEXT NOT NULL DEFAULT ''",
            );
            await _normalizeSources(db);
          }
        },
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE decisions(id TEXT PRIMARY KEY, source TEXT NOT NULL, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE states(id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE events(id TEXT PRIMARY KEY, decision TEXT NOT NULL, data TEXT NOT NULL, at TEXT NOT NULL DEFAULT \'\', day TEXT NOT NULL DEFAULT \'\', is_new INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT \'\', chapter TEXT NOT NULL DEFAULT \'\')',
          );
          await db.execute('CREATE INDEX events_day ON events(day, at)');
          await db.execute(
            'CREATE INDEX decisions_source ON decisions(source)',
          );
          await db.execute(
            "CREATE TABLE sources(id TEXT PRIMARY KEY, pgn TEXT NOT NULL, imported_at TEXT NOT NULL DEFAULT '')",
          );
        },
      ),
    );
    return SqliteTrainerStore(db, clock: clock);
  }

  @override
  Future<List<Decision>> decisions() async => (await db.query(
    'decisions',
  )).map((r) => Decision.fromJson(jsonDecode(r['data'] as String))).toList();
  @override
  Future<Map<String, ReviewState>> states() async => {
    for (final r in await db.query('states'))
      r['id'] as String: ReviewState.fromJson(jsonDecode(r['data'] as String)),
  };
  @override
  Future<void> replaceSource(String source, ImportResult imported) async {
    if (imported.decisions.any((d) => d.source != source))
      throw const FormatException('Source identity mismatch');
    final text = imported.pgn;
    final complete = imported.complete
        ? imported
        : await Isolate.run(() => importPgn(text, source));
    await db.transaction(
      (tx) => _replaceSource(tx, source, complete, _clock()),
    );
  }

  static Future<void> _replaceSource(
    DatabaseExecutor tx,
    String source,
    ImportResult imported,
    DateTime now,
  ) async {
    final old = await tx.query(
      'decisions',
      where: 'source = ?',
      whereArgs: [source],
    );
    final ids = imported.decisions.map((d) => d.id).toSet();
    if (ids.length != imported.decisions.length ||
        imported.decisions.any((d) => d.source != source))
      throw const FormatException('Invalid source snapshot');
    for (final d in imported.decisions) {
      Decision.fromJson(d.toJson());
    }
    final before = {
      for (final row in old)
        row['id'] as String: Decision.fromJson(
          jsonDecode(row['data'] as String),
        ),
    };
    final current = {for (final d in imported.decisions) d.id: d};
    final removed = before.keys.where((id) => !current.containsKey(id)).toSet();
    final previousStates = await tx.rawQuery(
      'SELECT states.id, states.data FROM states INNER JOIN decisions ON states.id = decisions.id WHERE decisions.source = ?',
      [source],
    );
    final suspend = tx.batch();
    for (final row in previousStates) {
      if (!removed.contains(row['id'])) continue;
      final state = ReviewState.fromJson(jsonDecode(row['data'] as String));
      suspend.update(
        'states',
        {'data': jsonEncode(ReviewState(state.card, suspended: true).toJson())},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await suspend.commit(noResult: true);
    await tx.delete('decisions', where: 'source = ?', whereArgs: [source]);
    // Keep batches bounded while retaining the outer transaction's atomicity.
    for (var offset = 0; offset < imported.decisions.length; offset += 500) {
      final batch = tx.batch();
      for (final d in imported.decisions.skip(offset).take(500)) {
        batch.insert('decisions', {
          'id': d.id,
          'source': source,
          'data': jsonEncode(d.toJson()),
        });
      }
      await batch.commit(noResult: true);
    }
    final scheduled = await tx.rawQuery(
      'SELECT states.id, states.data FROM states INNER JOIN decisions ON states.id = decisions.id WHERE decisions.source = ?',
      [source],
    );
    for (var offset = 0; offset < scheduled.length; offset += 500) {
      final batch = tx.batch();
      for (final row in scheduled.skip(offset).take(500)) {
        final id = row['id'] as String;
        final state = ReviewState.fromJson(jsonDecode(row['data'] as String));
        final changed = before[id]?.revision != current[id]!.revision;
        if (!changed && !state.suspended) continue;
        final card = changed
            ? state.card.copyWith(due: now.toUtc())
            : state.card;
        batch.update(
          'states',
          {'data': jsonEncode(ReviewState(card).toJson())},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);
    }
    final sessionRows = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['session'],
    );
    if (sessionRows.isNotEmpty) {
      final session = TrainingSession.decode(
        sessionRows.single['value'] as String,
      );
      final changed = before.keys
          .where((id) => current[id]?.revision != before[id]!.revision)
          .toSet();
      final remaining = session.remaining
          .where((id) => !removed.contains(id))
          .toList();
      if (changed.any(session.remaining.contains) ||
          remaining.length != session.remaining.length) {
        final updated = TrainingSession(
          token: identity([
            session.token,
            'source-refresh',
            source,
            imported.pgn,
          ]),
          remaining: remaining,
          attempts: {
            for (final e in session.attempts.entries)
              if (!removed.contains(e.key)) e.key: e.value,
          },
        );
        await tx.update(
          'settings',
          {'value': updated.encode()},
          where: 'key = ?',
          whereArgs: ['session'],
        );
      }
    }
    await tx.insert('sources', {
      'id': source,
      'pgn': imported.pgn,
      'imported_at': now.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _normalizeSources(DatabaseExecutor db) async {
    for (final row in await db.query('sources')) {
      final id = row['id'] as String;
      final text = row['pgn'] as String;
      final imported = await Isolate.run(() => importPgn(text, id));
      await _replaceSource(db, id, imported, DateTime.now().toUtc());
    }
  }

  @override
  Future<List<SourceSummary>> sources() async =>
      (await db.query(
            'sources',
            columns: ['id', 'imported_at'],
            orderBy: 'imported_at DESC, id ASC',
          ))
          .map(
            (r) => SourceSummary(
              id: r['id'] as String,
              importedAt: (r['imported_at'] as String).isEmpty
                  ? null
                  : DateTime.parse(r['imported_at'] as String),
            ),
          )
          .toList();
  @override
  Future<SourceSnapshot?> source(String id) async {
    final rows = await db.query('sources', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SourceSnapshot(
      id: id,
      pgn: row['pgn'] as String,
      importedAt: (row['imported_at'] as String).isEmpty
          ? null
          : DateTime.parse(row['imported_at'] as String),
    );
  }

  @override
  Future<void> review(
    String eventId,
    String decisionId,
    ScheduledReview review,
  ) async {
    await db.transaction((tx) async {
      if ((await tx.query(
        'events',
        where: 'id = ?',
        whereArgs: [eventId],
      )).isNotEmpty)
        return;
      final decisions = await tx.query(
        'decisions',
        where: 'id = ?',
        whereArgs: [decisionId],
      );
      if (decisions.isEmpty) throw StateError('Decision removed');
      final decision = Decision.fromJson(
        jsonDecode(decisions.single['data'] as String),
      );
      if (review.decisionRevision != null &&
          review.decisionRevision != decision.revision)
        throw StateError(
          'Study answers changed; reload the position before reviewing',
        );
      if (review.session != null && review.decisionRevision == null)
        throw StateError('A session review requires its source revision');
      final states = await tx.query(
        'states',
        where: 'id = ?',
        whereArgs: [decisionId],
      );
      final previous = states.isEmpty
          ? null
          : ReviewState.fromJson(jsonDecode(states.single['data'] as String));
      if (previous?.card.lastReview != review.previousReview)
        throw StateError('Schedule changed; reload before reviewing');
      final at = DateTime.parse(review.log['reviewDateTime'] as String).toUtc();
      final day = review.log['day'] as String? ?? reviewDay(at.toLocal());
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day))
        throw const FormatException('Invalid review day');
      final budget = DailyBudget(
        await _history(tx, day: day),
        newLimit: await _limit(tx, 'newLimit', 20),
        reviewLimit: await _limit(tx, 'reviewLimit', 100),
      );
      if (!budget.allows(decisionId, isNew: previous == null))
        throw const DailyLimitException();
      var evidence = const AttemptEvidence();
      if (review.session != null) {
        final currentRows = await tx.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['session'],
        );
        if (currentRows.isEmpty) throw StateError('No active session');
        if (currentRows.isNotEmpty) {
          final current = TrainingSession.decode(
            currentRows.single['value'] as String,
          );
          if (current.remaining.isEmpty ||
              current.remaining.first != decisionId)
            throw StateError('Session changed; reload');
          evidence = current.evidence(decisionId);
          if (eventId != current.eventId(decisionId))
            throw StateError('Review does not belong to this session');
          if (review.session != current.advance().encode())
            throw StateError('Invalid session cursor');
          if (evidence.rating == Rating.again &&
              review.log['rating'] != Rating.again.value)
            throw StateError(
              'A hinted or mistaken attempt must be graded Again',
            );
        }
        await tx.insert('settings', {
          'key': 'session',
          'value': review.session,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await tx.insert('events', {
        'id': eventId,
        'decision': decisionId,
        'data': jsonEncode({...review.log, 'evidence': evidence.toJson()}),
        'at': at.toIso8601String(),
        'day': day,
        'is_new': previous == null ? 1 : 0,
        'source': decision.source,
        'chapter': decision.chapter,
      });
      await tx.insert('states', {
        'id': decisionId,
        'data': jsonEncode(review.state.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<List<ReviewEvent>> history({String? day}) => _history(db, day: day);

  static Future<List<ReviewEvent>> _history(
    DatabaseExecutor tx, {
    String? day,
  }) async {
    final rows = await tx.query(
      'events',
      where: day == null ? null : 'day = ?',
      whereArgs: day == null ? null : [day],
      orderBy: 'at ASC, id ASC',
    );
    return rows.map((r) {
      final log = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return ReviewEvent(
        id: r['id'] as String,
        decisionId: r['decision'] as String,
        source: r['source'] as String,
        chapter: r['chapter'] as String,
        at: DateTime.parse(r['at'] as String),
        day: r['day'] as String,
        wasNew: r['is_new'] == 1,
        rating: Rating.fromValue(log['rating'] as int),
        evidence: log['evidence'] == null
            ? const AttemptEvidence()
            : AttemptEvidence.fromJson(
                Map<String, dynamic>.from(log['evidence']),
              ),
      );
    }).toList();
  }

  static Future<int> _limit(
    DatabaseExecutor tx,
    String key,
    int fallback,
  ) async {
    final rows = await tx.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? fallback : int.parse(rows.single['value'] as String);
  }

  @override
  Future<TrainingSession> recordAttempt(
    String sessionToken,
    String decisionId,
    AttemptEvidence evidence,
  ) => db.transaction((tx) async {
    final rows = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['session'],
    );
    if (rows.isEmpty) throw StateError('No active session');
    final session = TrainingSession.decode(rows.single['value'] as String);
    if (session.token != sessionToken)
      throw StateError('Session changed; reload');
    final updated = session.record(decisionId, evidence);
    await tx.update(
      'settings',
      {'value': updated.encode()},
      where: 'key = ?',
      whereArgs: ['session'],
    );
    return updated;
  });
  static Future<void> _upgradeEvents(DatabaseExecutor db) async {
    for (final column in [
      "at TEXT NOT NULL DEFAULT ''",
      "day TEXT NOT NULL DEFAULT ''",
      "is_new INTEGER NOT NULL DEFAULT 0",
      "source TEXT NOT NULL DEFAULT ''",
      "chapter TEXT NOT NULL DEFAULT ''",
    ]) {
      await db.execute('ALTER TABLE events ADD COLUMN $column');
    }
    await _backfillEvents(db);
    await db.execute('CREATE INDEX events_day ON events(day, at)');
  }

  static Future<void> _backfillEvents(DatabaseExecutor db) async {
    final rows = await db.query('events');
    final decisions = {
      for (final r in await db.query('decisions'))
        r['id']: Decision.fromJson(jsonDecode(r['data'] as String)),
    };
    final ordered = rows.toList()
      ..sort((a, b) {
        final la = jsonDecode(a['data'] as String),
            lb = jsonDecode(b['data'] as String);
        return (la['reviewDateTime'] as String).compareTo(
          lb['reviewDateTime'] as String,
        );
      });
    final seen = <String>{};
    for (final row in ordered) {
      final id = row['decision'] as String;
      final first = seen.add(id);
      if (row['at'] != '') continue;
      final log = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      final at = DateTime.parse(log['reviewDateTime'] as String).toUtc();
      await db.update(
        'events',
        {
          'at': at.toIso8601String(),
          'day': log['day'] ?? reviewDay(at),
          'is_new': first ? 1 : 0,
          'source': decisions[id]?.source ?? 'Archived source',
          'chapter': decisions[id]?.chapter ?? '',
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  @override
  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String> backup() async {
    final snapshot = await db.transaction((tx) async {
      var count = 0, size = 0;
      for (final entry in _backupColumns.entries) {
        final table = entry.key;
        final lengths = entry.value
            .map((c) => 'length(CAST($c AS BLOB))')
            .join(' + ');
        final totals = (await tx.rawQuery(
          'SELECT COUNT(*) AS n, COALESCE(SUM($lengths), 0) AS bytes FROM $table',
        )).single;
        count += totals['n'] as int;
        size += totals['bytes'] as int;
        if (count > maxBackupRows || size > maxBackupBytes) {
          throw const InputLimitException(
            'Backup exceeds 25 MB or 100,000 total rows.',
          );
        }
      }
      return {
        'version': 4,
        for (final table in _backupColumns.keys) table: await tx.query(table),
      };
    });
    return Isolate.run(() {
      final sink = _BackupByteSink();
      final encoder = JsonUtf8Encoder().startChunkedConversion(sink);
      encoder.add(snapshot);
      encoder.close();
      final text = utf8.decode(sink.bytes.takeBytes());
      _validatedBackup(text);
      return text;
    });
  }

  @override
  Future<void> restore(String text) async {
    // Bounded, depth-checked decoding and domain validation finish off the UI
    // isolate and before any existing row is deleted.
    final (version, tables) = await Isolate.run(() => _validatedBackup(text));
    await db.transaction((tx) async {
      for (final entry in tables.entries) {
        await tx.delete(entry.key);
        for (final row in entry.value) {
          await tx.insert(entry.key, row);
        }
      }
      await _backfillEvents(tx);
      if (version < 4) await _normalizeSources(tx);
    });
  }
}
