import 'dart:io';

import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:study_trainer/auth.dart';
import 'package:study_trainer/main.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_storage/trainer_storage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native keychain, PGN import, board move and durable offline review',
    (tester) async {
      expect(Platform.isIOS || Platform.isAndroid, isTrue);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      // Probe a new key without touching an existing account token.
      final probeKey = 'study_trainer.integration_probe.$stamp';
      final directory = await getApplicationSupportDirectory();
      final path = '${directory.path}/integration-$stamp.sqlite';
      SqliteTrainerStore? store;
      try {
        await SecureTokenVault.storage.write(
          key: probeKey,
          value: 'native-keychain-probe',
        );
        expect(
          await SecureTokenVault.storage.read(key: probeKey),
          'native-keychain-probe',
        );
        await SecureTokenVault.storage.delete(key: probeKey);
        expect(await SecureTokenVault.storage.read(key: probeKey), isNull);

        store = await SqliteTrainerStore.open(sqlite.databaseFactory, path);
        await tester.pumpWidget(
          TrainerBootstrap(openStore: () async => store!),
        );
        await waitFor(tester, find.text('Start due reviews'));
        await tester.tap(find.text('Import'));
        await waitFor(tester, find.text('Import or refresh'));
        await tester.enterText(
          find.widgetWithText(TextField, 'Study URL or stable local source ID'),
          'local:native-test',
        );
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Paste PGN (multiple chapters supported)',
          ),
          '[Event "Native test"]\n\n1. e4 {Central control} e5 *',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.ensureVisible(find.text('Import / refresh same source'));
        await tester.tap(find.text('Import / refresh same source'));
        await waitFor(tester, find.text('Saved locally'));
        expect((await store.decisions()).length, 2);
        await tester.tap(find.text('Library'));
        await waitFor(tester, find.text('Start due reviews'));
        await tester.tap(find.text('Start due reviews'));
        await waitFor(tester, find.byType(Chessboard));
        await tester.ensureVisible(find.text('Hint'));
        await tester.tap(find.text('Hint'));
        await waitFor(tester, find.text('From e2'));
        // Exercise touch interaction, not an injected onMove callback.
        final board = tester.getRect(find.byType(Chessboard));
        await tester.tapAt(
          board.topLeft + Offset(board.width * 4.5 / 8, board.height * 6.5 / 8),
        );
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tapAt(
          board.topLeft + Offset(board.width * 4.5 / 8, board.height * 4.5 / 8),
        );
        await waitFor(tester, find.textContaining('Correct · e4'));
        expect(find.text('Central control'), findsOneWidget);
        await tester.ensureVisible(find.text('Save review'));
        await tester.tap(find.text('Save review'));
        await waitFor(tester, find.text('Session complete. Progress saved.'));
        final event = (await store.history()).single;
        expect(event.rating, Rating.again);
        expect(event.evidence.hinted, isTrue);
        final saved = (await store.states())[event.decisionId]!.toJson();
        final backup = await store.backup();
        final backupFile = File('${directory.path}/integration-$stamp.json');
        await backupFile.writeAsString(backup, flush: true);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await store.db.close();
        store = await SqliteTrainerStore.open(sqlite.databaseFactory, path);
        expect((await store.states())[event.decisionId]!.toJson(), saved);
        await store.restore(await backupFile.readAsString());
        expect((await store.history()).single.id, event.id);
        await backupFile.delete();
        await tester.pumpWidget(TrainerApp(store: store));
        await waitFor(tester, find.text('Start due reviews'));
        await tester.tap(find.text('Progress'));
        await waitFor(
          tester,
          find.text('1 completed reviews · 0.0% unassisted recall'),
        );
        // Driver report is attached to the CI test run; no account or network required.
        binding.reportData = {
          'nativeFlow': 'passed',
          'keychain': 'passed',
          'sqliteReopen': 'passed',
          'backupRestore': 'passed',
        };
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (store != null && store.db.isOpen) await store.db.close();
        await SecureTokenVault.storage.delete(key: probeKey);
        await sqlite.databaseFactory.deleteDatabase(path);
      }
    },
  );
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 15),
      );
      return;
    }
  }
  fail('Timed out waiting for $finder');
}
