// The grade a Recall answer pre-selects, from how closely its wording follows
// the card's ways to say it. Method: docs/recall_grade_suggestion.md.
//
// Only a suggestion -- the learner's tap is the grade. A sentence translates
// many ways, so a low match is not proof of a wrong answer: between the
// Partial and Wrong bands the app suggests nothing and leaves it to them.
//
// Both sides are normalized ([answerKey], contractions expanded) and split
// into words. For each reference r, a weighted edit distance D(a, r) aligns
// the answer a with it, where each word w weighs
//
//   c(w) = 0.3 for a function word (the, a, to, I, is...), 1 otherwise
//
// and the edits cost
//
//   insert or delete w        c(w)
//   swap x for y              0.1 if y is x misspelt,
//                             0.5 if they share a root (hunger, hungry),
//                             else max(c(x), c(y))
//
// so a typo or a dropped "the" costs little, another form of the right word
// half, and a different content word a whole one. Normalized by the reference's own weight W(r) = sum of
// c(w) over its words:
//
//   sim(a, r) = max(0, 1 - D(a, r) / W(r)),   s = max over r of sim(a, r)
//
// and s >= 0.9 suggests Perfect, s >= 0.6 Partial, s < 0.3 Wrong.

import 'dart:math' as math;

import 'deck_models.dart';

/// At or above: only typos and small function-word slips -- Perfect.
const double kPerfectFrom = 0.9;

/// At or above (and below [kPerfectFrom]): most of it -- Partial.
const double kPartialFrom = 0.6;

/// Below: next to nothing in common with any way to say it -- Wrong.
const double kWrongBelow = 0.3;

/// The weight of a function word; content words weigh 1.
const double kFunctionWordWeight = 0.3;

/// The cost of a misspelt word, in place of the word it should have been.
const double kTypoCost = 0.1;

/// The cost of another form of the word: "walked" for "walk", "hunger" for
/// "hungry". The right idea in the wrong form, so half a word.
const double kSameRootCost = 0.5;

class AnswerMatch {
  const AnswerMatch({required this.score, required this.referenceIndex});

  /// s, 0-1: how closely the answer follows its closest way to say it.
  final double score;

  /// Which of the given ways to say it that was.
  final int referenceIndex;

  /// The grade [score] pre-selects, or null between the Partial and Wrong
  /// bands, where wording alone cannot tell a wrong answer from a new way
  /// of saying it.
  Grade? get suggestedGrade {
    if (score >= kPerfectFrom) return Grade.easy;
    if (score >= kPartialFrom) return Grade.medium;
    if (score < kWrongBelow) return Grade.difficult;
    return null;
  }
}

/// How closely [answer] follows the closest of [references], or null when
/// there is nothing to compare: no references, or an answer with no words.
AnswerMatch? matchAnswer(String answer, List<String> references) {
  final a = answerWords(answer);
  if (a.isEmpty) return null;
  AnswerMatch? best;
  for (var i = 0; i < references.length; i++) {
    final r = answerWords(references[i]);
    final weight = r.fold(0.0, (sum, w) => sum + wordWeight(w));
    if (weight == 0) continue;
    final score = math.max(0.0, 1 - alignmentCost(a, r) / weight);
    if (best == null || score > best.score) {
      best = AnswerMatch(score: score, referenceIndex: i);
    }
  }
  return best;
}

/// [text] as the words the alignment compares: [answerKey]'s normalization,
/// then contractions spelled out, so "I'm" and "I am" are the same answer.
List<String> answerWords(String text) => [
  for (final word in answerKey(text).split(' '))
    if (word.isNotEmpty) ...expandContraction(word),
];

/// [word] with an English contraction spelled out; anything else as is.
/// A bare 's is only expanded after the pronouns and question words where
/// it can only mean "is" -- "John's" stays a possessive.
List<String> expandContraction(String word) {
  if (_whole[word] case final whole?) return whole;
  for (final (suffix, full) in _suffixes) {
    if (word.length > suffix.length && word.endsWith(suffix)) {
      return [word.substring(0, word.length - suffix.length), full];
    }
  }
  if (word.endsWith("'s")) {
    final stem = word.substring(0, word.length - 2);
    if (_isStems.contains(stem)) return [stem, 'is'];
  }
  return [word];
}

/// Contractions that do not split cleanly at the apostrophe.
const Map<String, List<String>> _whole = {
  "can't": ['can', 'not'],
  "won't": ['will', 'not'],
  "shan't": ['shall', 'not'],
  "ain't": ['is', 'not'],
  "let's": ['let', 'us'],
};

