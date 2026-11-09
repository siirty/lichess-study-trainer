import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:study_trainer/main.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_storage/trainer_storage.dart';

void main() {
  testWidgets(
    'offline host recovers mistaken attempt after database reopen and reports history',
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp('host-offline');
        var store = await SqliteTrainerStore.open(
          databaseFactoryFfi,
          '${dir.path}/db',
        );
        await store.replaceSource(
          'local',
          importPgn('1. e4 *', 'local', Side.white),
        );
        await store.setSetting('newLimit', '1');
        await tester.pumpWidget(TrainerApp(store: store));
        await waitFor(
          tester,
          () =>
              find.text('Start due reviews').evaluate().isNotEmpty ||
              find.byType(Chessboard).evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Start due reviews'));
        await waitFor(
          tester,
          () => find.byType(Chessboard).evaluate().isNotEmpty,
        );
        tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
          Move.parse('d2d4')!,
        );
        await waitFor(
          tester,
          () => find.text('Try another repertoire move').evaluate().isNotEmpty,
        );
        expect(find.text('Try another repertoire move'), findsOneWidget);
        final pending = TrainingSession.decode(
          (await store.setting('session'))!,
        );
        expect(pending.evidence(pending.remaining.single).mistakes, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await store.db.close();
        store = await SqliteTrainerStore.open(
          databaseFactoryFfi,
          '${dir.path}/db',
        );
        await tester.pumpWidget(TrainerApp(store: store));
        await waitFor(
          tester,
          () =>
              find.text('Start due reviews').evaluate().isNotEmpty ||
              find.byType(Chessboard).evaluate().isNotEmpty,
        );
        expect(find.byType(Chessboard), findsOneWidget);
        tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
          Move.parse('e2e4')!,
        );
        await waitFor(
          tester,
          () => find.textContaining('Correct ·').evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.text('Save review'));
        await tester.tap(find.text('Save review'));
        await waitFor(
          tester,
          () => find
              .text('Session complete. Progress saved.')
              .evaluate()
              .isNotEmpty,
        );
        final event = (await store.history()).single;
        expect(event.rating, Rating.again);
        expect(event.evidence.mistakes, 1);
        expect(
          TrainingSession.decode((await store.setting('session'))!).remaining,
          isEmpty,
        );
        await tester.tap(find.text('Return to library'));
        await waitFor(
          tester,
          () => find
              .text('Today: 0 new slots · 100 review slots remaining')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.text('Today: 0 new slots · 100 review slots remaining'),
          findsOneWidget,
        );
        await tester.tap(find.text('Progress'));
        await tester.pumpAndSettle();
        expect(
          find.text('1 completed reviews · 0.0% unassisted recall'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        await store.db.close();
        await dir.delete(recursive: true);
      });
    },
  );
  testWidgets(
    'one offline source trains either side without replacing progress',
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(600, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp('two-sides-host');
        var store = await SqliteTrainerStore.open(
          databaseFactoryFfi,
          '${dir.path}/db',
        );
        await store.replaceSource('local', importPgn('1. e4 e5 *', 'local'));
        await store.setSetting('newLimit', '2');
        await tester.pumpWidget(TrainerApp(store: store));
        await waitFor(
          tester,
          () => find.text('Start due reviews').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Start due reviews'));
        await waitFor(
          tester,
          () => find.byType(Chessboard).evaluate().isNotEmpty,
        );
        expect(find.text('White to move'), findsOneWidget);
        tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
          Move.parse('e2e4')!,
        );
        await waitFor(
          tester,
          () => find.textContaining('Correct ·').evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.text('Save review'));
        await tester.tap(find.text('Save review'));
        await waitFor(
          tester,
          () => find
              .text('Session complete. Progress saved.')
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.text('Return to library'));
        await waitFor(
          tester,
          () =>
              find.byKey(const ValueKey('trainingSide')).evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('trainingSide')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Train black').last);
        await waitFor(
          tester,
          () =>
              tester
                  .widget<DropdownButton<Side>>(
                    find.byKey(const ValueKey('trainingSide')),
                  )
                  .value ==
              Side.black,
        );
        await tester.tap(find.text('Start due reviews'));
        await waitFor(
          tester,
          () => find.byType(Chessboard).evaluate().isNotEmpty,
        );
        expect(find.text('Black to move'), findsOneWidget);
        tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
          Move.parse('e7e5')!,
        );
        await waitFor(
          tester,
          () => find.textContaining('Correct ·').evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.text('Save review'));
        await tester.tap(find.text('Save review'));
        await waitFor(
          tester,
          () => find
              .text('Session complete. Progress saved.')
              .evaluate()
              .isNotEmpty,
        );
        final states = await store.states();
        final events = await store.history();
        expect(states.length, 2);
        expect(states.values.any((s) => s.suspended), false);
        expect(events.map((e) => e.decisionId).toSet().length, 2);
        expect((await store.sources()).length, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await store.db.close();
        store = await SqliteTrainerStore.open(
          databaseFactoryFfi,
          '${dir.path}/db',
        );
        await tester.pumpWidget(TrainerApp(store: store));
        await waitFor(
          tester,
          () =>
              find.byKey(const ValueKey('trainingSide')).evaluate().isNotEmpty,
        );
        expect(
          tester
              .widget<DropdownButton<Side>>(
                find.byKey(const ValueKey('trainingSide')),
              )
              .value,
          Side.black,
        );
        expect(
          find.text('Today: 0 new slots · 100 review slots remaining'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        await store.db.close();
        await dir.delete(recursive: true);
      });
    },
  );
  testWidgets(
    'backup export requires privacy acknowledgement before opening picker',
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(600, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp('backup-notice');
        final store = await SqliteTrainerStore.open(
          databaseFactoryFfi,
          '${dir.path}/db',
        );
        await tester.pumpWidget(TrainerApp(store: store));
        await waitFor(
          tester,
          () => find.text('Start due reviews').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Export full backup'));
        await tester.tap(find.text('Export full backup'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Export readable backup?'), findsOneWidget);
        expect(find.textContaining('It is not encrypted.'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await waitFor(
          tester,
          () => find.text('Export readable backup?').evaluate().isEmpty,
        );
        expect(find.text('Export readable backup?'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await store.db.close();
        await dir.delete(recursive: true);
      });
    },
  );
  testWidgets(
    'startup failure can be retried without exposing data or replacing the library',
    (tester) async {
      await tester.runAsync(() async {
        tester.view.physicalSize = const Size(600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        sqfliteFfiInit();
        final dir = await Directory.systemTemp.createTemp('startup-retry');
        final store = await SqliteTrainerStore.open(
          databaseFactoryFfi,
          '${dir.path}/db',
        );
        await store.replaceSource(
          'existing',
          importPgn('1. e4 e5 *', 'existing'),
        );
        var calls = 0;
        await tester.pumpWidget(
          TrainerBootstrap(
            openStore: () async {
              if (calls++ == 0)
                throw StateError('Private study text must not be displayed');
              return store;
            },
          ),
        );
        await waitFor(
          tester,
          () => find.text('Retry opening library').evaluate().isNotEmpty,
        );
        expect(find.textContaining('Private study text'), findsNothing);
        expect((await store.decisions()).length, 2);
        await tester.tap(find.text('Retry opening library'));
        await waitFor(
          tester,
          () => find.text('Start due reviews').evaluate().isNotEmpty,
        );
        expect(calls, 2);
        expect((await store.sources()).single.id, 'existing');
        await tester.pumpWidget(const SizedBox());
        await store.db.close();
        await dir.delete(recursive: true);
      });
    },
  );
}

// Let the actual SQLite isolate complete IO between Flutter frames. Fake-time
// pumpAndSettle alone would spin the loading indicator without yielding to IO.
Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 1000; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
    if (ready() && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Timed out waiting for offline UI transition');
}
