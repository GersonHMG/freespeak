// Turning a per-word accuracy into something the UI can colour.
//
// The grading itself lives in [ScoreThresholds] (lib/scoring/score_band.dart)
// -- one threshold set shared by word colouring, sentence colouring, and the
// success sound, so moving the cutoff moves all three at once. This file just
// wears the pronunciation layer's own names for the three bands.

import '../scoring/score_band.dart';

/// How well one word was pronounced.
enum PronunciationCategory {
  good,
  mediocre,
  bad;

  /// True for anything the learner should hear again.
  bool get needsWork => this != PronunciationCategory.good;

  String get label => switch (this) {
    PronunciationCategory.good => 'good',
    PronunciationCategory.mediocre => 'mediocre',
    PronunciationCategory.bad => 'bad',
  };
}

PronunciationCategory _fromBand(ScoreBand band) => switch (band) {
  ScoreBand.green => PronunciationCategory.good,
  ScoreBand.orange => PronunciationCategory.mediocre,
  ScoreBand.red => PronunciationCategory.bad,
};

/// The category [ScoreThresholds.standard] assigns to [accuracy]: good at
/// 80%+, mediocre from 60% up to just under 80%, bad below that.
PronunciationCategory categoryForAccuracy(double accuracy) =>
    _fromBand(ScoreThresholds.standard.bandFor(accuracy));

List<PronunciationCategory> categoriesForAccuracies(List<double> accuracies) =>
    accuracies.map(categoryForAccuracy).toList(growable: false);

/// ASCII punctuation, which is never itself mispronounced.
const String _punctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';

/// Which letters of [realWord] survived in [transcribedWord], positionally.
///
/// Deliberately naive — it compares letter i to letter i and nothing more, so
/// a single dropped letter marks the whole tail wrong. That is the ported
/// behaviour, and at word length it reads about right: a word misheard from
/// its third letter on really was wrong from there.
///
/// Returns one flag per rune of [realWord]; true means matched.
List<bool> lettersTranscribedCorrectly(
  String realWord,
  String transcribedWord,
) {
  final real = realWord.toLowerCase().runes.toList(growable: false);
  final heard = transcribedWord.toLowerCase().runes.toList(growable: false);

  return [
    for (var i = 0; i < real.length; i++)
      // Past the end of what was heard, only punctuation still counts.
      (i < heard.length && real[i] == heard[i]) ||
          _punctuation.runes.contains(real[i]),
  ];
}
