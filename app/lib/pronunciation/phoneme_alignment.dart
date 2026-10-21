// Step 2.5 of the pipeline: lining the whole recording up against the whole
// phrase, in phoneme space, once.
//
// This replaces an older two-level scheme that first matched spoken *words* to
// reference words by letter edit distance, then scored each resulting pair by
// phoneme edit distance. Two distances over two alphabets, and the outer one
// answered the harder question with the worse evidence: it decided which word
// the learner was attempting using spelling, which is precisely the thing
// English does not do reliably. "threw" for "through" looked like a different
// word to it, and a word dropped from the middle of a phrase could not be
// skipped at all, so a real word got shoved into the gap and everything after
// it was credited one slot early.
//
// Here there is one alignment, over one alphabet. Both sides are phonemized
// per word and concatenated into a single sequence, each rune remembering
// which word it came from, and a single edit path is fitted across the whole
// phrase. Word boundaries stop being something the alignment has to respect
// and become something it reports: a deletion is a sound that was not said, an
// insertion is a sound that should not have been, and each is charged to the
// reference word it landed in.
//
// The score formulas do not change — per-word accuracy is still
// (phonemes - mismatches) / phonemes, and the phrase is still the same ratio
// over the sums. What changes is that the mismatches are now counted by one
// global path rather than by n independent per-word comparisons, which is why
// [PhonemeAlignment.totalMismatches] is exactly the edit distance between the
// two full phoneme sequences and not merely a sum of unrelated numbers.

import 'word_metrics.dart';

/// Stress marks. Stripped before scoring: they inflate the phoneme count, and
/// a stress error is a different kind of mistake from a wrong sound — counting
/// it as a substitution would make it cost the same as saying a wrong vowel.
const String _stressMarks = 'ˈˌ';

