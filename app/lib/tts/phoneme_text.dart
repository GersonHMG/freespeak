// The punctuation conventions the phoneme string follows.
//
// Small, but load-bearing twice over: punctuation is what splits text into the
// spans eSpeak is asked about, and it is kept in the phoneme string as a
// prosodic boundary. It lives apart from the phonemizer so both rules can be read — and
// tested — without a native library in the way.
//
// This file also held the rewrites that turned eSpeak's IPA into misaki's
// (`eɪ` -> `A`, `ɾ` -> `T`, dropping length marks). Those are gone: the app
// keeps eSpeak's own notation, which is what the React Native version
// shipped.

/// Punctuation that carries prosody, so it is preserved verbatim in the
/// phoneme string rather than phonemized.
const String keptPunctuation = ';:,.!?¡¿—…"«»“”';

/// Brackets. Word boundaries, but not prosody, so they are split on and then
/// dropped from the phoneme string.
///
/// Kept separate from [keptPunctuation] because the difference matters: one
/// set stays in the phoneme string, the other never reaches it.
const String droppedPunctuation = '(){}[]';

/// Everything that ends a word, whether or not it stays in the phonemes.
const String _allPunctuation = '$keptPunctuation$droppedPunctuation';

/// Punctuation runs, except a mark sitting between two digits (the decimal
/// point in `5.99`, which must reach eSpeak's number expansion intact).
final RegExp punctuationRun = RegExp(
  '(?<![0-9])[${RegExp.escape(_allPunctuation)}]+'
  '|[${RegExp.escape(_allPunctuation)}]+(?![0-9])',
);

/// Sentence-final marks that close a phoneme string. All are in
/// [keptPunctuation].
const String terminalPunctuation = '.!?;:…—';

/// Ends [phonemes] on a sentence-final mark, adding a period when it has
/// none, so every phoneme string closes on a boundary.
String withTerminalPunctuation(String phonemes) {
  if (phonemes.isEmpty) return phonemes;
  return terminalPunctuation.contains(phonemes[phonemes.length - 1])
      ? phonemes
      : '$phonemes.';
}
