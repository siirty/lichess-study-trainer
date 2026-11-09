import 'dart:convert';
import 'dart:math';

import 'trainer_core.dart';

import 'package:dartchess/dartchess.dart';

/// The date recorded at review completion, in the device's current local calendar.
/// Stored dates remain fixed if the user subsequently changes time zone.
String reviewDay(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

class AttemptEvidence {
  const AttemptEvidence({this.hinted = false, this.mistakes = 0});
  final bool hinted;
  final int mistakes;
  Rating get rating => hinted || mistakes > 0 ? Rating.again : Rating.good;
  AttemptEvidence merge(AttemptEvidence other) => AttemptEvidence(
    hinted: hinted || other.hinted,
    mistakes: max(mistakes, other.mistakes),
  );
  Map<String, Object> toJson() => {'hinted': hinted, 'mistakes': mistakes};
  factory AttemptEvidence.fromJson(Map<String, dynamic> j) {
    final mistakes = j['mistakes'] as int;
    if (mistakes < 0) throw const FormatException('Negative mistake count');
    return AttemptEvidence(hinted: j['hinted'] as bool, mistakes: mistakes);
  }
}

class TrainingSession {
  TrainingSession({
    required this.token,
    required Iterable<String> remaining,
    Map<String, AttemptEvidence> attempts = const {},
  }) : remaining = List.unmodifiable(remaining),
       attempts = Map.unmodifiable(attempts) {
    if (token.isEmpty || this.remaining.toSet().length != this.remaining.length)
      throw const FormatException('Invalid session');
  }
  final String token;
  final List<String> remaining;
  final Map<String, AttemptEvidence> attempts;
  String eventId(String id) => identity([token, id]);
  AttemptEvidence evidence(String id) =>
      attempts[id] ?? const AttemptEvidence();
  TrainingSession record(String id, AttemptEvidence evidence) {
    if (remaining.isEmpty || remaining.first != id)
      throw StateError('This decision is no longer active');
    return TrainingSession(
      token: token,
      remaining: remaining,
      attempts: {...attempts, id: this.evidence(id).merge(evidence)},
    );
  }

  TrainingSession advance() => TrainingSession(
    token: token,
    remaining: remaining.skip(1),
    attempts: {
      for (final e in attempts.entries)
        if (e.key != remaining.first) e.key: e.value,
    },
  );
  String encode() => jsonEncode({
    'version': 1,
    'token': token,
    'remaining': remaining,
    'attempts': {for (final e in attempts.entries) e.key: e.value.toJson()},
  });
  factory TrainingSession.decode(String text) {
    final j = jsonDecode(text);
    if (j is List)
      return TrainingSession(
        token: identity(['legacy-session', j]),
        remaining: List<String>.from(j),
      );
    if (j['version'] != 1) throw const FormatException('Unsupported session');
    return TrainingSession(
      token: j['token'] as String,
      remaining: List<String>.from(j['remaining']),
      attempts: {
        for (final e in (j['attempts'] as Map<String, dynamic>).entries)
          e.key: AttemptEvidence.fromJson(Map<String, dynamic>.from(e.value)),
      },
    );
  }
}

class ReviewEvent {
  ReviewEvent({
    required this.id,
    required this.decisionId,
    required this.source,
    required this.chapter,
    required this.at,
    required this.day,
    required this.wasNew,
    required this.rating,
    this.evidence = const AttemptEvidence(),
  });
  final String id, decisionId, source, chapter, day;
  final DateTime at;
  final bool wasNew;
  final Rating rating;
  final AttemptEvidence evidence;
}

class DailyBudget {
  DailyBudget(
    Iterable<ReviewEvent> events, {
    this.newLimit = 20,
    this.reviewLimit = 100,
  }) : introduced = {
         for (final e in events)
           if (e.wasNew) e.decisionId,
       },
       reviewed = {
         for (final e in events)
           if (!e.wasNew) e.decisionId,
       } {
    if (newLimit < 0 || reviewLimit < 0)
      throw ArgumentError('Negative daily limit');
    reviewed.removeAll(introduced);
  }
  final int newLimit, reviewLimit;
  final Set<String> introduced, reviewed;
  int get newRemaining => max(0, newLimit - introduced.length);
  int get reviewRemaining => max(0, reviewLimit - reviewed.length);
  bool allows(String id, {required bool isNew}) =>
      introduced.contains(id) ||
      reviewed.contains(id) ||
      (isNew ? newRemaining > 0 : reviewRemaining > 0);
}

class DailyLimitException implements Exception {
  const DailyLimitException();
  @override
  String toString() =>
      'Daily limit reached. Adjust limits in Settings or continue tomorrow.';
}

/// Pure queue selection; repeated learning steps on today's items do not consume
/// additional unique-item slots. Practice may include future-due positions.
List<Decision> trainingQueue({
  required List<Decision> decisions,
  required Map<String, ReviewState> states,
  required Iterable<ReviewEvent> today,
  Iterable<ReviewEvent>? outcomes,
  required DateTime now,
  int newLimit = 20,
  int reviewLimit = 100,
  bool dueOnly = true,
  bool mistakesOnly = false,
  String? source,
  String? chapter,
  Side? side,
}) {
  final events = today.toList();
  final budget = DailyBudget(
    events,
    newLimit: newLimit,
    reviewLimit: reviewLimit,
  );
  final lastOutcome = <String, ReviewEvent>{};
  // History is ascending; choose by timestamp too so callers need not sort it.
  for (final e in outcomes ?? events) {
    final old = lastOutcome[e.decisionId];
    if (old == null || !old.at.isAfter(e.at)) lastOutcome[e.decisionId] = e;
  }
  final eligible =
      decisions.where((d) {
        final s = states[d.id];
        return !(s?.suspended ?? false) &&
            (side == null || d.side == side) &&
            (source == null || d.source == source) &&
            (chapter == null || d.chapter == chapter) &&
            (!dueOnly || s == null || !s.card.due.isAfter(now)) &&
            (!mistakesOnly || lastOutcome[d.id]?.rating == Rating.again);
      }).toList()..sort((a, b) {
        final sa = states[a.id], sb = states[b.id];
        if (sa == null && sb != null) return 1;
        if (sb == null && sa != null) return -1;
        final c = (sa?.card.due ?? now).compareTo(sb?.card.due ?? now);
        return c == 0 ? a.id.compareTo(b.id) : c;
      });
  var n = budget.newRemaining, r = budget.reviewRemaining;
  return eligible.where((d) {
    if (budget.introduced.contains(d.id) || budget.reviewed.contains(d.id))
      return true;
    return states[d.id] == null ? n-- > 0 : r-- > 0;
  }).toList();
}

class ReviewStatistics {
  ReviewStatistics(Iterable<ReviewEvent> events)
    : events = List.unmodifiable(events);
  final List<ReviewEvent> events;
  int get completed => events.length;
  int get successful => events.where((e) => e.rating != Rating.again).length;
  double? get accuracy => completed == 0 ? null : successful / completed;
  int get hinted => events.where((e) => e.evidence.hinted).length;
  int get mistakes => events.fold(0, (n, e) => n + e.evidence.mistakes);
  Map<String, int> get byDay => {
    for (final day in events.map((e) => e.day).toSet())
      day: events.where((e) => e.day == day).length,
  };
}
