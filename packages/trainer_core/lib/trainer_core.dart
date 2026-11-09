import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
export 'package:fsrs/fsrs.dart' show Rating;

export 'input_limits.dart';
import 'input_limits.dart';
export 'src_training.dart';
import 'src_training.dart';

String identity(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
// Counters do not define a decision. Keep en-passant conservatively to avoid false merges.
String positionKey(Position p) => p.fen.split(' ').take(4).join(' ');

class Decision {
  Decision({
    required this.id,
    required this.source,
    required this.chapter,
    required this.title,
    required this.fen,
    required Set<String> moves,
    Map<String, List<String>> annotations = const {},
    Map<String, List<int>> glyphs = const {},
    Map<String, Set<String>> replies = const {},
    Iterable<String> contextComments = const [],
  }) : moves = Set.unmodifiable(moves),
       annotations = Map.unmodifiable({
         for (final e in annotations.entries)
           e.key: List<String>.unmodifiable(e.value),
       }),
       glyphs = Map.unmodifiable({
         for (final e in glyphs.entries) e.key: List<int>.unmodifiable(e.value),
       }),
       replies = Map.unmodifiable({
         for (final e in replies.entries)
           e.key: Set<String>.unmodifiable(e.value),
       }),
       contextComments = List.unmodifiable(contextComments);
  final String id, source, chapter, title, fen;
  final Set<String> moves;
  final Map<String, List<String>> annotations;
  final Map<String, List<int>> glyphs;
  final Map<String, Set<String>> replies;
  final List<String> contextComments;
  Side get side => fen.split(' ')[1] == 'w' ? Side.white : Side.black;
  String get revision => identity([id, moves.toList()..sort()]);
  bool accepts(Move move) =>
      moves.contains(move.uci) &&
      Chess.fromSetup(Setup.parseFen(fen)).isLegal(move);
  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'chapter': chapter,
    'title': title,
    'fen': fen,
    'moves': moves.toList(),
    'annotations': annotations,
    'glyphs': glyphs,
    'replies': {for (final e in replies.entries) e.key: e.value.toList()},
    'contextComments': contextComments,
  };
  factory Decision.fromJson(Map<String, dynamic> j) {
    final decision = Decision(
      id: j['id'] as String,
      source: j['source'] as String,
      chapter: j['chapter'] as String,
      title: j['title'] as String,
      fen: j['fen'] as String,
      moves: Set<String>.from(j['moves']),
      annotations: {
        for (final e
            in (j['annotations'] as Map<String, dynamic>? ?? {}).entries)
          e.key: List<String>.from(e.value),
      },
      glyphs: {
        for (final e in (j['glyphs'] as Map<String, dynamic>? ?? {}).entries)
          e.key: List<int>.from(e.value),
      },
      replies: {
        for (final e in (j['replies'] as Map<String, dynamic>? ?? {}).entries)
          e.key: Set<String>.from(e.value),
      },
      contextComments: List<String>.from(j['contextComments'] ?? const []),
    );
    final position = Chess.fromSetup(Setup.parseFen(decision.fen));
    if (decision.id.isEmpty ||
        decision.source.isEmpty ||
        decision.chapter.isEmpty ||
        decision.moves.isEmpty)
      throw const FormatException('Incomplete decision');
    for (final uci in decision.moves) {
      final move = Move.parse(uci);
      if (move == null || !position.isLegal(move))
        throw const FormatException('Invalid repertoire move');
    }
    if ([
      ...decision.annotations.keys,
      ...decision.glyphs.keys,
      ...decision.replies.keys,
    ].any((key) => !decision.moves.contains(key)))
      throw const FormatException('Annotation has no repertoire move');
    for (final entry in decision.replies.entries) {
      final next = position.playUnchecked(Move.parse(entry.key)!);
      for (final uci in entry.value) {
        final reply = Move.parse(uci);
        if (reply == null || !next.isLegal(reply))
          throw const FormatException('Invalid opponent reply');
      }
    }
    return decision;
  }
}

