import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_flutter/trainer_flutter.dart';

void main() {
  testWidgets('injected board records Good only after a correct move', (
    tester,
  ) async {
    tester.view.reset();
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final decision = importPgn('1. e4 *', 'local', Side.white).decisions.single;
    Rating? recorded;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingBoard(
            decision: decision,
            onComplete: (r) async {
              recorded = r;
            },
          ),
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
      Move.parse('e2e4')!,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();
    expect(recorded, Rating.good);
  });
  testWidgets('hint or wrong move forces Again', (tester) async {
    tester.view.reset();
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final decision = importPgn('1. e4 *', 'local', Side.white).decisions.single;
    Rating? recorded;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingBoard(
            decision: decision,
            onComplete: (r) async {
              recorded = r;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hint'));
    await tester.pump();
    tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
      Move.parse('e2e4')!,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();
    expect(recorded, Rating.again);
  });
  testWidgets(
    'hint is revealed only after persistence and recovered penalty cannot become Good',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final decision = importPgn(
        '1. e4 *',
        'local',
        Side.white,
      ).decisions.single;
      final gate = Completer<void>();
      AttemptEvidence? saved;
      Rating? rating;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainingBoard(
              decision: decision,
              onComplete: (r) async {
                rating = r;
              },
              onAttemptChanged: (e) async {
                saved = e;
                await gate.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Hint'));
      await tester.pump();
      expect(saved!.hinted, true);
      expect(find.text('From e2'), findsNothing);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('From e2'), findsOneWidget);
      // Simulate disposal/recovery with the durable evidence supplied by the host.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainingBoard(
              decision: decision,
              initialEvidence: saved!,
              onComplete: (r) async {
                rating = r;
              },
            ),
          ),
        ),
      );
      tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
        Move.parse('e2e4')!,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save review'));
      await tester.pumpAndSettle();
      expect(rating, Rating.again);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'failed attempt persistence keeps hint hidden and permits retry',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final decision = importPgn(
        '1. e4 *',
        'local',
        Side.white,
      ).decisions.single;
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainingBoard(
              decision: decision,
              onComplete: (r) async {},
              onAttemptChanged: (e) async {
                if (calls++ == 0) throw StateError('disk full');
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Hint'));
      await tester.pumpAndSettle();
      expect(find.text('From e2'), findsNothing);
      expect(find.textContaining('Could not save attempt'), findsOneWidget);
      await tester.tap(find.text('Hint'));
      await tester.pumpAndSettle();
      expect(find.text('From e2'), findsOneWidget);
    },
  );
  testWidgets(
    'notes and glyphs are hidden until recall, then a legal opponent reply is automatic',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final decision = importPgn(
        '{Context mentioning e4} 1. e4! {Control the center} e5 *',
        's',
      ).decisions.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainingBoard(decision: decision, onComplete: (r) async {}),
          ),
        ),
      );
      expect(find.text('Control the center'), findsNothing);
      expect(find.text('Context mentioning e4'), findsNothing);
      expect(find.text('!'), findsNothing);
      tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
        Move.parse('e2e4')!,
      );
      await tester.pumpAndSettle();
      final expected = Chess.initial
          .playUnchecked(Move.parse('e2e4')!)
          .playUnchecked(Move.parse('e7e5')!);
      final controller = tester
          .widget<Chessboard>(find.byType(Chessboard))
          .controller;
      expect(controller.fen, expected.fen);
      expect(controller.interactive, false);
      expect(controller.lastMove, Move.parse('e7e5'));
      expect(find.text('Control the center'), findsOneWidget);
      expect(find.text('Context mentioning e4'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    },
  );
  testWidgets('host can translate feedback and disable automatic replies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final decision = importPgn('1. e4 e5 *', 's').decisions.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingBoard(
            decision: decision,
            onComplete: (r) async {},
            playOpponentReply: false,
            strings: const TrainingStrings(
              findMove: 'Finde einen Zug',
              hint: 'Hinweis',
              save: 'Speichern',
              correct: 'Richtig',
              whiteToMove: 'Weiß am Zug',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Finde einen Zug'), findsOneWidget);
    expect(find.text('Hinweis'), findsOneWidget);
    expect(find.text('Weiß am Zug'), findsOneWidget);
    tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
      Move.parse('e2e4')!,
    );
    await tester.pumpAndSettle();
    expect(find.text('Richtig · e4'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(
      tester.widget<Chessboard>(find.byType(Chessboard)).controller.fen,
      Chess.initial.playUnchecked(Move.parse('e2e4')!).fen,
    );
  });
  testWidgets(
    'pending attempt from an old source revision cannot mutate the refreshed board',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final old = importPgn('1. e4 *', 's').decisions.single,
          newer = importPgn('1. d4 *', 's').decisions.single;
      expect(old.id, newer.id);
      final gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainingBoard(
              decision: old,
              onComplete: (r) async {},
              onAttemptChanged: (e) => gate.future,
            ),
          ),
        ),
      );
      tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
        Move.parse('e2e4')!,
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainingBoard(decision: newer, onComplete: (r) async {}),
          ),
        ),
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Chessboard>(find.byType(Chessboard)).controller.fen,
        Chess.initial.fen,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('Correct ·'), findsNothing);
      tester.widget<Chessboard>(find.byType(Chessboard)).onMove!(
        Move.parse('d2d4')!,
      );
      await tester.pumpAndSettle();
      expect(find.text('Correct · d4'), findsOneWidget);
    },
  );
}
