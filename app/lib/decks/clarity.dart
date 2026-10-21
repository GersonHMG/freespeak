// The clarity score for a spoken Recall answer.
//
// Recall never compares the learner's English against stored answers -- a
// sentence translates many ways, and the learner judges the meaning
// themselves. What the app can judge is whether the words came through. For
// a transcript of n words, each with the recognizer's confidence conf(w) in
// [0, 1]:
//
//   clarity = round(100 * (conf(w_1) + ... + conf(w_n)) / n)
//
// It answers "would a listener understand the words you said?" whatever
// words were chosen. Words below [kUnclearBelow] are flagged so the result
// screen can highlight them in the transcript -- the learner sees what was
// heard, so a "sheep" where they meant "ship" shows up there.

import '../pronunciation/asr.dart';
import '../scoring/score_band.dart';
import 'deck_models.dart';

/// A word whose confidence is below this is flagged as unclear.
const double kUnclearBelow = 0.6;

/// One heard word, as the result screen shows it.
class ClarityWord {
  const ClarityWord({
    required this.text,
    required this.confidence,
    required this.unclear,
  });

  final String text;

  /// 0-1, as the recognizer reported it.
  final double confidence;

  /// Below [kUnclearBelow]: highlight it.
  final bool unclear;
}

class ClarityResult {
  const ClarityResult({required this.score, required this.words});

  /// 0-100.
  final int score;

  /// Every heard word, in order.
  final List<ClarityWord> words;

  Iterable<ClarityWord> get unclearWords => words.where((w) => w.unclear);
}

/// The clarity of [transcript], or null when there is nothing to score.
///
/// Null covers an empty transcript (nothing heard: ask to record again, as
/// practice does, rather than scoring 0) and a transcript whose words carry
/// no confidence (a recognizer that does not report it). Words without a
/// confidence are left out of the mean rather than counted as 0 or 1.
ClarityResult? clarityOf(
  Transcript transcript, {
  double unclearBelow = kUnclearBelow,
}) {
  final words = [
    for (final word in transcript.words)
      if (word.confidence case final conf? when word.text.isNotEmpty)
        ClarityWord(
          text: word.text,
          confidence: conf.clamp(0.0, 1.0),
          unclear: conf < unclearBelow,
        ),
  ];
  if (words.isEmpty) return null;

  final mean =
      words.map((w) => w.confidence).reduce((a, b) => a + b) / words.length;
  return ClarityResult(score: (100 * mean).round(), words: words);
}

/// The button a 0-100 clarity [score] pre-selects, read off the app's usual
/// bands: green -> Perfect, orange -> Partial, red -> Wrong. A typed answer
/// has no score and so no suggestion.
Grade suggestedGrade(
  num score, {
  ScoreThresholds thresholds = ScoreThresholds.standard,
}) => switch (thresholds.bandFor(score.toDouble())) {
  ScoreBand.green => Grade.easy,
  ScoreBand.orange => Grade.medium,
  ScoreBand.red => Grade.difficult,
};