class ImportResult {
  ImportResult(Iterable<Decision> decisions, this.pgn, {this.complete = true})
    : decisions = List.unmodifiable(decisions);

  /// A complete source snapshot contains both sides. A side-scoped extraction
  /// must be normalized before replacing authoritative source content.
  final bool complete;
  final List<Decision> decisions;
  final String pgn;
}

// dartchess deliberately accepts incomplete PGN. Before replacing an offline
// source, reject visibly truncated containers while leaving chess/SAN parsing
// to dartchess. This is a structural guard, not a second PGN implementation.
void _validatePgnContainers(String text) {
  var depth = 0, moveCharacters = 0, headers = 0;
  var header = false,
      quoted = false,
      escaped = false,
      comment = false,
      lineComment = false,
      lineStart = true;
  for (final code in text.codeUnits) {
    if (code == 10 || code == 13) {
      lineComment = false;
      lineStart = true;
      if (!quoted) escaped = false;
      continue;
    }
    if (lineComment) continue;
    if (lineStart && code == 37 && !comment && !quoted && !header) {
      lineComment = true;
      continue;
    }
    if (code != 0xfeff) lineStart = false;
    if (comment) {
      if (code == 125) comment = false;
      continue;
    }
    if (quoted) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (code == 92) {
        escaped = true;
        continue;
      }
      if (code == 34) quoted = false;
      continue;
    }
    if (code == 59) {
      lineComment = true;
      continue;
    }
    if (code == 123) {
      comment = true;
      continue;
    }
    if (code == 125) throw const FormatException('Unmatched PGN comment');
    if (code == 34 && header) {
      quoted = true;
      continue;
    }
    if (code == 91) {
      if (++headers > maxPgnChapters * 32)
        throw const InputLimitException('Too many PGN headers.');
      if (header) throw const FormatException('Nested PGN header');
      header = true;
      continue;
    }
    if (code == 93) {
      if (!header) throw const FormatException('Unmatched PGN header');
      header = false;
      continue;
    }
    if (header) continue;
    if (code > 32 && ++moveCharacters > 750000)
      throw const InputLimitException(
        'PGN move text exceeds the supported limit.',
      );
    if (code == 40 && ++depth > maxPgnVariationDepth)
      throw const InputLimitException('Too many nested PGN variations.');
    if (code == 41 && --depth < 0)
      throw const FormatException('Unmatched PGN variation');
  }
  if (depth != 0 || header || quoted || comment)
    throw const FormatException('Incomplete PGN; existing source was retained');
}

// Match the upstream multi-game separator (newline, whitespace, then '[')
// in linear time. A backtracking newline/whitespace regex can take quadratic
// time on an otherwise small file containing many blank lines.
bool _pgnWhitespace(int c) =>
    (c >= 9 && c <= 13) ||
    c == 32 ||
    c == 160 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200a) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202f ||
    c == 0x205f ||
    c == 0x3000 ||
    c == 0xfeff;

Iterable<PgnGame<PgnNodeData>> _parsePgnGames(String pgn) sync* {
  var start = 0, i = 0, games = 0;
  while (i < pgn.length) {
    if (pgn.codeUnitAt(i) != 10) {
      i++;
      continue;
    }
    var next = i + 1;
    while (next < pgn.length && _pgnWhitespace(pgn.codeUnitAt(next))) {
      next++;
    }
    if (next > i + 1 && next < pgn.length && pgn.codeUnitAt(next) == 91) {
      final text = pgn.substring(start, i);
      if (text.trim().isNotEmpty) {
        if (++games > maxPgnChapters)
          throw const InputLimitException('Too many PGN chapters.');
        yield PgnGame.parsePgn(text);
      }
      start = next;
    }
    i = next;
  }
  final text = pgn.substring(start);
  if (text.trim().isNotEmpty) {
    if (++games > maxPgnChapters)
      throw const InputLimitException('Too many PGN chapters.');
    yield PgnGame.parsePgn(text);
  }
}

