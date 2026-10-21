// Grading one attempt at one sentence: the accuracy already computed by
// [PronunciationResult], read against a colour band and weighted by the
// sentence's difficulty into a point value.
//
// Pure and synchronous -- built from a [PronunciationResult] the pronunciation
// layer already produced, so it is testable with a hand-built result, no mic
// or model required. [SessionScore] is what turns a stream of these into a
// running total across a whole practice session.

import '../pronunciation/pronunciation_result.dart';
import 'difficulty.dart';
import 'score_band.dart';

/// One sentence, one attempt, graded.
class SentenceScore {
  const SentenceScore({
    required this.accuracy,
    required this.band,
    required this.difficulty,
    required this.points,
  });

  /// Whole-sentence accuracy, 0-100 -- the same number
  /// [PronunciationResult.overall] carries.
  final int accuracy;

  final ScoreBand band;

  final SentenceDifficulty difficulty;

  /// `(accuracy * difficulty.multiplier).round()`, before any retry decay
  /// [SessionScore] applies.
  final int points;
}

/// Grades [result] against [sentence]'s difficulty tier.
///
/// [sentence] is the reference text, not [result.referenceText] read back --
/// callers already have it in hand (it is what they asked the learner to
/// say), and passing it explicitly keeps this function from having to trust
/// that [PronunciationResult] round-trips the exact string unchanged.
SentenceScore rateSentence(
  PronunciationResult result,
  String sentence, {
  ScoreThresholds thresholds = ScoreThresholds.standard,
}) {
  final difficulty = difficultyOf(sentence);
  final accuracy = result.overall;
  return SentenceScore(
    accuracy: accuracy,
    band: thresholds.bandFor(accuracy.toDouble()),
    difficulty: difficulty,
    points: (accuracy * difficulty.multiplier).round(),
  );
}
