import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/syllable_cuts.dart';
import 'package:lingo_node/tts/syllabifier.dart';

const int _sr = 24000;

/// Tone bursts at the given spans (ms), silence between them.
Float32List _bursts(List<(int, int)> spans, int totalMs) {
  final pcm = Float32List(_sr * totalMs ~/ 1000);
  for (final (start, end) in spans) {
    for (var i = _sr * start ~/ 1000; i < _sr * end ~/ 1000; i++) {
      pcm[i] = 0.5 * math.sin(2 * math.pi * 220 * i / _sr);
    }
  }
  return pcm;
}

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  group('syllableBoundaries', () {
    test('one syllable is the whole span', () {
      final syllables = syllabify('kˈæt');
      expect(syllables, hasLength(1));
      expect(
        syllableBoundaries(
          _bursts([(0, 300)], 300),
          _sr,
          _ms(0),
          _ms(300),
          syllables,
        ),
        [_ms(0), _ms(300)],
      );
    });

    test('the cut lands in the quiet gap near where it is expected', () {
      // "however": three syllables, voiced 0-200, 260-420 and 480-640 ms.
      final syllables = syllabify('haʊˈɛvɚ');
      expect(syllables, hasLength(3));
      final bounds = syllableBoundaries(
        _bursts([(0, 200), (260, 420), (480, 640)], 640),
        _sr,
        _ms(0),
        _ms(640),
        syllables,
      );
      expect(bounds.first, _ms(0));
      expect(bounds.last, _ms(640));
      expect(bounds[1].inMilliseconds, inInclusiveRange(200, 260));
      expect(bounds[2].inMilliseconds, inInclusiveRange(420, 480));
    });

    test('cuts stay ordered and at least 50 ms apart on a flat signal', () {
      final syllables = syllabify('ˌʌndɚstˈænd');
      final bounds = syllableBoundaries(
        _bursts([(0, 400)], 400),
        _sr,
        _ms(0),
        _ms(400),
        syllables,
      );
      expect(bounds, hasLength(syllables.length + 1));
      for (var i = 1; i < bounds.length; i++) {
        expect(
          (bounds[i] - bounds[i - 1]).inMilliseconds,
          greaterThanOrEqualTo(50),
        );
      }
    });
  });
}
