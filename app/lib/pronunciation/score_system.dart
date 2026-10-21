// Scoring a phrase against what was heard, in phoneme space.
//
// Comparing spellings would punish English for being English ("through" vs
// "threw" is a spelling gulf and a pronunciation match), so both sides go
// through the same G2P first and the distance is measured over phonemes.
//
// That "same G2P" matters more than which one it is. The React Native app used
// @informath/text-to-ipa; here both sides run through the app's existing
// [EspeakPhonemizer], the one the app shows phonemes with. Its exact IPA
// conventions are irrelevant to the score as long as reference and spoken
// share them.
//
// This file no longer decides *who matched whom* — [alignPhonemes] does, once,
// across the whole phrase. What is left here is the arithmetic on top of that
// alignment and the shape the UI reads.

import 'category.dart';
import 'phoneme_alignment.dart';

/// Text in, IPA out. Satisfied by `EspeakPhonemizer.phonemize`.
typedef Grapheme2Phoneme = Future<String> Function(String text);

/// Stands in for a reference word that drew no phonemes at all.
const String wordNotFoundToken = '-';

/// Per-word and whole-phrase accuracy over an alignment.
class PronunciationAccuracy {
  const PronunciationAccuracy({required this.overall, required this.perWord});

  /// 0-100, weighted by phoneme count so long words count for more.
  final int overall;

  /// 0-100 per word, in reference order.
  final List<double> perWord;
}

/// Scores each word by how much of its reference survived.
///
/// A word with no reference phonemes at all — a lexicon miss, or pure
/// punctuation — scores 0 and is left out of the overall, rather than dragging
/// it down for a failure that is the phonemizer's and not the learner's.
///
/// The overall is deliberately not the mean of [PronunciationAccuracy.perWord]:
/// it is one ratio over the phrase's totals, so a mangled short word cannot
/// weigh the same as a mangled long one. Per-word values are clamped and the
/// totals are not, which is why the two can disagree — a word said far longer
/// than the reference is floored at 0 rather than going negative, but the
/// phrase still pays what it cost.
PronunciationAccuracy accuracyOf(PhonemeAlignment alignment) {
  final perWord = <double>[];
  for (final word in alignment.words) {
    final phonemes = word.phonemes;
    if (phonemes == 0) {
      perWord.add(0);
      continue;
    }
    final accuracy = (phonemes - word.mismatches) / phonemes * 100;
    perWord.add(accuracy.clamp(0, 100).toDouble());
  }

  // Nothing scorable — an empty phrase, or one the phonemizer missed entirely.
  // The ported version divided by zero here and returned NaN.
  final totalPhonemes = alignment.totalPhonemes;
  final overall = totalPhonemes == 0
      ? 0
      : ((totalPhonemes - alignment.totalMismatches) / totalPhonemes * 100)
            .clamp(0, 100)
            .round();

  return PronunciationAccuracy(overall: overall, perWord: perWord);
}

/// One reference word, scored: how it was said, and how well.
///
/// Deliberately carries nothing about *where* in a recording the word was
/// said — that is [WordTiming]'s job, computed separately by
/// [mapWordTimings]. A word's accuracy and its audio clip are different
/// questions with different failure modes (a mismatched segment count sinks
/// only the clip, never the score), and this split is what keeps a bug in one
/// from being able to reach the other.
class WordScore {
  const WordScore({
    required this.reference,
    required this.spoken,
    required this.accuracy,
    required this.category,
    required this.referencePhonemes,
    required this.spokenPhonemes,
    required this.letters,
  });

  /// The reference word, verbatim.
  final String reference;

  /// The heard words whose sounds landed on this one, joined by spaces, or
  /// [wordNotFoundToken] if none did.
  ///
  /// More than one word here is not a bug: phoneme alignment can see that a
  /// single reference word was said across a boundary ("a napple" for "an
  /// apple"), which word-to-word matching could only report as something
  /// missing.
  final String spoken;

  /// Percentage of the word's phonemes that survived, 0-100.
  final double accuracy;

  final PronunciationCategory category;

  /// IPA for [reference] and for what was heard in its place, as scored
  /// (normalized).
  final String referencePhonemes;
  final String spokenPhonemes;

  /// One flag per rune of [reference]: true where the letter was heard
  /// correctly.
  final List<bool> letters;

  /// True when nothing at all was heard for this word.
  bool get wasSkipped => spoken == wordNotFoundToken;

  @override
  String toString() =>
      '$reference ${accuracy.round()}% (${category.label}) heard "$spoken"';
}

/// A whole phrase, scored.
class PhraseScore {
  const PhraseScore({required this.overall, required this.words});

  /// Whole-phrase accuracy, 0-100, weighted by phoneme count.
  final int overall;

  /// One [WordScore] per reference word, in order.
  final List<WordScore> words;
}

/// Which heard words a reference word drew its sounds from, as text.
String _heardText(List<int> spokenIndices, List<String> spokenWords) {
  if (spokenIndices.isEmpty) return wordNotFoundToken;
  return [for (final i in spokenIndices) spokenWords[i]].join(' ');
}

/// Scores every reference word against what [alignment] put on it.
///
/// This is "step 3" of the pipeline: given [alignment] (already computed —
/// scoring does not decide who matched whom, only how well), produce a grade
/// for each word. Step 4, timestamp mapping, is [mapWordTimings] — a sibling
/// of this function, not a continuation of it: both read [alignment], neither
/// reads the other's output.
///
/// [spokenWords] is only needed to render what was heard back as text; every
/// number in the result comes from [alignment].
PhraseScore scoreWords(
  List<String> referenceWords,
  List<String> spokenWords,
  PhonemeAlignment alignment,
) {
  final accuracy = accuracyOf(alignment);
  final categories = categoriesForAccuracies(accuracy.perWord);

  final words = <WordScore>[];
  for (var i = 0; i < referenceWords.length; i++) {
    final aligned = alignment.words[i];
    final heard = _heardText(aligned.spokenWordIndices, spokenWords);
    words.add(
      WordScore(
        reference: referenceWords[i],
        spoken: heard,
        accuracy: accuracy.perWord[i],
        category: categories[i],
        referencePhonemes: aligned.referencePhonemes,
        spokenPhonemes: aligned.spokenPhonemes,
        letters: aligned.wasSkipped
            // Nothing was heard, so no letter of it was heard either. The
            // positional comparison would say the same thing, but only by
            // accident of comparing against the sentinel.
            ? List<bool>.filled(referenceWords[i].runes.length, false)
            : lettersTranscribedCorrectly(referenceWords[i], heard),
      ),
    );
  }

  return PhraseScore(overall: accuracy.overall, words: words);
}
