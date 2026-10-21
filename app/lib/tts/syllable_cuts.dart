// Where to cut a spoken word into its syllables, from the audio alone.
//
// The TTS model times words, not phonemes, so syllable boundaries inside a
// word are found in the sound: loudness dips between syllables, because each
// syllable is built around a vowel, its loudest part. A word of K syllables
// (counted from its phonemes) is cut at K - 1 dips of the short-time energy.
//
// Dips also occur inside a syllable, at a stop consonant's closure, so each
// cut is searched for only near where it is expected: the word's span shared
// out by the syllables' phonemes, vowels counting double. Within that window
// the cut goes to the quietest point, with a mild pull toward the expected
// one.

import 'dart:math' as math;
import 'dart:typed_data';

import 'syllabifier.dart';

/// Analysis window and hop for the short-time energy.
const Duration _window = Duration(milliseconds: 20);
const Duration _hop = Duration(milliseconds: 10);

/// No syllable is cut shorter than this.
const Duration _minSyllable = Duration(milliseconds: 50);

/// Half-width of the search window, as a share of the average syllable.
const double _searchShare = 0.4;

/// How much being one search-window away from the expected cut costs, in dB.
const double _priorDb = 6.0;

final Set<int> _vowels = 'aeiouyæɑɐɒɔəɘɚɛɜɝɞɪʊʌɨʉøœɵɤɯᵻ'.runes.toSet();
final Set<int> _marks = 'ˈˌːˑ̩͡'.runes.toSet();

/// The K + 1 boundaries of [syllables] within [start, end] of [pcm]: [start],
/// each cut, then [end].
List<Duration> syllableBoundaries(
  Float32List pcm,
  int sampleRate,
  Duration start,
  Duration end,
  List<PhonemeSyllable> syllables,
) {
  final k = syllables.length;
  if (k <= 1 || end <= start) return [start, end];

  // Expected cuts: the span shared out by phoneme weight.
  final weights = [for (final s in syllables) _weight(s.phonemes)];
  final total = weights.fold<double>(0, (a, b) => a + b);
  final span = (end - start).inMicroseconds;
  final expected = <int>[];
  var acc = 0.0;
  for (var i = 0; i < k - 1; i++) {
    acc += weights[i];
    expected.add(start.inMicroseconds + (span * acc / total).round());
  }

  final energy = _energyDb(pcm, sampleRate);
  final hopUs = _hop.inMicroseconds;
  final halfWindowUs = _window.inMicroseconds ~/ 2;
  int frameAt(int us) => ((us - halfWindowUs) / hopUs).round();
  int timeOf(int frame) => frame * hopUs + halfWindowUs;

  final search = (span / k * _searchShare).round();
  final minGap = _minSyllable.inMicroseconds;
  final cuts = <int>[];
  var floor = start.inMicroseconds + minGap;
  for (var i = 0; i < k - 1; i++) {
    final ceiling = end.inMicroseconds - minGap * (k - 1 - i);
    final lo = math.max(floor, expected[i] - search);
    final hi = math.min(ceiling, expected[i] + search);
    var best = math.min(math.max(expected[i], floor), math.max(floor, ceiling));
    if (lo <= hi && energy.isNotEmpty) {
      var bestCost = double.infinity;
      for (var f = frameAt(lo); f <= frameAt(hi); f++) {
        if (f < 0 || f >= energy.length) continue;
        final t = timeOf(f);
        if (t < lo || t > hi) continue;
        final cost =
            energy[f] +
            _priorDb * (t - expected[i]).abs() / math.max(search, 1);
        if (cost < bestCost) {
          bestCost = cost;
          best = t;
        }
      }
    }
    cuts.add(best);
    floor = best + minGap;
  }

  return [start, for (final c in cuts) Duration(microseconds: c), end];
}

double _weight(String phonemes) {
  var w = 0.0;
  for (final r in phonemes.runes) {
    if (_marks.contains(r)) continue;
    w += _vowels.contains(r) ? 2 : 1;
  }
  return math.max(w, 1);
}

/// Energy in dB per [_hop], over [_window], smoothed over three frames.
List<double> _energyDb(Float32List pcm, int sampleRate) {
  final win = (_window.inMicroseconds * sampleRate / 1e6).round();
  final hop = (_hop.inMicroseconds * sampleRate / 1e6).round();
  if (pcm.length < win || hop == 0) return const [];
  final raw = <double>[];
  for (var i = 0; i + win <= pcm.length; i += hop) {
    var power = 0.0;
    for (var j = i; j < i + win; j++) {
      power += pcm[j] * pcm[j];
    }
    raw.add(10 * math.log(power / win + 1e-12) / math.ln10);
  }
  return [
    for (var i = 0; i < raw.length; i++)
      (raw[math.max(i - 1, 0)] +
              raw[i] +
              raw[math.min(i + 1, raw.length - 1)]) /
          3,
  ];
}
