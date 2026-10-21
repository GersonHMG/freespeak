// Durable, cross-session record of every scored attempt -- separate from
// SessionScore (lib/scoring/session_score.dart), which is deliberately
// in-memory and dies with the practice screen. This is the raw material
// future features (progress charts, spaced repetition, the Mispronounced
// Words menu) read from; SessionScore is only ever about the session that is
// currently running.
//
// Two tables, normalized so a word's text and its phonemes are stored once
// per attempt rather than duplicated across separate "words" and "phonemes"
// feature tables:
//
//   attempts       -- one row per scored recording: the sentence, its word
//                      count, its overall score, and when it happened.
//   word_attempts  -- one row per scored word within an attempt: the word,
//                      its reference IPA, its accuracy, and the good /
//                      mediocre / bad band it fell into.
//
// A "mispronounced phoneme" is read off the same word_attempts row as a
// "mispronounced word" -- both are just (word_attempts.<column>, accuracy)
// for the words that scored badly. There is no per-phoneme accuracy in the
// scoring pipeline yet (that needs an edit-distance backtrace this app
// doesn't have), so reference_ipa is the whole word's phoneme string, not an
// isolated bad phoneme within it.
//
// Every scored word is stored, not just the ones that needed work --
// filtering to "mispronounced" is a query concern (see [mispronouncedWords]),
// so the store stays useful for whatever a future feature wants from the
// words that went well too.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite_lib show databaseFactory;

import '../decks/deck_schema.dart';
import '../pronunciation/category.dart';
import '../pronunciation/phrase_tokens.dart';
import '../pronunciation/pronunciation_result.dart';
import '../scoring/score_band.dart';
import '../scoring/sentence_score.dart';

const String _dbFileName = 'practice_history.db';

/// [ChangeNotifier.notifyListeners] is protected -- this thin subclass is
/// just PracticeHistoryStore's way of calling it from its own write methods.
class _ChangeSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// One word this learner tends to mispronounce, aggregated across every
/// attempt that scored it below [PronunciationCategory.good].
class MispronouncedWord {
  const MispronouncedWord({
    required this.word,
    required this.timesMissed,
    required this.averageAccuracy,
  });

  final String word;

  /// How many attempts scored this word mediocre or bad.
  final int timesMissed;

  /// 0-100, averaged across those attempts.
  final double averageAccuracy;
}

/// One sentence this learner tends to get wrong, aggregated across every
/// attempt whose sentence-level score fell below [ScoreThresholds.green] --
/// the sentence-level analogue of [MispronouncedWord].
class MispronouncedSentence {
  const MispronouncedSentence({
    required this.sentence,
    required this.timesMissed,
    required this.averageAccuracy,
  });

  final String sentence;

  /// How many attempts at this sentence scored below "good".
  final int timesMissed;

  /// 0-100, averaged across those attempts.
  final double averageAccuracy;
}

/// Which screen an attempt came from. Stored on every word_attempts row.
enum AttemptSource {
  /// A sentence from a [SessionScreen] phrase set.
  session,

  /// A single word drilled on [PracticeScreen].
  practice,
}

/// Whole-history totals for the My Progress screen -- the numbers that are
/// one SQL aggregate each. Streaks and per-day points come from
/// [loadDailyActivity] instead; [loadProgressStats] joins the two.
class AttemptSummary {
  const AttemptSummary({
    required this.totalAttempts,
    required this.averageAccuracy,
    required this.wordsScored,
  });

  /// Every recorded attempt, sessions and practice alike.
  final int totalAttempts;

  /// Mean sentence score across [totalAttempts], 0-100. Zero with none.
  final double averageAccuracy;

  /// Distinct words that have been scored at least once, any category.
  final int wordsScored;
}

/// Opens (or creates) the practice history database and writes/reads
/// attempts against it.
///
/// [databaseFactory] defaults to the platform sqflite plugin; a test passes
/// `databaseFactoryFfi` instead so this is exercisable on desktop/CI without
/// a device -- see test/practice_history_store_test.dart.
class PracticeHistoryStore {
  PracticeHistoryStore({DatabaseFactory? databaseFactory, this.path})
    : _factory = databaseFactory ?? sqflite_lib.databaseFactory;

  final DatabaseFactory _factory;

  /// Overrides where the database file lives -- a test passes
  /// [inMemoryDatabasePath]; production leaves this null and gets the
  /// platform's own databases directory.
  final String? path;

  Database? _db;

