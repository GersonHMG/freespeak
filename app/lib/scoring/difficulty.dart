// A sentence's difficulty tier, and the score multiplier it carries.
//
// Word count comes from `phraseWords()` (lib/pronunciation/phrase_tokens.dart)
// -- the one place the app defines what "a word" is -- rather than a naive
// whitespace split, so a sentence lands in the same tier the scorer's word
// list agrees it does even with odd spacing or punctuation-only tokens.

import '../pronunciation/phrase_tokens.dart';

enum SentenceDifficulty {
  /// 1-8 words.
  easy(1.0),

  /// 9-20 words.
  medium(1.3),

  /// 21+ words.
  hard(1.6);

  const SentenceDifficulty(this.multiplier);

  /// Applied to a sentence's accuracy to get its raw point value.
  final double multiplier;
}

/// The tier for a sentence with [wordCount] words.
SentenceDifficulty difficultyForWordCount(int wordCount) {
  if (wordCount <= 8) return SentenceDifficulty.easy;
  if (wordCount <= 20) return SentenceDifficulty.medium;
  return SentenceDifficulty.hard;
}

/// The tier for [sentence], counting words the same way the scorer does.
SentenceDifficulty difficultyOf(String sentence) =>
    difficultyForWordCount(phraseWords(sentence).length);
