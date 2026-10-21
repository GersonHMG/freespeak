// Covers the CSV-backed phrase sampler: parsing (quoted lines, the header
// row, blank lines) and that the difficulty ramp -- easy sentences first,
// hard last, drawn at random within each tier -- actually behaves as
// documented.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/sample_sentences.dart';
import 'package:lingo_node/scoring/difficulty.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the default session is the 2/3 easy-to-medium ramp', () async {
    final sentences = await loadSampleSentences();
    expect(sentences, hasLength(5));
    expect(sentences.every((s) => s.isNotEmpty), isTrue);
    // Nothing here should be the literal header text.
    expect(sentences, isNot(contains('sentence')));

    final tiers = sentences.map(difficultyOf).toList();
    expect(tiers, [
      SentenceDifficulty.easy,
      SentenceDifficulty.easy,
      SentenceDifficulty.medium,
      SentenceDifficulty.medium,
      SentenceDifficulty.medium,
    ]);
  });

  test(
    'a custom tierCounts map is ordered by difficulty, not map order',
    () async {
      // Deliberately listed medium-first, easy-last: the result must still
      // come back easy-to-medium, because SentenceDifficulty.values decides
      // the order, not the caller's map.
      final sentences = await loadSampleSentences(
        tierCounts: const {
          SentenceDifficulty.medium: 1,
          SentenceDifficulty.easy: 1,
        },
        random: Random(7),
      );
      expect(sentences, hasLength(2));
      expect(sentences.map(difficultyOf).toList(), [
        SentenceDifficulty.easy,
        SentenceDifficulty.medium,
      ]);
    },
  );

  test('a tier omitted from tierCounts contributes nothing', () async {
    final sentences = await loadSampleSentences(
      tierCounts: const {SentenceDifficulty.medium: 4},
    );
    expect(sentences, hasLength(4));
    expect(
      sentences.every((s) => difficultyOf(s) == SentenceDifficulty.medium),
      isTrue,
    );
  });

  test('unwraps quoted lines rather than keeping the quotes', () async {
    // Pulling every sentence is certain to include the dataset's 14
    // comma-bearing (quoted) ones; a raw '"' surviving into the result would
    // mean the unquoting step regressed.
    final sentences = await loadSampleSentences(
      tierCounts: const {
        SentenceDifficulty.easy: 100000,
        SentenceDifficulty.medium: 100000,
      },
    );
    expect(sentences.any((s) => s.contains(',')), isTrue);
    expect(sentences.any((s) => s.startsWith('"')), isFalse);
  });

  test('a seeded Random gives a reproducible sample', () async {
    final a = await loadSampleSentences(random: Random(42));
    final b = await loadSampleSentences(random: Random(42));
    expect(a, b);
  });

  test('two unseeded samples are not (in practice) identical', () async {
    final a = await loadSampleSentences(
      tierCounts: const {SentenceDifficulty.medium: 20},
    );
    final b = await loadSampleSentences(
      tierCounts: const {SentenceDifficulty.medium: 20},
    );
    expect(a, isNot(equals(b)));
  });

  test('no sentence in the dataset is longer than 12 words', () async {
    final sentences = await loadSampleSentences(
      tierCounts: const {
        SentenceDifficulty.easy: 100000,
        SentenceDifficulty.medium: 100000,
        SentenceDifficulty.hard: 100000,
      },
    );
    expect(sentences, isNotEmpty);
    expect(
      sentences.where((s) => s.split(RegExp(r'\s+')).length > 12),
      isEmpty,
    );
    // So the hard tier (21+ words) is empty by construction.
    expect(
      sentences.map(difficultyOf),
      isNot(contains(SentenceDifficulty.hard)),
    );
  });
}