  // A separate object, not the store itself extending ChangeNotifier -- the
  // store's own dispose() is async (it closes the database), which isn't a
  // valid override of ChangeNotifier's synchronous one.
  final _ChangeSignal _changes = _ChangeSignal();

  /// Fires after any write that changes what a query against this store
  /// would return -- [recordAttempt] and [clearAll] today. A screen showing
  /// derived numbers (the home screen's daily goal and activity, the
  /// mispronounced-words badge) listens to this to know when to re-fetch,
  /// rather than only ever reading the value as of when it first built.
  Listenable get changes => _changes;

  /// Opens the database, creating its schema on first run. Idempotent and
  /// safe to call more than once -- callers that just want to make sure it's
  /// ready (app warm-up) and callers that are about to use it can both call
  /// this without coordinating.
  Future<void> open() async {
    if (_db != null) return;
    final dbPath =
        path ?? p.join(await _factory.getDatabasesPath(), _dbFileName);
    _db = await _factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 11,
        // The flashcard tables cascade deletes from deck to note to card to
        // review, which SQLite only honours with foreign keys switched on --
        // per connection, so it has to happen here rather than once in the
        // schema.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE attempts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER NOT NULL,
              sentence TEXT NOT NULL,
              sentence_length INTEGER NOT NULL,
              sentence_score INTEGER NOT NULL,
              points INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE word_attempts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              attempt_id INTEGER NOT NULL REFERENCES attempts(id),
              word TEXT NOT NULL,
              reference_ipa TEXT NOT NULL,
              accuracy REAL NOT NULL,
              category TEXT NOT NULL,
              source TEXT NOT NULL DEFAULT 'session'
            )
          ''');
          await db.execute(
            'CREATE INDEX word_attempts_word ON word_attempts(word)',
          );
          await createDeckTables(db);
        },
        // v1 -> v2: the daily goal moved from counting sentences to counting
        // points, which needs each attempt's point value on hand. Rows from
        // before this column existed get 0 rather than being backfilled --
        // they've already been counted toward whatever day they happened on
        // and are not worth re-deriving for.
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE attempts ADD COLUMN points INTEGER NOT NULL DEFAULT 0',
            );
          }
          // v2 -> v3: the Practice drill records single-word attempts through
          // the same tables. `source` tells them apart from session attempts
          // ('session' / 'practice') so a future stat can separate the two;
          // every query today treats both alike, on purpose.
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE word_attempts ADD COLUMN source TEXT NOT NULL DEFAULT 'session'",
            );
          }
          // v3 -> v4: `word` is stored bare (see [normalizeWord]). Rows
          // written before this kept the sentence's punctuation and capital,
          // so "Can?", "can" and "can." grouped as three separate words in
          // the mispronounced list and the first two were undrillable. This
          // rewrites them in place rather than leaving a learner's existing
          // history permanently split.
          //
          // Done in Dart, over the distinct words only, so the one definition
          // of "bare" lives in one language -- a SQL TRIM would be a second
          // copy of the punctuation set, free to drift from the first.
          if (oldVersion < 4) {
            final rows = await db.rawQuery(
              'SELECT DISTINCT word FROM word_attempts',
            );
            final batch = db.batch();
            for (final row in rows) {
              final stored = row['word']! as String;
              final bare = normalizeWord(stored);
              if (bare == stored) continue;
              if (bare.isEmpty) {
                batch.delete(
                  'word_attempts',
                  where: 'word = ?',
                  whereArgs: [stored],
                );
              } else {
                batch.update(
                  'word_attempts',
                  {'word': bare},
                  where: 'word = ?',
                  whereArgs: [stored],
                );
              }
            }
            await batch.commit(noResult: true);
          }
          // v4 -> v5: flashcard decks (lib/decks/deck_schema.dart). New
          // tables only; nothing existing changes.
          if (oldVersion < 5) {
            await createDeckTables(db);
          }
          // v5 -> v6: Pronounce cards were removed; only Recall remains.
          // A database created at v5 or earlier may hold some.
          if (oldVersion == 5) {
            await removePronounceCards(db);
          }
          // v6 -> v7: reviews.practice, for custom-session grades. A
          // database older than v5 got the column with its new tables above.
          if (oldVersion >= 5 && oldVersion < 7) {
            await addReviewPracticeColumn(db);
          }
          // v7 -> v8: starter decks renamed "Starter deck".
          if (oldVersion >= 5 && oldVersion < 8) {
            await renameStarterDecks(db);
          }
          // v8 -> v9: decks.icon.
          if (oldVersion >= 5 && oldVersion < 9) {
            await addDeckIconColumn(db);
          }
          // v9 -> v10: decks.color.
          if (oldVersion >= 5 && oldVersion < 10) {
            await addDeckColorColumn(db);
          }
          // v10 -> v11: note_answers.added_by_learner.
          if (oldVersion >= 5 && oldVersion < 11) {
            await addLearnerAnswerColumn(db);
          }
        },
      ),
    );
  }

  Future<Database> get _database async {
    await open();
    return _db!;
  }

  /// The opened database, for DeckStore (lib/decks/deck_store.dart), whose
  /// tables share this file and this store's schema version. Nothing else
  /// should reach past this store's own methods.
  Future<Database> get database => _database;

  /// Persists one scored attempt: the sentence-level row, plus one row per
  /// word in [result.words].
  ///
  /// Callers should only call this for an attempt that actually heard
  /// something -- see [SessionScreen]'s own "nothing heard is a microphone
  /// problem, not a score" reasoning. A silent recording is not a data point
  /// about the learner's pronunciation.
  Future<void> recordAttempt({
    required PronunciationResult result,
    required SentenceScore score,
    AttemptSource source = AttemptSource.session,
    // Off for practice modes meant as low-stakes repetition rather than
    // scoring (see PracticeScreen.awardsPoints / SessionScreen.awardsPoints)
    // -- the attempt is still recorded, for accuracy stats and the
    // mispronounced-word/sentence lists, it just doesn't move the daily
    // goal or streak.
    bool awardsPoints = true,
  }) async {
    final db = await _database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sentenceLength = phraseWords(result.referenceText).length;

    await db.transaction((txn) async {
      final attemptId = await txn.insert('attempts', {
        'timestamp': timestamp,
        'sentence': result.referenceText,
        'sentence_length': sentenceLength,
        'sentence_score': score.accuracy,
        // score.points, not SessionScore's decayed award -- this row is a
        // durable record of the attempt itself, independent of the
        // in-memory session it happened to be made in. See SessionScore's
        // own file header for why the two are kept apart.
        'points': awardsPoints ? score.points : 0,
      });

      final batch = txn.batch();
      for (final word in result.words) {
        // Stored bare: this column is what the mispronounced-words list
        // groups by and what a word drill hands the recognizer as its
        // target, and neither wants the sentence's punctuation along for the
        // ride. See [normalizeWord].
        final bare = normalizeWord(word.word);
        // A token that is nothing but punctuation is not a word to practise.
        if (bare.isEmpty) continue;
        batch.insert('word_attempts', {
          'attempt_id': attemptId,
          'word': bare,
          'reference_ipa': word.referencePhonemes,
          'accuracy': word.accuracy,
          'category': word.category.name,
          'source': source.name,
        });
      }
      await batch.commit(noResult: true);
    });
    _changes.fire();
  }

  /// The words this learner mispronounces most, worst offenders first --
  /// most-missed, then (as a tiebreaker) lowest average accuracy.
  Future<List<MispronouncedWord>> mispronouncedWords({int limit = 50}) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT word, COUNT(*) AS times_missed, AVG(accuracy) AS avg_accuracy
      FROM word_attempts
      WHERE category != ?
      GROUP BY word
      ORDER BY times_missed DESC, avg_accuracy ASC
      LIMIT ?
      ''',
      [PronunciationCategory.good.name, limit],
    );

    return [
      for (final row in rows)
        MispronouncedWord(
          word: row['word']! as String,
          timesMissed: row['times_missed']! as int,
          averageAccuracy: (row['avg_accuracy']! as num).toDouble(),
        ),
    ];
  }

  /// Whether any attempt has ever been recorded. Gates features (Word
  /// Rematch) that need at least one scored attempt before they have
  /// anything -- a missed-word count of zero is ambiguous between "never
  /// played" and "played and did great", and only the first should hide the
  /// feature rather than just saying there's nothing to drill.
  Future<bool> hasAnyAttempts() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM attempts) AS any_row',
    );
    return (rows.first['any_row']! as int) == 1;
  }

  /// How many distinct words currently score mediocre or bad on average --
  /// the number [_MispronouncedWordsCard] badges, without paging in the
  /// full [mispronouncedWords] list just to count it.
  Future<int> mispronouncedWordCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(DISTINCT word) AS count FROM word_attempts '
      'WHERE category != ?',
      [PronunciationCategory.good.name],
    );
    return rows.first['count']! as int;
  }

  /// The sentences this learner gets wrong most, worst offenders first --
  /// most-missed, then (as a tiebreaker) lowest average score. Mirrors
  /// [mispronouncedWords] but off the sentence-level `attempts` table rather
  /// than `word_attempts`.
  Future<List<MispronouncedSentence>> mispronouncedSentences({
    int limit = 50,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT sentence, COUNT(*) AS times_missed, AVG(sentence_score) AS avg_accuracy
      FROM attempts
      WHERE sentence_score < ?
      GROUP BY sentence
      ORDER BY times_missed DESC, avg_accuracy ASC
      LIMIT ?
      ''',
      [ScoreThresholds.standard.green, limit],
    );

    return [
      for (final row in rows)
        MispronouncedSentence(
          sentence: row['sentence']! as String,
          timesMissed: row['times_missed']! as int,
          averageAccuracy: (row['avg_accuracy']! as num).toDouble(),
        ),
    ];
  }

  /// How many distinct sentences currently average below "good" -- the
  /// number the Practice tab's "Revisit sentences" card badges.
  Future<int> mispronouncedSentenceCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(DISTINCT sentence) AS count FROM attempts '
      'WHERE sentence_score < ?',
      [ScoreThresholds.standard.green],
    );
    return rows.first['count']! as int;
  }

  /// Every card read at or after [since], as (which card, when) -- the raw
  /// material [loadDailyActivity] (lib/data/daily_activity.dart) buckets
  /// into the daily goal and streak, counting each card once per day.
  ///
  /// Two kinds of card, keyed apart so they never collide:
  ///
  /// * `sentence:<text>` -- a pronunciation-session attempt that counted
  ///   toward the goal (`points > 0`; the Practice tab's low-stakes attempts
  ///   are recorded with 0 points, see [recordAttempt]'s `awardsPoints`);
  /// * `card:<id>` -- a graded Recall review (the flashcard `reviews` table,
  ///   which shares this database; see lib/decks/deck_schema.dart).
  Future<List<(String card, DateTime at)>> cardReadsSince(
    DateTime since,
  ) async {
    final db = await _database;
    final from = since.millisecondsSinceEpoch;
    final attempts = await db.query(
      'attempts',
      columns: ['sentence', 'timestamp'],
      where: 'points > 0 AND timestamp >= ?',
      whereArgs: [from],
    );
    final reviews = await db.query(
      'reviews',
      columns: ['card_id', 'reviewed_at'],
      where: 'reviewed_at >= ?',
      whereArgs: [from],
    );
    return [
      for (final row in attempts)
        (
          'sentence:${row['sentence']}',
          DateTime.fromMillisecondsSinceEpoch(row['timestamp']! as int),
        ),
      for (final row in reviews)
        (
          'card:${row['card_id']}',
          DateTime.fromMillisecondsSinceEpoch(row['reviewed_at']! as int),
        ),
    ];
  }

  /// The one-aggregate-each totals My Progress shows -- see [AttemptSummary].
  Future<AttemptSummary> attemptSummary() async {
    final db = await _database;
    final attempts = (await db.rawQuery(
      'SELECT COUNT(*) AS count, AVG(sentence_score) AS avg FROM attempts',
    )).first;
    final words = (await db.rawQuery(
      'SELECT COUNT(DISTINCT word) AS count FROM word_attempts',
    )).first;
    return AttemptSummary(
      totalAttempts: attempts['count']! as int,
      // AVG over zero rows is NULL, not 0.
      averageAccuracy: ((attempts['avg'] as num?) ?? 0).toDouble(),
      wordsScored: words['count']! as int,
    );
  }

  /// Sum of every attempt's points ever recorded -- the lifetime total My
  /// Progress shows. The daily goal no longer counts points; it counts cards
  /// (see [cardReadsSince]).
  Future<int> totalPointsEarned() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(points), 0) AS total FROM attempts',
    );
    return rows.first['total']! as int;
  }

  /// Wipes every recorded attempt. Used by the debug menu's "Clear Data"
  /// action -- irreversible, so callers should confirm with the user first.
  Future<void> clearAll() async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('word_attempts');
      await txn.delete('attempts');
    });
    _changes.fire();
  }

  Future<void> dispose() async {
    _changes.dispose();
    await _db?.close();
    _db = null;
  }
}
