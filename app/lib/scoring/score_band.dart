// The single definition of "good enough", shared by word colouring, sentence
// colouring, and the success sound. One threshold set, three consumers —
// changing the cutoff here moves all three at once instead of drifting apart.

/// How well something scored, independent of what produced the number.
enum ScoreBand { green, orange, red }

/// Accuracy cutoffs a [ScoreBand] is read off of.
///
/// `>= green` is green, `>= orange` (and below [green]) is orange, anything
/// lower is red. Boundaries are inclusive on their own side: exactly [green]
/// is green, exactly [orange] is orange.
class ScoreThresholds {
  const ScoreThresholds({this.green = 80, this.orange = 60});

  final double green;
  final double orange;

  ScoreBand bandFor(double accuracy) {
    if (accuracy >= green) return ScoreBand.green;
    if (accuracy >= orange) return ScoreBand.orange;
    return ScoreBand.red;
  }

  /// The app-wide default: 80%+ green, 60-79.99% orange, below 60% red.
  static const ScoreThresholds standard = ScoreThresholds();
}
