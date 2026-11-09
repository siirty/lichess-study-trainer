import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:trainer_core/trainer_core.dart';

/// Host-localizable feedback. Study comments are always rendered as plain text.
class TrainingStrings {
  const TrainingStrings({
    this.hint = 'Hint',
    this.save = 'Save review',
    this.saving = 'Saving…',
    this.findMove = 'Find a repertoire move',
    this.wrongMove = 'Try another repertoire move',
    this.whiteToMove = 'White to move',
    this.blackToMove = 'Black to move',
    this.correct = 'Correct',
    this.reply = 'Reply',
    this.from = 'From',
    this.notes = 'Study notes',
    this.saveError = 'Could not save',
    this.attemptError = 'Could not save attempt',
  });
  final String hint,
      save,
      saving,
      findMove,
      wrongMove,
      whiteToMove,
      blackToMove,
      correct,
      reply,
      from,
      notes,
      saveError,
      attemptError;
}

/// Host owns navigation, storage, queue selection and localization.
class TrainingBoard extends StatefulWidget {
  const TrainingBoard({
    super.key,
    required this.decision,
    required this.onComplete,
    this.initialEvidence = const AttemptEvidence(),
    this.onAttemptChanged,
    this.hintLabel,
    this.nextLabel,
    this.strings = const TrainingStrings(),
    this.playOpponentReply = true,
  });
  final Decision decision;
  final Future<void> Function(Rating rating) onComplete;
  final String? hintLabel, nextLabel;
  final TrainingStrings strings;
  final bool playOpponentReply;
  final AttemptEvidence initialEvidence;
  final Future<void> Function(AttemptEvidence evidence)? onAttemptChanged;
  @override
  State<TrainingBoard> createState() => _TrainingBoardState();
}

class _TrainingBoardState extends State<TrainingBoard> {
  late Position position;
  late ChessboardController controller;
  late AttemptEvidence evidence;
  bool correct = false, busy = false, saved = false;
  String feedback = '';
  String? playedMove;
  Move? lastMove;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    evidence = widget.initialEvidence;
    reset();
  }

  void reset() {
    epoch++;
    playedMove = null;
    lastMove = null;
    position = Chess.fromSetup(Setup.parseFen(widget.decision.fen));
    controller = ChessboardController(game: game());
  }

  GameData game() => GameData(
    fen: position.fen,
    lastMove: lastMove,
    kingSquareInCheck: position.isCheck
        ? position.board.kingOf(position.turn)
        : null,
    playerSide: correct
        ? PlayerSide.none
        : position.turn == Side.white
        ? PlayerSide.white
        : PlayerSide.black,
    validMoves: makeLegalMoves(position),
    sideToMove: position.turn,
  );
  @override
  void didUpdateWidget(TrainingBoard old) {
    super.didUpdateWidget(old);
    if (old.decision.revision != widget.decision.revision ||
        old.decision.fen != widget.decision.fen) {
      controller.dispose();
      evidence = widget.initialEvidence;
      correct = false;
      saved = false;
      busy = false;
      feedback = '';
      reset();
    }
  }

  @override
  void dispose() {
    epoch++;
    controller.dispose();
    super.dispose();
  }

  Future<void> move(Move move, {bool? viaDragAndDrop}) async {
    if (correct || busy) return;
    final accepted = widget.decision.accepts(move);
    final next = accepted
        ? evidence
        : AttemptEvidence(
            hinted: evidence.hinted,
            mistakes: evidence.mistakes + 1,
          );
    if (!await persistEvidence(next) || !mounted) return;
    setState(() {
      if (widget.decision.accepts(move)) {
        correct = true;
        final (afterMove, san) = position.makeSan(move);
        feedback = '${widget.strings.correct} · $san';
        playedMove = move.uci;
        lastMove = move;
        position = afterMove;
        final replies = (widget.decision.replies[move.uci] ?? {}).toList()
          ..sort();
        if (widget.playOpponentReply && replies.isNotEmpty) {
          final reply = Move.parse(replies.first)!;
          final (afterReply, replySan) = position.makeSan(reply);
          feedback += ' · ${widget.strings.reply} $replySan';
          position = afterReply;
          lastMove = reply;
        }
      } else {
        feedback = widget.strings.wrongMove;
      }
      controller.updatePosition(game());
    });
  }

  Future<bool> persistEvidence(AttemptEvidence next) async {
    final generation = epoch;
    evidence = evidence.merge(next);
    setState(() => busy = true);
    try {
      await widget.onAttemptChanged?.call(evidence);
      return mounted && epoch == generation;
    } catch (_) {
      if (mounted && epoch == generation)
        setState(() => feedback = widget.strings.attemptError);
      return false;
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  Future<void> hint() async {
    if (correct || busy) return;
    if (await persistEvidence(
          AttemptEvidence(hinted: true, mistakes: evidence.mistakes),
        ) &&
        mounted) {
      setState(
        () => feedback =
            '${widget.strings.from} ${widget.decision.moves.first.substring(0, 2)}',
      );
    }
  }

  Future<void> save() async {
    final generation = epoch;
    setState(() => busy = true);
    try {
      await widget.onComplete(evidence.rating);
      if (mounted && epoch == generation) saved = true;
    } catch (_) {
      if (mounted && epoch == generation)
        setState(() => feedback = widget.strings.saveError);
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        widget.decision.title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        widget.decision.side == Side.white
            ? widget.strings.whiteToMove
            : widget.strings.blackToMove,
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, c) => Chessboard(
          controller: controller,
          size: min(c.maxWidth, 480),
          orientation: Chess.fromSetup(
            Setup.parseFen(widget.decision.fen),
          ).turn,
          onMove: move,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        feedback.isEmpty ? widget.strings.findMove : feedback,
        semanticsLabel: feedback,
      ),
      Wrap(
        spacing: 12,
        children: [
          TextButton(
            onPressed: correct || busy ? null : hint,
            child: Text(widget.hintLabel ?? widget.strings.hint),
          ),
          FilledButton(
            onPressed: correct && !busy && !saved ? save : null,
            child: Text(
              busy
                  ? widget.strings.saving
                  : widget.nextLabel ?? widget.strings.save,
            ),
          ),
        ],
      ),
      if (correct && playedMove != null) ...[
        if ((widget.decision.glyphs[playedMove] ?? []).isNotEmpty)
          Text(
            (widget.decision.glyphs[playedMove] ?? [])
                .map(
                  (n) =>
                      const {
                        1: '!',
                        2: '?',
                        3: '!!',
                        4: '??',
                        5: '!?',
                        6: '?!',
                      }[n] ??
                      '\$$n',
                )
                .join(' '),
          ),
        if (widget.decision.contextComments.isNotEmpty ||
            (widget.decision.annotations[playedMove] ?? []).isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            widget.strings.notes,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final note in {
            ...widget.decision.contextComments,
            ...widget.decision.annotations[playedMove] ?? const <String>[],
          })
            Text(note),
        ],
      ],
    ],
  );
}
