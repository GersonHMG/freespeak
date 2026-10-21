// Splits one word's eSpeak IPA into syllables, for Word Rematch's slowed,
// syllable-by-syllable playback ("however" -> haʊ · ˈɛv · ɚ).
//
// The syllables are rune ranges over the phoneme string, not new strings, so
// they can be mapped straight onto the model's per-token durations -- that is
// what lets a syllable be cut out of audio that was synthesized as a whole
// word, with no extra inference.
//
// Boundaries follow the Maximal Onset Principle, corrected for stressed short
// vowels. Two things eSpeak's notation decides for us:
//   * stress marks sit immediately before the vowel (`həlˈoʊ`), not at the
//     start of the syllable, so they say which nucleus is stressed and nothing
//     about where the boundary is;
//   * ː and the syllabic mark ̩ attach to the phone before them.

/// How strongly a syllable is stressed.
enum SyllableStress { none, secondary, primary }

/// One syllable: runes `[start, end)` of the phoneme string it came from.
class PhonemeSyllable {
  const PhonemeSyllable({
    required this.start,
    required this.end,
    required this.phonemes,
    required this.stress,
    this.onset = 0,
  });

  final int start;
  final int end;

  /// The syllable's own IPA, stress mark included.
  final String phonemes;
  final SyllableStress stress;

  /// How many consonants come before the nucleus -- what the spelling split
  /// mirrors (see spelling_syllables.dart).
  final int onset;

  @override
  String toString() => phonemes;
}

const int _primary = 0x2C8; // ˈ
const int _secondary = 0x2CC; // ˌ
const int _long = 0x2D0; // ː
const int _halfLong = 0x2D1; // ˑ
const int _syllabic = 0x329; // combining ̩
const int _tie = 0x361; // combining ͡

/// Vowel symbols eSpeak's English voices produce, plus a few neighbours.
final Set<int> _vowels = 'aeiouyæɑɐɒɔəɘɚɛɜɝɞɪʊʌɨʉøœɵɤɯᵻ'.runes.toSet();

/// Vowel pairs spoken as one nucleus. Any other two vowels in a row are two
/// syllables (`aɪɚ`, "fire", is aɪ + ɚ).
const Set<String> _diphthongs = {
  'aɪ', 'aʊ', 'eɪ', 'oʊ', 'ɔɪ', 'əʊ', 'eə', 'ɪə', 'ʊə', 'ɛə', //
};

/// Consonant pairs that are one phone.
const Set<String> _affricates = {'tʃ', 'dʒ'};

/// Short vowels that cannot end a stressed syllable in English, so a stressed
/// one pulls the next consonant into its coda ("ev" in however, "nev" in
/// never).
final Set<String> _lax = {'ɪ', 'ɛ', 'æ', 'ʌ', 'ʊ', 'ɒ'};

/// Clusters English allows at the start of a syllable, beyond any single
/// consonant (which is always allowed, bar [_neverOnset]).
const Set<String> _legalOnsets = {
  // stop/fricative + ɹ
  'pɹ', 'bɹ', 'tɹ', 'dɹ', 'kɹ', 'ɡɹ', 'fɹ', 'θɹ', 'ʃɹ', 'vɹ',
  // + l
  'pl', 'bl', 'kl', 'ɡl', 'fl', 'sl',
  // + w
  'tw', 'dw', 'kw', 'ɡw', 'sw', 'θw', 'hw',
  // s + stop/nasal/f
  'sp', 'st', 'sk', 'sm', 'sn', 'sf',
  // + j
  'pj', 'bj', 'fj', 'vj', 'hj', 'mj', 'kj', 'ɡj', 'nj', 'lj', 'tj', 'dj',
  'sj', 'zj', 'θj',
  // three
  'spl', 'spɹ', 'stɹ', 'skɹ', 'skw', 'spj', 'skj', 'stj',
};

/// Consonants that never begin an English syllable.
const Set<String> _neverOnset = {'ŋ'};

enum _Kind { vowel, consonant, stress, other }

/// A phone, or a stress mark / separator, with the runes it covers.
class _Seg {
  _Seg(this.kind, this.start, this.end, this.text);

  final _Kind kind;
  final int start;
  int end;
  String text;
  bool syllabic = false;

  bool get isNucleus => kind == _Kind.vowel || syllabic;
}

