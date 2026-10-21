import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/word_align.dart';

Duration _ms(int ms) => Duration(milliseconds: ms);

(String, Duration, Duration) _w(String word, int start, int end) =>
    (word, _ms(start), _ms(end));

void main() {
  group('alignWordTimes', () {
    test(
      'matching words take their own spans, ignoring case and punctuation',
      () {
        final times = alignWordTimes(
          ['Where', 'is', 'the', 'station?'],
          [
            _w('Where', 100, 300),
            _w('is', 300, 500),
            _w('the', 500, 600),
            _w('station', 600, 1200),
          ],
        );
        expect(times, [
          (_ms(100), _ms(300)),
          (_ms(300), _ms(500)),
          (_ms(500), _ms(600)),
          (_ms(600), _ms(1200)),
        ]);
      },
    );

    test('a number read as words takes their combined span', () {
      // "9:30" is read as "nine thirty".
      final times = alignWordTimes(
        ['at', '9:30', 'today'],
        [
          _w('at', 0, 200),
          _w('nine', 200, 500),
          _w('thirty', 500, 900),
          _w('today', 900, 1400),
        ],
      );
      expect(times[1], (_ms(200), _ms(900)));
      expect(times[2], (_ms(900), _ms(1400)));
    });

    test('unmatched target words share the gap by length', () {
      final times = alignWordTimes(
        ['go', 'xx', 'yyyy', 'now'],
        [_w('go', 0, 100), _w('something', 100, 700), _w('now', 700, 900)],
      );
      // 2 and 4 letters share 600 ms: 200 ms and 400 ms.
      expect(times[1], (_ms(100), _ms(300)));
      expect(times[2], (_ms(300), _ms(700)));
    });

    test('a word with nothing spoken for it gets no span', () {
      final times = alignWordTimes(
        ['hello', '—', 'world'],
        [_w('hello', 0, 400), _w('world', 400, 900)],
      );
      expect(times, [(_ms(0), _ms(400)), null, (_ms(400), _ms(900))]);
    });
  });
}