const List<(String, String)> _suffixes = [
  ("n't", 'not'),
  ("'re", 'are'),
  ("'ve", 'have'),
  ("'ll", 'will'),
  ("'m", 'am'),
  ("'d", 'would'),
];

const Set<String> _isStems = {
  'it', 'he', 'she', 'that', 'this', 'there', 'here', 'what', 'where', //
  'who', 'how', 'when', 'why',
};

/// c(w): [kFunctionWordWeight] for a function word, 1 for anything else.
double wordWeight(String word) =>
    _functionWords.contains(word) ? kFunctionWordWeight : 1;

/// Articles, pronouns, auxiliaries, prepositions and conjunctions: the words
/// a translation can drop, add or swap without changing what it says much.
const Set<String> _functionWords = {
  // Articles and determiners.
  'a', 'an', 'the', 'this', 'that', 'these', 'those', 'some', 'any', //
  // Pronouns.
  'i', 'me', 'my', 'you', 'your', 'he', 'him', 'his', 'she', 'her', 'it', //
  'its', 'we', 'us', 'our', 'they', 'them', 'their', //
  // Auxiliaries.
  'am', 'is', 'are', 'was', 'were', 'be', 'been', 'do', 'does', 'did', //
  'have', 'has', 'had', 'will', 'would', 'shall', 'can', 'could', //
  // Prepositions.
  'to', 'of', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'about', //
  'into', 'up', //
  // Conjunctions and the like.
  'and', 'or', 'but', 'so', 'if', 'then', 'very', 'just', 'there',
};

/// D(a, r): the cheapest way to edit [answer] into [reference], word by
/// word, at the costs in this file's header.
double alignmentCost(List<String> answer, List<String> reference) {
  // prev[j]: the cost of turning the answer words so far into the first j
  // reference words.
  var prev = List<double>.filled(reference.length + 1, 0);
  for (var j = 1; j <= reference.length; j++) {
    prev[j] = prev[j - 1] + wordWeight(reference[j - 1]);
  }
  for (final x in answer) {
    final next = List<double>.filled(reference.length + 1, 0);
    next[0] = prev[0] + wordWeight(x);
    for (var j = 1; j <= reference.length; j++) {
      final y = reference[j - 1];
      next[j] = math.min(
        prev[j - 1] + swapCost(x, y),
        math.min(prev[j] + wordWeight(x), next[j - 1] + wordWeight(y)),
      );
    }
    prev = next;
  }
  return prev[reference.length];
}

/// The cost of answering [x] where the reference has [y].
double swapCost(String x, String y) {
  if (x == y) return 0;
  if (isTypo(x, y)) return kTypoCost;
  final different = math.max(wordWeight(x), wordWeight(y));
  return sameRoot(x, y) ? math.min(kSameRootCost, different) : different;
}

/// Whether [x] reads as [y] misspelt: at most one letter off for words of
/// four to seven letters, two for longer ones. Shorter words are left out
/// -- "in" and "on", or "the" and "she", are different words, not typos --
/// and so are two function words, whose swap is a real (if cheap) slip.
bool isTypo(String x, String y) {
  final longer = math.max(x.length, y.length);
  if (longer < 4) return false;
  if (_functionWords.contains(x) && _functionWords.contains(y)) return false;
  final allowed = longer >= 8 ? 2 : 1;
  if ((x.length - y.length).abs() > allowed) return false;
  return _letterDistance(x, y) <= allowed;
}

/// Whether [x] and [y] read as forms of one word: they open with the same
/// four or more letters, and those cover at least 60% of the shorter one.
/// A cheap stand-in for a stemmer -- "walk"/"walking" and "hunger"/"hungry"
/// pass, "went"/"go" and "start"/"stand" do not. It errs on the generous
/// side: "station"/"state" pass too, at half a word rather than a whole one.
bool sameRoot(String x, String y) {
  final shorter = math.min(x.length, y.length);
  var prefix = 0;
  while (prefix < shorter && x[prefix] == y[prefix]) {
    prefix++;
  }
  return prefix >= 4 && prefix >= 0.6 * shorter;
}

/// Plain Levenshtein distance between the letters of [x] and [y].
int _letterDistance(String x, String y) {
  var prev = List<int>.generate(y.length + 1, (j) => j);
  for (var i = 1; i <= x.length; i++) {
    final next = List<int>.filled(y.length + 1, 0);
    next[0] = i;
    for (var j = 1; j <= y.length; j++) {
      final swap = prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1);
      next[j] = math.min(swap, math.min(prev[j], next[j - 1]) + 1);
    }
    prev = next;
  }
  return prev[y.length];
}
