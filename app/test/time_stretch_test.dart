import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/time_stretch.dart';

const int _rate = 24000;

Float32List _sine(double hz, double seconds) {
  final n = (seconds * _rate).round();
  return Float32List.fromList([
    for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * hz * i / _rate),
  ]);
}

/// Frequency estimated from upward zero crossings over the middle of [x],
/// away from the edges where the first frame fades in.
double _frequency(Float32List x) {
  final from = x.length ~/ 4;
  final to = x.length * 3 ~/ 4;
  var crossings = 0;
  for (var i = from + 1; i < to; i++) {
    if (x[i - 1] < 0 && x[i] >= 0) crossings++;
  }
  return crossings / ((to - from) / _rate);
}

void main() {
  group('timeStretch', () {
    test('slowing to 0.7 makes it 1/0.7 as long', () {
      final input = _sine(200, 0.5);
      final out = timeStretch(input, 0.7, sampleRate: _rate);
      expect(out.length, (input.length / 0.7).ceil());
    });

    test('keeps the pitch', () {
      final out = timeStretch(_sine(200, 0.5), 0.7, sampleRate: _rate);
      expect(_frequency(out), closeTo(200, 6));
    });

    test('keeps the level', () {
      final out = timeStretch(_sine(200, 0.5), 0.7, sampleRate: _rate);
      var peak = 0.0;
      for (var i = out.length ~/ 4; i < out.length * 3 ~/ 4; i++) {
        peak = math.max(peak, out[i].abs());
      }
      expect(peak, closeTo(0.5, 0.05));
    });

    test('silence stays silent, and rate 1 is a copy', () {
      final silence = Float32List(4800);
      expect(
        timeStretch(silence, 0.7, sampleRate: _rate).every((s) => s == 0),
        isTrue,
      );
      final input = _sine(200, 0.1);
      expect(timeStretch(input, 1.0, sampleRate: _rate), input);
    });
  });

  test('fadeEdges starts and ends at zero, leaves the middle alone', () {
    final input = Float32List.fromList(List.filled(1000, 1.0));
    final out = fadeEdges(input, 120);
    expect(out.first, 0);
    expect(out.last, closeTo(0, 1e-3));
    expect(out[500], 1.0);
  });

  test('joinWithGaps reports where each clip landed', () {
    final (out, spans) = joinWithGaps([
      Float32List.fromList([1, 1]),
      Float32List.fromList([2, 2, 2]),
    ], 4);
    expect(out.length, 2 + 4 + 3);
    expect(spans, [(0, 2), (6, 9)]);
    expect(out.sublist(6), [2, 2, 2]);
  });
}