/// Omitting [side] imports both colors in one pass. Existing side-scoped callers
/// keep the same deterministic IDs as a combined import.
ImportResult importPgn(String pgn, String source, [Side? side]) {
  if (source.isEmpty || source.length > 512)
    throw const FormatException(
      'Source identifier must contain 1–512 characters',
    );
  checkTextBytes(pgn, maxPgnBytes);
  _validatePgnContainers(pgn);
  final games = _parsePgnGames(pgn);
  final decisions = <Decision>[];
  final chapters = <String>{};
  var totalPositions = 0;
  for (final game in games) {
    if (game.headers['Variant'] != null &&
        game.headers['Variant'] != 'Standard')
      throw const FormatException('Only standard chess is supported');
    final site = Uri.tryParse(game.headers['Site'] ?? '');
    final chapter =
        site != null &&
            site.host == 'lichess.org' &&
            site.pathSegments.length >= 3 &&
            site.pathSegments[0] == 'study'
        ? site.pathSegments[2]
        : identity([game.headers['Event'], game.headers['FEN'] ?? 'start']);
    if (chapters.length >= maxPgnChapters)
      throw const InputLimitException('Too many PGN chapters.');
    if (!chapters.add(chapter))
      throw const FormatException(
        'Ambiguous chapter identity: use distinct Event headers',
      );
    final byPosition = <String, (Position, Set<String>)>{};
    final notes = <String, Map<String, Set<String>>>{};
    final glyphs = <String, Map<String, Set<int>>>{};
    final replies = <String, Map<String, Set<String>>>{};
    final context = <String, Set<String>>{};
    final stack = [(game.moves, PgnGame.startingPosition(game.headers))];
    while (stack.isNotEmpty) {
      final (node, pos) = stack.removeLast();
      if (++totalPositions > maxPgnPositions)
        throw const InputLimitException('Too many PGN positions.');
      for (final child in node.children) {
        final move = pos.parseSan(child.data.san);
        if (move == null || !pos.isLegal(move))
          throw FormatException('Illegal SAN: ${child.data.san}');
        if (side == null || pos.turn == side) {
          final key = positionKey(pos);
          byPosition.putIfAbsent(key, () => (pos, <String>{})).$2.add(move.uci);
          final comments = <String>[
            ...child.data.startingComments ?? const [],
            ...child.data.comments ?? const [],
          ];
          notes
              .putIfAbsent(key, () => {})
              .putIfAbsent(move.uci, () => {})
              .addAll(comments);
          glyphs
              .putIfAbsent(key, () => {})
              .putIfAbsent(move.uci, () => {})
              .addAll(child.data.nags ?? const []);
          context
              .putIfAbsent(key, () => {})
              .addAll(
                node is PgnChildNode<PgnNodeData>
                    ? node.data.comments ?? const []
                    : game.comments,
              );
          final next = pos.playUnchecked(move);
          final acceptedReplies = replies
              .putIfAbsent(key, () => {})
              .putIfAbsent(move.uci, () => {});
          for (final continuation in child.children) {
            final reply = next.parseSan(continuation.data.san);
            if (reply == null || !next.isLegal(reply))
              throw FormatException('Illegal SAN: ${continuation.data.san}');
            acceptedReplies.add(reply.uci);
          }
        }
        stack.add((child, pos.playUnchecked(move)));
      }
    }
    for (final entry in byPosition.entries) {
      decisions.add(
        Decision(
          id: identity([source, chapter, entry.value.$1.turn.name, entry.key]),
          source: source,
          chapter: chapter,
          title: game.headers['Event'] ?? 'Chapter',
          fen: entry.value.$1.fen,
          moves: entry.value.$2,
          annotations: {
            for (final e in (notes[entry.key] ?? {}).entries)
              e.key: e.value.toList(),
          },
          glyphs: {
            for (final e in (glyphs[entry.key] ?? {}).entries)
              e.key: e.value.toList()..sort(),
          },
          replies: replies[entry.key] ?? {},
          contextComments: context[entry.key] ?? {},
        ),
      );
    }
  }
  if (decisions.isEmpty)
    throw const FormatException('No trainable moves found');
  return ImportResult(decisions, pgn, complete: side == null);
}

