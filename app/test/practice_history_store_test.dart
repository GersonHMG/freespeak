// PracticeHistoryStore, exercised against the desktop-backed sqflite FFI
// implementation so this runs without a device -- the same reasoning
// mispronounce_detector.dart gives for keeping the recognizer behind an
// interface: the part with a hard platform dependency should not be the part
// that makes everything else untestable.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:path/path.dart' as p;
import 'package:lingo_node/pronunciation/category.dart';
import 'package:lingo_node/pronunciation/pronunciation_result.dart';
import 'package:lingo_node/scoring/difficulty.dart';
import 'package:lingo_node/scoring/score_band.dart';
import 'package:lingo_node/scoring/sentence_score.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ScoredWord _word(
  String word, {
  required double accuracy,
  required PronunciationCategory category,
}) {
  return ScoredWord(
    tokenIndex: 0,
    word: word,
    spoken: word,
    accuracy: accuracy,
    category: category,
    referencePhonemes: word,
    spokenPhonemes: word,
    letters: const [],
  );
}

PronunciationResult _result(String sentence, List<ScoredWord> words) {
  final overall = words.isEmpty
      ? 0
      : (words.map((w) => w.accuracy).reduce((a, b) => a + b) / words.length)
            .round();
  return PronunciationResult(
    referenceText: sentence,
    spokenText: sentence,
    overall: overall,
    words: words,
  );
}

