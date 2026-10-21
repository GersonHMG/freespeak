// The one place a phrase is split into words.
//
// This exists because two consumers have to agree on what "word 3" means:
// [SpokenText], which renders every token including its trailing whitespace so
// the line reads exactly like the original text, and the scorer, which works on
// bare words. The ported TypeScript split each side its own way (`/(?<=\s)/`
// for rendering, `/\s+/` for scoring), which lines up only for single-spaced
// text with no leading space — and silently misaligns the highlight for
// anything else.
//
// So: one split, two views of it. [PhraseToken.index] is the rendering index,
// and every scored word carries the token index it came from.

/// One piece of a phrase: the raw text as it appears, and its bare word.
class PhraseToken {
  const PhraseToken({
    required this.index,
    required this.raw,
    required this.word,
  });

  /// Position in the full token list, including whitespace-only tokens.
  final int index;

  /// The text verbatim, trailing whitespace included.
  final String raw;

  /// [raw] trimmed. Empty for a whitespace-only token.
  final String word;

  bool get isWord => word.isNotEmpty;
}

/// Splits [text] into tokens, preserving every character.
///
/// Concatenating the [PhraseToken.raw] values reproduces [text] exactly.
List<PhraseToken> tokenizePhrase(String text) {
  // Split after each whitespace run, so a word keeps the space that follows it.
  final pieces = text.split(RegExp(r'(?<=\s)(?!\s)'));
  return [
    for (var i = 0; i < pieces.length; i++)
      PhraseToken(index: i, raw: pieces[i], word: pieces[i].trim()),
  ];
}

/// The speakable words of [text], in order. Whitespace-only tokens dropped.
List<PhraseToken> phraseWords(String text) =>
    tokenizePhrase(text).where((t) => t.isWord).toList(growable: false);

/// Punctuation that clings to a word's edges in running text.
///
/// Only the edges: an apostrophe or hyphen *inside* a word is part of it, and
/// stripping those would turn "it's" into "its" and "moss-covered" into one
/// unpronounceable run.
const String _edgePunctuation =
    r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~¡¿—…«»“”‘’''';

final RegExp _edges = RegExp(
  '^[${RegExp.escape(_edgePunctuation)}]+|'
  '[${RegExp.escape(_edgePunctuation)}]+\$',
);

/// A word reduced to the form worth storing, drilling and grouping by.
///
/// [PhraseToken.word] is the word as it sits in its sentence, punctuation and
/// capital included, which is right for rendering it back and for scoring it
/// in place. It is wrong for everything that treats a word as a thing in its
/// own right: "Book", "book" and "book." are one word to practise, not three,
/// and a drill target of "can?" is worse than cosmetic — it goes into the
/// recognizer's grammar verbatim, and no lexicon has an entry for "can?", so
/// the shortlist can never match and the attempt can only come back unknown.
String normalizeWord(String word) => word.toLowerCase().replaceAll(_edges, '');
