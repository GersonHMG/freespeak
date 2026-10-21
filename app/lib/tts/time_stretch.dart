// Slows speech down without changing its pitch, for Word Rematch's syllable
// playback.
//
// The voice is always synthesized at normal speed and the slowing happens
// here, on the finished samples. WSOLA (waveform-similarity overlap-add): the output is
// built from overlapping windowed frames of the input, read at a hop of
// `rate` times the hop they are written at. Each frame is nudged by up to one
// pitch period to wherever it best continues the frame before it, which is
// what keeps the pitch intact -- plain resampling would drop it by the same
// factor as the speed.
//
// Everything here is pure computation on Float32Lists, so it runs in
// compute() and is testable on the host.

import 'dart:math' as math;
import 'dart:typed_data';

/// [samples] played at [rate] times normal speed (below 1 is slower), pitch
/// unchanged. The result is about `samples.length / rate` long.
Float32List timeStretch(
  Float32List samples,
  double rate, {
  required int sampleRate,
}) {
  if (samples.isEmpty || rate == 1.0) return Float32List.fromList(samples);
  assert(rate > 0);

  // ~20 ms frames at 50% overlap, searched over ±10 ms (the longest pitch
  // period of an adult voice).
  final frame = (0.020 * sampleRate).round() & ~1;
  final synthesisHop = frame ~/ 2;
  final analysisHop = rate * synthesisHop;
  final tolerance = (0.010 * sampleRate).round();

  final outLength = (samples.length / rate).ceil();
  final out = Float32List(outLength + frame);
  final weight = Float32List(outLength + frame);

  // Periodic Hann: at 50% overlap the windows sum to exactly one.
  final window = Float32List(frame);
  for (var n = 0; n < frame; n++) {
    window[n] = 0.5 - 0.5 * math.cos(2 * math.pi * n / frame);
  }

  double at(int i) => i >= 0 && i < samples.length ? samples[i] : 0.0;

  var previous = 0;
  for (var k = 0; k * synthesisHop < outLength; k++) {
    var position = 0;
    if (k > 0) {
      // What the previous frame would naturally have continued into.
      final continuation = previous + synthesisHop;
      final nominal = (k * analysisHop).round();
      var best = double.negativeInfinity;
      position = nominal;
      for (var delta = -tolerance; delta <= tolerance; delta++) {
        final candidate = nominal + delta;
        if (candidate < 0) continue;
        var correlation = 0.0;
        var energy = 1e-9;
        for (var n = 0; n < frame; n += 2) {
          final c = at(candidate + n);
          correlation += at(continuation + n) * c;
          energy += c * c;
        }
        final score = correlation / math.sqrt(energy);
        if (score > best) {
          best = score;
          position = candidate;
        }
      }
    }

    final offset = k * synthesisHop;
    for (var n = 0; n < frame; n++) {
      out[offset + n] += at(position + n) * window[n];
      weight[offset + n] += window[n];
    }
    previous = position;
  }

  final result = Float32List(outLength);
  for (var i = 0; i < outLength; i++) {
    // Only the first half-frame has less than full coverage.
    result[i] = weight[i] > 1e-3 ? out[i] / weight[i] : 0.0;
  }
  return result;
}

/// A copy of [samples] faded in and out over [fadeSamples] at each end, so a
/// clip cut out of continuous speech does not click where it was cut.
Float32List fadeEdges(Float32List samples, int fadeSamples) {
  final out = Float32List.fromList(samples);
  final fade = math.min(fadeSamples, out.length ~/ 2);
  for (var i = 0; i < fade; i++) {
    // Raised cosine, 0 -> 1.
    final g = 0.5 - 0.5 * math.cos(math.pi * i / fade);
    out[i] *= g;
    out[out.length - 1 - i] *= g;
  }
  return out;
}

/// [clips] one after another with [gapSamples] of silence between them, and
/// where each clip landed as `[start, end)` sample ranges.
(Float32List, List<(int, int)>) joinWithGaps(
  List<Float32List> clips,
  int gapSamples,
) {
  var total = 0;
  for (final clip in clips) {
    total += clip.length;
  }
  total += gapSamples * math.max(0, clips.length - 1);

  final out = Float32List(total);
  final spans = <(int, int)>[];
  var offset = 0;
  for (var i = 0; i < clips.length; i++) {
    if (i > 0) offset += gapSamples;
    out.setAll(offset, clips[i]);
    spans.add((offset, offset + clips[i].length));
    offset += clips[i].length;
  }
  return (out, spans);
}