/// Punctuation the phonemizer passes through verbatim, plus the ASCII the
/// scorer may meet from an ASR transcript. It carries prosody for the
/// synthesizer and nothing for the scorer.
const String _punctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~¡¿—…«»“”‘’''';

/// Everything to drop before two phoneme strings are compared: stress marks,
/// punctuation, and whitespace.
///
/// The `\s` is escaped for the *regex*, not for Dart. Written as `'\s'` in a
/// non-raw string it collapses to a bare `s` before RegExp ever sees it, which
/// builds a class that strips the phoneme /s/ from every word and no
/// whitespace from any of them.
final RegExp _ignored = RegExp(
  '[${RegExp.escape(_stressMarks + _punctuation)}\\s]',
);

/// Reduces IPA to just the sounds, so the distance counts only those.
///
/// Runs per word, before anything is concatenated, and that order is load
/// bearing: this strips whitespace, so normalizing a joined sequence would
/// shift every rune left of its owner and silently mis-attribute the back half
/// of the phrase.
String normalizePhonemes(String phonemes) =>
    phonemes.replaceAll(_ignored, '').toLowerCase();

/// One reference word's share of the phrase-wide alignment.
class AlignedWord {
  const AlignedWord({
    required this.referencePhonemes,
    required this.spokenPhonemes,
    required this.mismatches,
    required this.spokenWordIndices,
  });

  /// The word's own phonemes, normalized — the `p` in the accuracy formula is
  /// this string's rune count.
  final String referencePhonemes;

  /// The stretch of the recording's phonemes that the path put here. Empty
  /// when the word drew nothing at all, which is what "skipped" means now.
  final String spokenPhonemes;

  /// Edits charged to this word: substitutions and deletions inside its own
  /// phonemes, plus any insertions that landed in it.
  final int mismatches;

  /// Which spoken words contributed the phonemes in [spokenPhonemes], in the
  /// order they were heard.
  ///
  /// Usually one. More than one is a boundary error worth reporting rather
  /// than hiding — "a napple" for "an apple" genuinely draws on two heard
  /// words — and it is also what lets a clip be cut for a reference word that
  /// was run together with its neighbour.
  final List<int> spokenWordIndices;

  int get phonemes => referencePhonemes.runes.length;

  /// True when nothing at all was heard for this word.
  bool get wasSkipped => spokenWordIndices.isEmpty;
}

/// A whole phrase, aligned.
class PhonemeAlignment {
  const PhonemeAlignment(this.words);

  /// One entry per reference word, in order.
  final List<AlignedWord> words;

  int get totalPhonemes => words.fold(0, (sum, word) => sum + word.phonemes);

  /// Equal to the edit distance between the two joined phoneme sequences —
  /// every step of the one path is charged to exactly one word, and no word
  /// without phonemes can be charged, so nothing is double counted or lost.
  int get totalMismatches =>
      words.fold(0, (sum, word) => sum + word.mismatches);
}

/// Fits one edit path across the whole phrase and splits it by reference word.
///
/// Both lists are raw IPA, one entry per word, in the order the words occur;
/// [reference] comes from the phrase being practised and [spoken] from the
/// recognizer's transcript. Entries that normalize to nothing — punctuation
/// tokens, or a word the phonemizer has no entry for — take part in neither
/// the path nor the score, and come back with zero phonemes.
PhonemeAlignment alignPhonemes({
  required List<String> reference,
  required List<String> spoken,
}) {
  final referenceSegments = [for (final p in reference) normalizePhonemes(p)];
  final spokenSegments = [for (final p in spoken) normalizePhonemes(p)];

  // Concatenate, remembering which word every rune came from. `owners` only
  // ever names words that actually contributed a phoneme, which is what keeps
  // an insertion from being charged to a word that is excluded from the score.
  final referenceBuffer = StringBuffer();
  final owners = <int>[];
  for (var word = 0; word < referenceSegments.length; word++) {
    for (final rune in referenceSegments[word].runes) {
      referenceBuffer.writeCharCode(rune);
      owners.add(word);
    }
  }

  final spokenBuffer = StringBuffer();
  final speakers = <int>[];
  for (var word = 0; word < spokenSegments.length; word++) {
    for (final rune in spokenSegments[word].runes) {
      spokenBuffer.writeCharCode(rune);
      speakers.add(word);
    }
  }

  final heard = [
    for (var i = 0; i < referenceSegments.length; i++) StringBuffer(),
  ];
  final contributors = [
    for (var i = 0; i < referenceSegments.length; i++) <int>[],
  ];
  final mismatches = List<int>.filled(referenceSegments.length, 0);

  // Nothing to charge anything to. Every word still comes back, scored as the
  // empty thing it is, rather than the caller getting a shorter list than it
  // has words.
  if (owners.isNotEmpty) {
    final spokenCodes = spokenBuffer.toString().runes.toList(growable: false);
    final steps = alignRunes(
      referenceBuffer.toString(),
      spokenBuffer.toString(),
      freeEndGaps: true,
    );

    // How much of the reference the path has consumed. Steps arrive in
    // forward order, so for an insertion — which consumes no reference rune
    // and therefore names no word of its own — this is the boundary it landed
    // on, and `owners[cursor]` is the word about to be spoken into. Mid-word
    // that is the word being said; at a boundary it is the *next* word, which
    // is the convention: a sound added before a word belongs to that word, not
    // to the one that already finished correctly.
    var cursor = 0;

    for (final step in steps) {
      final owner = step.aIndex >= 0
          ? owners[step.aIndex]
          : (cursor < owners.length ? owners[cursor] : owners.last);
      if (step.aIndex >= 0) cursor = step.aIndex + 1;

      if (step.op != EditOp.match) mismatches[owner]++;

      if (step.bIndex >= 0) {
        heard[owner].writeCharCode(spokenCodes[step.bIndex]);
        final speaker = speakers[step.bIndex];
        if (!contributors[owner].contains(speaker)) {
          contributors[owner].add(speaker);
        }
      }
    }
  }

  return PhonemeAlignment([
    for (var i = 0; i < referenceSegments.length; i++)
      AlignedWord(
        referencePhonemes: referenceSegments[i],
        spokenPhonemes: heard[i].toString(),
        mismatches: mismatches[i],
        spokenWordIndices: List<int>.unmodifiable(contributors[i]),
      ),
  ]);
}
