// Splits a word's spelling to match its phonemic syllables, so Word Rematch
// can print "how · ev · er" over audio cut at haʊ | ˈɛv | ɚ.
//
// The audio is always cut where the phonemes say; this only chooses labels.
// The phonemic split decides both the count and where each boundary falls
// (how many consonants open the next syllable), and the spelling is fitted to
// it. When the two cannot be made to agree -- vowel letters that are not one
// per syllable, as in "idea" or "lately" -- this gives up and the caller shows
// the IPA instead. A wrong label next to the right audio would teach the
// wrong thing.

import 'syllabifier.dart';

const String _vowelLetters = 'aeiou';

/// Consonant letter pairs that spell one sound, and how many phones each
/// stands for.
const Map<String, int> _digraphs = {
  'ch': 1, 'sh': 1, 'th': 1, 'ph': 1, 'wh': 1, 'ck': 1, 'ng': 1, 'gh': 1,
  'qu': 2, //
};

/// [word] split into one piece per entry of [syllables], or null when its
/// spelling cannot be fitted to them. The pieces join back to [word].
List<String>? spellSyllables(String word, List<PhonemeSyllable> syllables) {
  if (syllables.isEmpty) return null;
  if (syllables.length == 1) return [word];
  final lower = word.toLowerCase();
  if (!RegExp(r'^[a-z]+$').hasMatch(lower)) return null;

  final groups = _vowelGroups(lower);
  _dropSilentE(lower, groups, syllables.length);
  if (groups.length != syllables.length) return null;

  final cuts = <int>[];
  for (var k = 0; k + 1 < groups.length; k++) {
    final from = groups[k].$2;
    final to = groups[k + 1].$1;
    cuts.add(
      from +
          _onsetCut(
            lower,
            from,
            to,
            syllables[k + 1].onset,
            k + 2 == groups.length,
          ),
    );
  }

  final pieces = <String>[];
  var start = 0;
  for (final cut in [...cuts, word.length]) {
    pieces.add(word.substring(start, cut));
    start = cut;
  }
  return pieces;
}

/// Letter ranges `[start, end)` of each run of vowel letters. `y` is a vowel
/// except at the start of the word or before another vowel ("yes", "beyond").
List<(int, int)> _vowelGroups(String w) {
  bool isVowel(int i) {
    final c = w[i];
    if (_vowelLetters.contains(c)) return true;
    if (c != 'y' || i == 0) return false;
    return i + 1 >= w.length || !_vowelLetters.contains(w[i + 1]);
  }

  final groups = <(int, int)>[];
  var i = 0;
  while (i < w.length) {
    if (!isVowel(i)) {
      i++;
      continue;
    }
    final start = i;
    while (i < w.length && isVowel(i)) {
      i++;
    }
    groups.add((start, i));
  }
  return groups;
}

/// Removes a final group that is a silent `e` ("make", "liked", "places"),
/// but only while there are more groups than syllables -- "table"'s `le` and
/// "wanted"'s `ed` are heard, and the phonemic count says so.
void _dropSilentE(String w, List<(int, int)> groups, int syllableCount) {
  if (groups.length <= syllableCount) return;
  final last = groups.last;
  if (last.$2 - last.$1 != 1 || w[last.$1] != 'e') return;
  final atEnd = last.$1 == w.length - 1;
  final beforeSOrD =
      last.$1 == w.length - 2 && (w.endsWith('s') || w.endsWith('d'));
  if (atEnd || beforeSOrD) groups.removeLast();
}

/// Where, within the consonant letters `w[from, to)`, the next syllable
/// starts, given that it opens with [onset] consonant sounds.
int _onsetCut(String w, int from, int to, int onset, bool beforeLast) {
  final cluster = w.substring(from, to);
  if (cluster.isEmpty) return 0;

  // A doubled consonant is split down the middle whatever the sounds say:
  // "bet-ter", "hap-py" (one sound, but the spelling convention is fixed).
  for (var i = 0; i + 1 < cluster.length; i++) {
    if (cluster[i] == cluster[i + 1] && cluster[i] != 'c') return i + 1;
  }

  // Consonant + le at the end ("ta-ble", "sim-ple"): the le's consonant goes
  // with it, though the sound (a syllabic l) has no onset of its own.
  if (beforeLast &&
      w.endsWith('le') &&
      to == w.length - 1 &&
      cluster.endsWith('l')) {
    return cluster.length >= 2 ? cluster.length - 2 : 0;
  }

  // Otherwise take letters from the right until they spell [onset] sounds.
  final units = <(int, int)>[]; // (start within cluster, phones)
  var i = 0;
  while (i < cluster.length) {
    final pair = i + 1 < cluster.length ? cluster.substring(i, i + 2) : '';
    final digraph = _digraphs[pair];
    if (digraph != null) {
      units.add((i, digraph));
      i += 2;
    } else {
      units.add((i, cluster[i] == 'x' ? 2 : 1));
      i++;
    }
  }

  var cut = cluster.length;
  var taken = 0;
  for (var u = units.length - 1; u >= 0; u--) {
    if (taken + units[u].$2 > onset) break;
    taken += units[u].$2;
    cut = units[u].$1;
  }
  return cut;
}
