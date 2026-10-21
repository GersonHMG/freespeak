import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/pronunciation/pronunciation_result.dart';
import 'package:lingo_node/scoring/difficulty.dart';
import 'package:lingo_node/scoring/score_band.dart';
import 'package:lingo_node/scoring/sentence_score.dart';
import 'package:lingo_node/scoring/session_score.dart';

PronunciationResult _resultAt(int overall, {String spokenText = 'heard'}) =>
    PronunciationResult(
      referenceText: 'reference',
      spokenText: spokenText,
      overall: overall,
      words: const [],
    );

void main() {
  group('ScoreThresholds.bandFor', () {
    const thresholds = ScoreThresholds.standard;

    test('green at and above 80', () {
      expect(thresholds.bandFor(100), ScoreBand.green);
      expect(thresholds.bandFor(80), ScoreBand.green);
    });

    test('orange from 60 up to just under 80', () {
      expect(thresholds.bandFor(79.9), ScoreBand.orange);
      expect(thresholds.bandFor(65), ScoreBand.orange);
      expect(thresholds.bandFor(60), ScoreBand.orange);
    });

    test('red below 60', () {
      expect(thresholds.bandFor(59.9), ScoreBand.red);
      expect(thresholds.bandFor(0), ScoreBand.red);
    });
  });

  group('difficultyForWordCount', () {
    test('easy is 1-8 words', () {
      expect(difficultyForWordCount(1), SentenceDifficulty.easy);
      expect(difficultyForWordCount(8), SentenceDifficulty.easy);
    });

    test('medium is 9-20 words', () {
      expect(difficultyForWordCount(9), SentenceDifficulty.medium);
      expect(difficultyForWordCount(20), SentenceDifficulty.medium);
    });

    test('hard is 21+ words', () {
      expect(difficultyForWordCount(21), SentenceDifficulty.hard);
      expect(difficultyForWordCount(100), SentenceDifficulty.hard);
    });
  });

  group('difficultyOf', () {
    test('counts words the same way the scorer does', () {
      // Irregular whitespace and a hyphenated word both count as expected
      // against phraseWords(), not a naive split(' ').
      expect(difficultyOf('one   two three'), SentenceDifficulty.easy);
      expect(difficultyOf('well-known word'), SentenceDifficulty.easy);
    });

    test('agrees with the boundary at 8 vs 9 words', () {
      const eight = 'one two three four five six seven eight';
      const nine = 'one two three four five six seven eight nine';
      expect(difficultyOf(eight), SentenceDifficulty.easy);
      expect(difficultyOf(nine), SentenceDifficulty.medium);
    });
  });

  group('rateSentence', () {
    test('applies the difficulty multiplier to accuracy', () {
      // 85 * 1.6 = 136
      const hard =
          'one two three four five six seven eight nine ten eleven '
          'twelve thirteen fourteen fifteen sixteen seventeen eighteen '
          'nineteen twenty twentyone';
      final score = rateSentence(_resultAt(85), hard);
      expect(score.difficulty, SentenceDifficulty.hard);
      expect(score.points, 136);
      expect(score.band, ScoreBand.green);
    });

    test('bands the sentence the same way a word would be banded', () {
      final score = rateSentence(_resultAt(65), 'short phrase');
      expect(score.band, ScoreBand.orange);
    });
  });

  group('SessionScore', () {
    test('a first attempt is not decayed', () {
      final session = SessionScore();
      final score = rateSentence(_resultAt(100), 'one two three');
      final outcome = session.record(0, score);
      expect(outcome.attemptNumber, 1);
      expect(outcome.decay, 1.0);
      expect(outcome.award, score.points);
      expect(outcome.sentenceTotal, score.points);
    });

    test('later attempts at the same sentence decay geometrically', () {
      final session = SessionScore();
      final score = rateSentence(_resultAt(100), 'one two three');

      final first = session.record(0, score);
      final second = session.record(0, score);
      final third = session.record(0, score);

      expect(first.decay, 1.0);
      expect(second.decay, closeTo(0.8, 1e-9));
      expect(third.decay, closeTo(0.64, 1e-9));
    });

    test('decay never drops below the floor', () {
      final session = SessionScore(decayFloor: 0.4);
      final score = rateSentence(_resultAt(100), 'one two three');

      AttemptOutcome outcome = session.record(0, score);
      for (var i = 0; i < 10; i++) {
        outcome = session.record(0, score);
      }
      expect(outcome.decay, 0.4);
    });

    test('a sentence total is the sum of every decayed attempt', () {
      final session = SessionScore();
      final score = rateSentence(_resultAt(100), 'one two three');

      final first = session.record(0, score); // 100 * 1.0
      final second = session.record(0, score); // 100 * 0.8

      expect(first.sentenceTotal, 100);
      expect(second.sentenceTotal, 100 + 80);
      expect(session.totalPoints, 180);
    });

    test('different sentences accumulate independently and sum', () {
      final session = SessionScore();
      final a = rateSentence(_resultAt(100), 'one two three');
      final b = rateSentence(_resultAt(50), 'four five six');

      session.record(0, a);
      session.record(1, b);

      expect(session.totalPoints, 100 + 50);
      expect(session.sentencesAttempted, 2);
    });

    test('a retry can only add, never remove, from the total', () {
      final session = SessionScore();
      final good = rateSentence(_resultAt(90), 'one two three');
      final worse = rateSentence(_resultAt(10), 'one two three');

      final first = session.record(0, good);
      final second = session.record(0, worse);

      expect(second.sentenceTotal, greaterThan(first.sentenceTotal));
    });

    test('attemptsFor reports how many times a sentence was tried', () {
      final session = SessionScore();
      final score = rateSentence(_resultAt(100), 'one two three');
      expect(session.attemptsFor(0), 0);
      session.record(0, score);
      session.record(0, score);
      expect(session.attemptsFor(0), 2);
      expect(session.attemptsFor(1), 0);
    });

    test('maxPossible only grows with attempts actually made', () {
      final session = SessionScore();
      final score = rateSentence(_resultAt(100), 'one two three');
      session.record(0, score);
      expect(session.maxPossible, 100);
      session.record(0, score);
      expect(session.maxPossible, 100 + 80);
    });
  });
}
