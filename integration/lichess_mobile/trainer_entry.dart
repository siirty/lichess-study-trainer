import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:lichess_mobile/src/model/study/study.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_flutter/trainer_flutter.dart';

/// Call with PGN returned by StudyRepository.getStudy; host retains authentication.
ImportResult trainingChapter(Study study, String pgn) {
  final game = PgnGame.parsePgn(pgn);
  // Bind identity to server IDs rather than mutable display names.
  game.headers['Site'] =
      'https://lichess.org/study/${study.id.value}/${study.chapter.id.value}';
  return importPgn(
    game.makePgn(),
    'lichess:${study.id.value}/${study.chapter.id.value}',
  );
}

Widget trainingEntry(
  Decision decision,
  Future<void> Function(Rating) commit, {
  AttemptEvidence evidence = const AttemptEvidence(),
  Future<void> Function(AttemptEvidence)? recordAttempt,
  TrainingStrings strings = const TrainingStrings(),
}) => TrainingBoard(
  decision: decision,
  onComplete: commit,
  initialEvidence: evidence,
  onAttemptChanged: recordAttempt,
  strings: strings,
);
