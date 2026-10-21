// The punctuation rules decide two things the audio depends on: where the
// phonemizer splits text into spans, and what the model gets as a prosodic
// boundary. The engine that fills the gaps between them only runs on a phone,
// so this is the part that can be pinned on the host.

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/phoneme_text.dart';

void main() {
  group('punctuationRun', () {
    test('splits on the punctuation it keeps', () {
      expect(
        punctuationRun.allMatches('Hello, world!').map((m) => m[0]),
        <String>[',', '!'],
      );
    });

    test('leaves a decimal point intact for number expansion', () {
      // Split here and eSpeak reads "five" and "ninety nine" as two separate
      // words instead of one figure.
      expect(punctuationRun.allMatches('It costs 5.99').map((m) => m[0]), []);
    });

    test('takes a run of marks in one go', () {
      expect(
        punctuationRun.allMatches('Wait... really?!').map((m) => m[0]),
        <String>['...', '?!'],
      );
    });

    test('splits on brackets too, though the model never sees them', () {
      expect(punctuationRun.allMatches('a (b) c').map((m) => m[0]), <String>[
        '(',
        ')',
      ]);
    });
  });

  group('the two punctuation sets', () {
    test('the two sets do not overlap', () {
      for (final rune in droppedPunctuation.runes) {
        expect(keptPunctuation.contains(String.fromCharCode(rune)), isFalse);
      }
    });
  });

  group('withTerminalPunctuation', () {
    test('gives the model a boundary to land on', () {
      // Without one the final word gets clipped or swallowed outright.
      expect(withTerminalPunctuation('dˈɔɡ'), 'dˈɔɡ.');
    });

    test('leaves an existing one alone', () {
      expect(withTerminalPunctuation('dˈɔɡ?'), 'dˈɔɡ?');
      expect(withTerminalPunctuation('dˈɔɡ…'), 'dˈɔɡ…');
    });

    test('has nothing to add to an empty string', () {
      expect(withTerminalPunctuation(''), '');
    });

    test('every terminal mark is one it recognizes as already final', () {
      for (final mark in terminalPunctuation.split('')) {
        expect(withTerminalPunctuation('x$mark'), 'x$mark');
      }
    });
  });
}
