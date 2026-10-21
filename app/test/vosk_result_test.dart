// Vosk's JSON, as the rest of the pipeline is allowed to see it.
//
// The unknown-word token is the whole reason this has a test: it belongs in
// the grammar (so an out-of-list attempt is not forced onto the nearest real
// word) and nowhere past it. Left in, a drill phonemizes the literal text
// "[unk]", scores it against the reference, and shows the learner a confident
// percentage for a token that means "no idea" -- which is exactly what it did.

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/pronunciation/vosk_asr.dart';

String _json(List<(String, double, double)> words) {
  final entries = [
    for (final (text, start, end) in words)
      '{"conf": 1.0, "start": $start, "end": $end, "word": "$text"}',
  ].join(', ');
  return '{"text": "${words.map((w) => w.$1).join(' ')}", '
      '"result": [$entries]}';
}

void main() {
  group('VoskResult.parse', () {
    test('keeps an ordinary result intact', () {
      final result = VoskResult.parse(
        _json([('the', 0.0, 0.5), ('fox', 0.5, 1.0)]),
      );

      expect(result.text, 'the fox');
      expect(result.words.map((w) => w.text), ['the', 'fox']);
    });

    test('keeps each word\'s confidence', () {
      final result = VoskResult.parse(
        '{"text": "the fox", "result": ['
        '{"conf": 0.98, "start": 0.0, "end": 0.5, "word": "the"}, '
        '{"conf": 0.41, "start": 0.5, "end": 1.0, "word": "fox"}]}',
      );

      expect(result.words.map((w) => w.confidence), [0.98, 0.41]);
    });

    test('drops the unknown token from the transcript', () {
      final result = VoskResult.parse(
        _json([('[unk]', 0.0, 0.4), ('[unk]', 0.4, 0.9)]),
      );

      // Not "[unk] [unk]" and not a 33% -- an attempt nobody could make out
      // is nothing to score, and empty is what every caller reads that way.
      expect(result.text, isEmpty);
      expect(result.words, isEmpty);
    });

    test('drops it from both sides at once', () {
      // mapWordTimings refuses to trust any timing when these two counts
      // disagree, so filtering one side alone would silently cost a drill its
      // playback rather than fixing anything.
      final result = VoskResult.parse(
        _json([('beer', 0.0, 0.4), ('[unk]', 0.4, 0.9)]),
      );

      expect(result.text, 'beer');
      expect(result.words.length, result.text.split(' ').length);
      expect(result.words.single.text, 'beer');
    });

    test('leaves a word that merely contains the token alone', () {
      final result = VoskResult.parse(_json([('unknown', 0.0, 0.5)]));

      expect(result.text, 'unknown');
      expect(result.words.single.text, 'unknown');
    });

    test('survives a payload with no result list', () {
      final result = VoskResult.parse('{"text": ""}');

      expect(result.text, isEmpty);
      expect(result.words, isEmpty);
    });

    test('survives unparseable json', () {
      final result = VoskResult.parse('not json');

      expect(result.text, isEmpty);
      expect(result.words, isEmpty);
    });
  });
}