class ReviewState {
  ReviewState(this.card, {this.suspended = false});
  final fsrs.Card card;
  final bool suspended;
  Map<String, Object?> toJson() => {
    'card': card.toMap(),
    'suspended': suspended,
  };
  factory ReviewState.fromJson(Map<String, dynamic> j) {
    final card = fsrs.Card.fromMap(Map<String, dynamic>.from(j['card']));
    final stability = card.stability, difficulty = card.difficulty;
    if ((stability == null) != (difficulty == null) ||
        (stability != null &&
            (!stability.isFinite || stability <= 0 || stability > 1e9)) ||
        (difficulty != null &&
            (!difficulty.isFinite || difficulty < 1 || difficulty > 10)) ||
        (card.state != fsrs.State.learning && stability == null) ||
        (card.step != null && card.step! < 0) ||
        (card.state != fsrs.State.review && card.step == null)) {
      throw const FormatException('Invalid scheduling state');
    }
    return ReviewState(card, suspended: j['suspended'] as bool);
  }
}

class ScheduledReview {
  ScheduledReview(
    this.state,
    this.log, {
    this.session,
    this.previousReview,
    this.decisionRevision,
  });
  final String? decisionRevision;
  final DateTime? previousReview;
  final String? session;
  final ReviewState state;
  final Map<String, dynamic> log;
}

ScheduledReview schedule(
  ReviewState? previous,
  fsrs.Rating rating,
  DateTime now, {
  double retention = .9,
  Decision? decision,
}) {
  if (!retention.isFinite || retention <= 0 || retention >= 1)
    throw ArgumentError.value(
      retention,
      'retention',
      'Must be between zero and one',
    );
  if (previous?.card.lastReview != null &&
      now.toUtc().isBefore(previous!.card.lastReview!))
    throw StateError('Device clock is earlier than the last review');
  final scheduler = fsrs.Scheduler(
    desiredRetention: retention,
    enableFuzzing: false,
  );
  final result = scheduler.reviewCard(
    previous?.card ?? fsrs.Card(cardId: 0, due: now.toUtc()),
    rating,
    reviewDateTime: now.toUtc(),
  );
  return ScheduledReview(
    ReviewState(result.card),
    {...result.reviewLog.toMap(), 'day': reviewDay(now.toLocal())},
    previousReview: previous?.card.lastReview,
    decisionRevision: decision?.revision,
  );
}

void validateReviewLog(Map<String, dynamic> log) {
  fsrs.ReviewLog.fromMap(log);
  if (log['evidence'] != null)
    AttemptEvidence.fromJson(Map<String, dynamic>.from(log['evidence']));
}

class SourceSummary {
  const SourceSummary({required this.id, required this.importedAt});
  final String id;
  final DateTime? importedAt;
}

class SourceSnapshot extends SourceSummary {
  const SourceSnapshot({
    required super.id,
    required super.importedAt,
    required this.pgn,
  });
  final String pgn;
}

abstract interface class TrainerStore {
  Future<List<Decision>> decisions();
  Future<List<SourceSummary>> sources();
  Future<SourceSnapshot?> source(String id);
  Future<Map<String, ReviewState>> states();
  Future<void> replaceSource(String source, ImportResult imported);
  Future<void> review(
    String eventId,
    String decisionId,
    ScheduledReview review,
  );
  Future<List<ReviewEvent>> history({String? day});
  Future<TrainingSession> recordAttempt(
    String sessionToken,
    String decisionId,
    AttemptEvidence evidence,
  );
  Future<String?> setting(String key);
  Future<void> setSetting(String key, String value);
  Future<String> backup();
  Future<void> restore(String json);
}
