// What the scorer hands back to the UI.

import 'category.dart';
import 'score_system.dart';

/// One reference word, and how well the learner said it.
class ScoredWord {
  const ScoredWord({
    required this.tokenIndex,
    required this.word,
    required this.spoken,
    required this.accuracy,
    required this.category,
    required this.referencePhonemes,
    required this.spokenPhonemes,
    required this.letters,
    this.spokenStart,
    this.spokenEnd,
  });

  /// Index into [tokenizePhrase]'s output for the reference text, so the
  /// rendering and the score refer to the same word.
  final int tokenIndex;

  /// The reference word, verbatim.
  final String word;

  /// The word actually heard here, or [wordNotFoundToken] if it was skipped.
  final String spoken;

  /// Percentage of the word's phonemes that survived, 0-100.
  final double accuracy;

  final PronunciationCategory category;

  /// IPA for [word] and for [spoken], as scored (normalized).
  final String referencePhonemes;
  final String spokenPhonemes;

  /// One flag per rune of [word]: true where the letter was heard correctly.
  final List<bool> letters;

  /// Where [spoken] falls in the learner's recording — [PronunciationResult]'s
  /// [PronunciationResult.recordingPath], specifically. Null when the word was
  /// skipped, or the recognizer's word timing could not be trusted for this
  /// attempt (see [mapWordTimings]). Null means exactly one thing either way:
  /// there is no clip to play back for this word.
  final Duration? spokenStart;
  final Duration? spokenEnd;

  /// Whether tapping this word a second time has something to play. Skipping
  /// straight to "no clip" rather than attempting the cut and catching a
  /// failure is deliberate — a missing time range is an expected, common
  /// outcome (see [spokenStart]), not an error.
  bool get hasSpokenClip => spokenStart != null && spokenEnd != null;

  /// True when nothing at all was heard for this word.
  bool get wasSkipped => spoken == wordNotFoundToken;

  /// True when the word is worth practising again.
  bool get needsWork => category.needsWork || wasSkipped;

  @override
  String toString() =>
      '$word ${accuracy.round()}% (${category.label}) heard "$spoken"';
}

/// A whole attempt at one phrase.
class PronunciationResult {
  const PronunciationResult({
    required this.referenceText,
    required this.spokenText,
    required this.overall,
    required this.words,
    this.recordingPath,
  });

  /// What the learner was asked to say.
  final String referenceText;

  /// What the recognizer heard. Empty if it heard nothing.
  final String spokenText;

  /// Whole-phrase accuracy, 0-100, weighted by phoneme count.
  final int overall;

  /// Every reference word, in order.
  final List<ScoredWord> words;

  /// The WAV [spokenStart]/[spokenEnd] are measured against — the exact file
  /// the recognizer decoded, 16 kHz mono 16-bit PCM. Null when this result
  /// came from [MispronounceDetector.scoreTranscript] directly rather than
  /// from a recording (a unit test, most often), in which case every word's
  /// [ScoredWord.hasSpokenClip] is false regardless of its timing fields.
  final String? recordingPath;

  /// The subset worth practising again.
  List<ScoredWord> get mispronounced =>
      words.where((w) => w.needsWork).toList(growable: false);

  /// Score for the word at [tokenIndex], or null if that token is whitespace.
  ScoredWord? wordAt(int tokenIndex) {
    for (final word in words) {
      if (word.tokenIndex == tokenIndex) return word;
    }
    return null;
  }
}
