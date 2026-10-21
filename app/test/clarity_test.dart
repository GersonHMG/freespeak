import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/decks/clarity.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/pronunciation/asr.dart';

Transcript _heard(List<(String, double?)> words) => Transcript(
  text: words.map((w) => w.$1).join(' '),
  words: [
    for (final (i, (text, conf)) in words.indexed)
      TimedWord(
        text: text,
        start: Duration(milliseconds: 300 * i),
        end: Duration(milliseconds: 300 * (i + 1)),
        confidence: conf,
      ),
  ],
);

void main() {
  group('clarityOf', () {
    test('is the mean word confidence, as 0-100', () {
      final result = clarityOf(
        _heard([('i', 1.0), ('am', 0.9), ('very', 0.8), ('hungry', 0.5)]),
      )!;
      expect(result.score, 80); // 100 * 3.2 / 4
      expect(result.words.map((w) => w.text), ['i', 'am', 'very', 'hungry']);
    });

    test('flags words below the cut-off as unclear', () {
      final result = clarityOf(
        _heard([('the', 0.95), ('sheep', 0.42), ('sailed', 0.6)]),
      )!;
      // 0.6 itself is clear: the cut-off is "below".
      expect(result.unclearWords.map((w) => w.text), ['sheep']);
    });

    test('takes a custom cut-off', () {
      final result = clarityOf(
        _heard([('the', 0.95), ('sailed', 0.7)]),
        unclearBelow: 0.8,
      )!;
      expect(result.unclearWords.map((w) => w.text), ['sailed']);
    });

    test('is null for an empty transcript, not 0', () {
      expect(clarityOf(const Transcript(text: '')), isNull);
    });

    test('is null when no word carries a confidence', () {
      expect(clarityOf(_heard([('hello', null), ('there', null)])), isNull);
    });

    test('leaves out words without a confidence instead of guessing', () {
      final result = clarityOf(_heard([('hello', 0.7), ('there', null)]))!;
      expect(result.score, 70);
      expect(result.words.map((w) => w.text), ['hello']);
    });

    test('rounds to the nearest whole score', () {
      expect(clarityOf(_heard([('a', 0.333), ('b', 0.333)]))!.score, 33);
      expect(clarityOf(_heard([('a', 0.666), ('b', 0.666)]))!.score, 67);
    });
  });

  group('suggestedGrade', () {
    test('follows the standard bands', () {
      expect(suggestedGrade(100), Grade.easy);
      expect(suggestedGrade(80), Grade.easy);
      expect(suggestedGrade(79), Grade.medium);
      expect(suggestedGrade(60), Grade.medium);
      expect(suggestedGrade(59), Grade.difficult);
      expect(suggestedGrade(0), Grade.difficult);
    });
  });
}
