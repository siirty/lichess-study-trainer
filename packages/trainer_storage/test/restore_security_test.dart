import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_storage/trainer_storage.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late SqliteTrainerStore store;
  late String original;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('restore-security');
    store = await SqliteTrainerStore.open(
      databaseFactoryFfi,
      '${directory.path}/db',
    );
    await store.replaceSource('local', importPgn('1. e4 e5 *', 'local'));
    await store.setSetting('retention', '.9');
    original = await store.backup();
  });
  tearDown(() async {
    await store.db.close();
    await directory.delete(recursive: true);
  });
  test(
    'malformed rows, duplicate identities and poisoned settings preserve database',
    () async {
      final mutations = <void Function(Map<String, dynamic>)>[
        (j) => j['settings'][0]['value'] = 'NaN',
        (j) => j['settings'][0]['value'] = '1.0',
        (j) => j['settings'].add({
          'key': 'session',
          'value': '{"secret":"private"}',
        }),
        (j) => j['settings'].add({'key': 'unknown', 'value': 'private'}),
        (j) => j['decisions'].add(j['decisions'][0]),
        (j) => j['decisions'][0]['source'] = 'forged',
        (j) => j['sources'][0]['unexpected_column'] = 'private',
        (j) => j['states'] = [
          {'id': 'broken', 'data': '{"private":${'[' * 65}0${']' * 65}}'},
        ],
      ];
      for (final mutate in mutations) {
        final j = jsonDecode(original) as Map<String, dynamic>;
        mutate(j);
        await expectLater(
          store.restore(jsonEncode(j)),
          throwsA(anyOf(isA<FormatException>(), isA<InputLimitException>())),
        );
        expect(await store.backup(), original);
      }
    },
  );
  test('row and byte budgets reject before replacing saved library', () async {
    final j = jsonDecode(original) as Map<String, dynamic>;
    j['states'] = List.generate(
      maxBackupRows + 1,
      (i) => {'id': '$i', 'data': '{}'},
    );
    await expectLater(
      store.restore(jsonEncode(j)),
      throwsA(isA<InputLimitException>()),
    );
    await expectLater(
      store.restore(' ' * (maxBackupBytes + 1)),
      throwsA(isA<InputLimitException>()),
    );
    expect(await store.backup(), original);
  });
}
