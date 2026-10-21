// The running total across a practice session.
//
// A sentence can be attempted more than once (skip back, or land on it again
// after the phrase set wraps), and every attempt adds to that sentence's
// standing total -- retrying is never a way to lose points, only a way to add
// fewer of them. What keeps that from being free farming is decay: each
// further attempt at the same sentence is worth exponentially less,
// `decayRate` per retry down to a `decayFloor`, so a learner chasing a better
// score converges on a ceiling rather than an infinite grind.
//
// Kept separate from [SentenceScore] (which grades one attempt, no memory of
// any other) because "how much has this sentence earned in total" and "how
// well was this attempt said" are different questions -- the first needs
// state across attempts, the second never should.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'sentence_score.dart';

/// What one [SessionScore.record] call did: the attempt's own grade, the
/// decay applied to it, and the sentence's new standing total.
class AttemptOutcome {
  const AttemptOutcome({
    required this.score,
    required this.attemptNumber,
    required this.decay,
    required this.award,
    required this.sentenceTotal,
  });

  /// This attempt's grade, before decay.
  final SentenceScore score;

  /// 1 for a sentence's first attempt this session, 2 for its second, etc.
  final int attemptNumber;

  /// The multiplier applied to [score.points] to get [award] -- 1.0 on the
  /// first attempt, shrinking after.
  final double decay;

  /// `(score.points * decay).round()` -- what this attempt actually added.
  final int award;

  /// This sentence's cumulative total across every attempt so far, [award]
  /// included.
  final int sentenceTotal;
}

/// Accumulates [SentenceScore]s across a practice session.
///
/// Retries are additive but decayed: a sentence's total is the sum of every
/// attempt's award, and award shrinks geometrically with each further
/// attempt at that same sentence (by phrase index) so the total still
/// converges rather than growing without bound.
class SessionScore extends ChangeNotifier {
  SessionScore({this.decayRate = 0.8, this.decayFloor = 0.4})
    : assert(decayRate > 0 && decayRate < 1),
      assert(decayFloor > 0 && decayFloor <= 1);

  /// How much each further attempt at the same sentence is worth, relative
  /// to the one before it.
  final double decayRate;

  /// The decay never drops below this, so a sentence practised many times
  /// still moves the total on every attempt instead of hitting zero.
  final double decayFloor;

  final Map<int, int> _attemptCounts = <int, int>{};
  final Map<int, int> _sentenceTotals = <int, int>{};

  /// The best this session's decay curve could have paid out for the
  /// attempts actually made at each sentence, had every one scored 100% --
  /// the denominator [totalPoints] is measured against.
  final Map<int, int> _sentenceCeilings = <int, int>{};

  /// Records one attempt at the sentence identified by [phraseIndex].
  ///
  /// Call only for an attempt that produced a real score -- a recording the
  /// recognizer heard nothing in should never reach here, or a bad
  /// microphone would burn an attempt (and its decay) for nothing.
  AttemptOutcome record(int phraseIndex, SentenceScore score) {
    final attemptNumber = (_attemptCounts[phraseIndex] ?? 0) + 1;
    _attemptCounts[phraseIndex] = attemptNumber;

    final decay = attemptNumber == 1
        ? 1.0
        : math.max(
            math.pow(decayRate, attemptNumber - 1).toDouble(),
            decayFloor,
          );

    final award = (score.points * decay).round();
    final total = (_sentenceTotals[phraseIndex] ?? 0) + award;
    _sentenceTotals[phraseIndex] = total;

    final ceilingGain = (100 * score.difficulty.multiplier * decay).round();
    _sentenceCeilings[phraseIndex] =
        (_sentenceCeilings[phraseIndex] ?? 0) + ceilingGain;

    notifyListeners();
    return AttemptOutcome(
      score: score,
      attemptNumber: attemptNumber,
      decay: decay,
      award: award,
      sentenceTotal: total,
    );
  }

  /// Sum of every sentence's standing total.
  int get totalPoints => _sentenceTotals.values.fold(0, (a, b) => a + b);

  /// What [totalPoints] would be had every attempt made so far scored a
  /// perfect 100 -- the denominator for a "x / y" display. Grows only as new
  /// attempts are made, not by the size of the phrase set, so it is a
  /// ceiling on what has actually been attempted rather than a session-wide
  /// estimate.
  int get maxPossible => _sentenceCeilings.values.fold(0, (a, b) => a + b);

  /// How many distinct sentences have at least one recorded attempt.
  int get sentencesAttempted => _attemptCounts.length;

  /// How many times [phraseIndex] has been attempted so far, 0 if never.
  int attemptsFor(int phraseIndex) => _attemptCounts[phraseIndex] ?? 0;
}