SentenceScore _score(PronunciationResult result) => SentenceScore(
  accuracy: result.overall,
  band: ScoreThresholds.standard.bandFor(result.overall.toDouble()),
  difficulty: SentenceDifficulty.easy,
  points: result.overall,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late PracticeHistoryStore store;

  setUp(() {
    // In-memory and fresh per test -- no file to clean up, and no state
    // leaking between tests.
    store = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => store.dispose());

  test(
    'recordAttempt is invisible to mispronouncedWords for good words',
    () async {
      final result = _result('hello there', [
        _word('hello', accuracy: 95, category: PronunciationCategory.good),
        _word('there', accuracy: 90, category: PronunciationCategory.good),
      ]);

      await store.recordAttempt(result: result, score: _score(result));

      expect(await store.mispronouncedWords(), isEmpty);
      expect(await store.mispronouncedWordCount(), 0);
    },
  );

  test('mispronouncedWords aggregates across attempts, worst first', () async {
    final first = _result('the world is round', [
      _word('the', accuracy: 100, category: PronunciationCategory.good),
      _word('world', accuracy: 40, category: PronunciationCategory.bad),
    ]);
    final second = _result('the world is flat', [
      _word('the', accuracy: 100, category: PronunciationCategory.good),
      _word('world', accuracy: 60, category: PronunciationCategory.bad),
      _word('flat', accuracy: 70, category: PronunciationCategory.mediocre),
    ]);

    await store.recordAttempt(result: first, score: _score(first));
    await store.recordAttempt(result: second, score: _score(second));

    final words = await store.mispronouncedWords();
    expect(words.map((w) => w.word), ['world', 'flat']);

    final world = words.firstWhere((w) => w.word == 'world');
    expect(world.timesMissed, 2);
    expect(world.averageAccuracy, 50); // (40 + 60) / 2

    expect(await store.mispronouncedWordCount(), 2);
  });

  test(
    'words are stored bare, so a punctuated one groups with its own',
    () async {
      // "Can?" and "can" are one word to practise. Grouped by the raw token
      // they were three separate entries, and the punctuated ones could not be
      // drilled at all -- no lexicon has "can?", so the recognizer's shortlist
      // had nothing to match.
      final first = _result('Can you leave.', [
        _word('Can', accuracy: 40, category: PronunciationCategory.bad),
        _word('leave.', accuracy: 50, category: PronunciationCategory.bad),
      ]);
      final second = _result('can we go', [
        _word('can', accuracy: 60, category: PronunciationCategory.bad),
      ]);

      await store.recordAttempt(result: first, score: _score(first));
      await store.recordAttempt(result: second, score: _score(second));

      final words = await store.mispronouncedWords();
      expect(words.map((w) => w.word), ['can', 'leave']);
      expect(words.firstWhere((w) => w.word == 'can').timesMissed, 2);
    },
  );

  test('a token that is only punctuation is not stored as a word', () async {
    final result = _result('wait -- stop', [
      _word('wait', accuracy: 40, category: PronunciationCategory.bad),
      _word('--', accuracy: 0, category: PronunciationCategory.bad),
    ]);

    await store.recordAttempt(result: result, score: _score(result));

    expect((await store.mispronouncedWords()).map((w) => w.word), ['wait']);
  });

  test('attemptSummary is all zeros on an empty store', () async {
    final summary = await store.attemptSummary();

    expect(summary.totalAttempts, 0);
    expect(summary.averageAccuracy, 0);
    expect(summary.wordsScored, 0);
  });

  test(
    'attemptSummary counts attempts, averages scores, dedupes words',
    () async {
      final first = _result('hello world', [
        _word('hello', accuracy: 100, category: PronunciationCategory.good),
        _word('world', accuracy: 60, category: PronunciationCategory.mediocre),
      ]);
      final second = _result('world', [
        _word('world', accuracy: 100, category: PronunciationCategory.good),
      ]);

      await store.recordAttempt(result: first, score: _score(first));
      await store.recordAttempt(
        result: second,
        score: _score(second),
        source: AttemptSource.practice,
      );

      final summary = await store.attemptSummary();
      expect(summary.totalAttempts, 2);
      expect(summary.averageAccuracy, 90); // (80 + 100) / 2
      expect(summary.wordsScored, 2); // hello, world -- not three rows

      // A practice attempt feeds the mispronounced list like any other: the
      // 60 earlier still counts as a miss, the later 100 does not.
      final world = (await store.mispronouncedWords()).single;
      expect(world.word, 'world');
      expect(world.timesMissed, 1);
    },
  );

  test('upgrading rewrites words written before they were stored bare', () async {
    // A v3 database built by hand, the way one already on a learner's phone
    // looks: `word` holds the raw sentence token. Reopening it through the
    // store runs the v3 -> v4 upgrade over it.
    final dir = await Directory.systemTemp.createTemp('lingo_history_test');
    final dbPath = p.join(dir.path, 'history.db');

    final legacy = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE attempts (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'timestamp INTEGER NOT NULL, sentence TEXT NOT NULL, '
            'sentence_length INTEGER NOT NULL, sentence_score INTEGER NOT NULL, '
            'points INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE word_attempts (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'attempt_id INTEGER NOT NULL REFERENCES attempts(id), '
            'word TEXT NOT NULL, reference_ipa TEXT NOT NULL, '
            'accuracy REAL NOT NULL, category TEXT NOT NULL, '
            "source TEXT NOT NULL DEFAULT 'session')",
          );
        },
      ),
    );
    final attemptId = await legacy.insert('attempts', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sentence': 'Can you leave.',
      'sentence_length': 3,
      'sentence_score': 40,
      'points': 0,
    });
    for (final (word, accuracy) in [
      ('Can?', 40.0),
      ('can', 60.0),
      ('--', 0.0),
    ]) {
      await legacy.insert('word_attempts', {
        'attempt_id': attemptId,
        'word': word,
        'reference_ipa': 'x',
        'accuracy': accuracy,
        'category': PronunciationCategory.bad.name,
        'source': 'session',
      });
    }
    await legacy.close();

    final upgraded = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: dbPath,
    );
    addTearDown(() async {
      await upgraded.dispose();
      await dir.delete(recursive: true);
    });

    final words = await upgraded.mispronouncedWords();

    // "Can?" folded into "can" rather than sitting beside it forever, and the
    // punctuation-only row is gone rather than being drillable as "--".
    expect(words.map((w) => w.word), ['can']);
    expect(words.single.timesMissed, 2);
  });

  test('clearAll wipes every recorded attempt', () async {
    final result = _result('flat tire', [
      _word('flat', accuracy: 30, category: PronunciationCategory.bad),
    ]);
    await store.recordAttempt(result: result, score: _score(result));
    expect(await store.mispronouncedWordCount(), 1);

    await store.clearAll();

    expect(await store.mispronouncedWords(), isEmpty);
    expect(await store.mispronouncedWordCount(), 0);
  });

  test('cardReadsSince counts goal attempts and Recall reviews', () async {
    final scored = _result('hello there', [
      _word('hello', accuracy: 90, category: PronunciationCategory.good),
    ]);
    await store.recordAttempt(result: scored, score: _score(scored));
    // A Practice-tab attempt: recorded, but it does not count toward the
    // goal, so it is not a card read.
    final practice = _result('free word', [
      _word('free', accuracy: 90, category: PronunciationCategory.good),
    ]);
    await store.recordAttempt(
      result: practice,
      score: _score(practice),
      awardsPoints: false,
    );

    final decks = DeckStore(store);
    addTearDown(decks.dispose);
    final deckId = await decks.createDeck(name: 'Starter');
    await decks.addNote(deckId: deckId, nativeText: 'Hola', references: ['Hi']);
    final card = (await decks.studyQueue(deckId)).single;
    await decks.recordReview(
      cardId: card.cardId,
      grade: Grade.medium,
      input: AnswerInput.typed,
    );

    final reads = await store.cardReadsSince(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(reads.map((r) => r.$1), [
      'sentence:hello there',
      'card:${card.cardId}',
    ]);
  });

  test('recordAttempt keeps what was heard for each word', () async {
    final result = _result('hello there', [
      _word('hello', accuracy: 95, category: PronunciationCategory.good),
      _word('there', accuracy: 60, category: PronunciationCategory.bad),
    ]);
    await store.recordAttempt(result: result, score: _score(result));

    expect(await store.wordSounds(), [('hello', 'hello'), ('there', 'there')]);
    // Only words since the given time.
    expect(
      await store.wordSounds(
        since: DateTime.now().add(const Duration(days: 1)),
      ),
      isEmpty,
    );
  });

  test('weeklyAccuracy averages each week, oldest first', () async {
    final db = await store.database;
    // A Wednesday, so "this week" started on Monday the 12th.
    final now = DateTime(2026, 10, 14, 12);
    Future<void> attempt(DateTime at, int score) => db.insert('attempts', {
      'timestamp': at.millisecondsSinceEpoch,
      'sentence': 's',
      'sentence_length': 1,
      'sentence_score': score,
    });
    await attempt(DateTime(2026, 10, 13, 9), 80); // this week
    await attempt(DateTime(2026, 10, 12, 9), 90); // this week
    await attempt(DateTime(2026, 9, 30, 9), 60); // two weeks back
    await attempt(DateTime(2026, 8, 1, 9), 10); // before the window

    final weekly = await store.weeklyAccuracy(weeks: 4, now: now);
    expect(weekly, [null, 60, null, 85]);
  });
}