/// Splits [phonemes] (one word's IPA) into syllables that together cover every
/// rune, in order. A string with no vowel comes back as a single syllable.
List<PhonemeSyllable> syllabify(String phonemes) {
  final runes = phonemes.runes.toList();
  if (runes.isEmpty) return const [];
  final segs = _segment(runes);

  final nuclei = [
    for (var i = 0; i < segs.length; i++)
      if (segs[i].isNucleus) i,
  ];
  if (nuclei.length <= 1) {
    return [
      PhonemeSyllable(
        start: 0,
        end: runes.length,
        phonemes: phonemes,
        stress: _stressBefore(segs, nuclei.isEmpty ? segs.length : nuclei[0]),
      ),
    ];
  }

  // Boundary k sits between nucleus k and k+1, as a segment index: the
  // syllable on the right starts at that segment.
  final boundaries = <int>[];
  for (var k = 0; k + 1 < nuclei.length; k++) {
    boundaries.add(_boundary(segs, nuclei[k], nuclei[k + 1]));
  }

  final syllables = <PhonemeSyllable>[];
  var segStart = 0;
  for (var k = 0; k < nuclei.length; k++) {
    final segEnd = k < boundaries.length ? boundaries[k] : segs.length;
    final start = segs[segStart].start;
    final end = segs[segEnd - 1].end;
    syllables.add(
      PhonemeSyllable(
        start: start,
        end: end,
        phonemes: String.fromCharCodes(runes.sublist(start, end)),
        stress: _stressBefore(segs, nuclei[k]),
        onset: [
          for (var i = segStart; i < nuclei[k]; i++)
            if (segs[i].kind == _Kind.consonant) i,
        ].length,
      ),
    );
    segStart = segEnd;
  }
  return syllables;
}

/// The segment index where the syllable after [left]'s nucleus begins.
int _boundary(List<_Seg> segs, int left, int right) {
  // A word boundary inside a single token (`5.99` spoken as several words)
  // is a syllable boundary too, whatever the consonants say.
  for (var i = left + 1; i < right; i++) {
    if (segs[i].kind == _Kind.other) return i + 1;
  }

  final consonants = [
    for (var i = left + 1; i < right; i++)
      if (segs[i].kind == _Kind.consonant) i,
  ];
  if (consonants.isEmpty) return _startOfNucleusGroup(segs, right);

  // Maximal onset: the longest legal tail of the cluster.
  var onsetFrom = consonants.length; // index into [consonants]
  for (var j = 0; j < consonants.length; j++) {
    final tail = consonants.sublist(j).map((i) => segs[i].text).join();
    if (_isLegalOnset(tail, consonants.length - j)) {
      onsetFrom = j;
      break;
    }
  }

  // A stressed short vowel cannot close its syllable: lend it one consonant.
  if (onsetFrom == 0 &&
      _stressBefore(segs, left) != SyllableStress.none &&
      _lax.contains(segs[left].text)) {
    onsetFrom = 1;
  }

  if (onsetFrom >= consonants.length) {
    return _startOfNucleusGroup(segs, right);
  }
  return _startOfNucleusGroup(segs, consonants[onsetFrom]);
}

bool _isLegalOnset(String cluster, int length) {
  if (length == 1) return !_neverOnset.contains(cluster);
  return _legalOnsets.contains(cluster);
}

/// [nucleus], or the stress mark right in front of it, so the mark stays with
/// the syllable it belongs to.
int _startOfNucleusGroup(List<_Seg> segs, int nucleus) {
  var i = nucleus;
  while (i > 0 && segs[i - 1].kind == _Kind.stress) {
    i--;
  }
  return i;
}

SyllableStress _stressBefore(List<_Seg> segs, int nucleus) {
  // The mark is directly before the vowel in eSpeak's notation; searching back
  // over the onset as well covers notations that put it at the syllable start.
  for (var i = nucleus - 1; i >= 0; i--) {
    final seg = segs[i];
    if (seg.isNucleus || seg.kind == _Kind.other) break;
    if (seg.kind == _Kind.stress) {
      return seg.text == 'ˈ'
          ? SyllableStress.primary
          : SyllableStress.secondary;
    }
  }
  return SyllableStress.none;
}

List<_Seg> _segment(List<int> runes) {
  final segs = <_Seg>[];
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    final ch = String.fromCharCode(r);
    final prev = segs.isEmpty ? null : segs.last;

    // Marks that modify the phone before them.
    if (r == _long || r == _halfLong || r == _tie || r == 0x2B0 /* ʰ */ ) {
      if (prev != null && prev.kind != _Kind.other) {
        prev
          ..end = i + 1
          ..text += ch;
        continue;
      }
    }
    if (r == _syllabic) {
      if (prev != null && prev.kind == _Kind.consonant) {
        prev
          ..end = i + 1
          ..text += ch
          ..syllabic = true;
        continue;
      }
    }

    if (r == _primary || r == _secondary) {
      segs.add(_Seg(_Kind.stress, i, i + 1, ch));
      continue;
    }

    if (_vowels.contains(r)) {
      // Second half of a diphthong joins the first.
      if (prev != null &&
          prev.kind == _Kind.vowel &&
          prev.text.runes.length == 1 &&
          _diphthongs.contains(prev.text + ch)) {
        prev
          ..end = i + 1
          ..text += ch;
        continue;
      }
      segs.add(_Seg(_Kind.vowel, i, i + 1, ch));
      continue;
    }

    if (ch.trim().isEmpty || _isPunctuation(r)) {
      segs.add(_Seg(_Kind.other, i, i + 1, ch));
      continue;
    }

    if (prev != null &&
        prev.kind == _Kind.consonant &&
        _affricates.contains(prev.text + ch)) {
      prev
        ..end = i + 1
        ..text += ch;
      continue;
    }
    segs.add(_Seg(_Kind.consonant, i, i + 1, ch));
  }
  return segs;
}

bool _isPunctuation(int r) => ';:,.!?¡¿—…"«»“”-'.runes.contains(r);
