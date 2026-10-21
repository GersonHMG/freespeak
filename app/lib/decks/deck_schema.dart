// The flashcard tables, added to practice_history.db in schema version 5.
//
// They live in the same file as `attempts` / `word_attempts` rather than a
// database of their own so there is one schema version and one migration
// path to reason about. PracticeHistoryStore owns opening the file and calls
// [createDeckTables] from both onCreate (fresh install) and onUpgrade
// (v4 -> v5); DeckStore (deck_store.dart) reads and writes them.
//
//   decks         -- a named collection of notes, with its language pair
//                    and the icon and colour the learner picked for it
//                    (v9, v10).
//   notes         -- the content: one Spanish prompt, word or sentence.
//   note_answers  -- reference English translations for a note, one per
//                    row. They are examples, not an answer key: Recall never
//                    compares the learner's answer against them. Exactly one
//                    is primary (listed first). `added_by_learner` = 1
//                    for one the learner saved while studying (v11): theirs
//                    to remove, on any deck, starter decks included, and
//                    left alone when the deck's own references are edited.
//   cards         -- one per note (its Recall card), with its schedule.
//   reviews       -- append-only log of every graded review, kept so a
//                    different scheduler can be fitted from it later.
//                    `practice` = 1 for a custom-session grade, which left
//                    the card's schedule alone.
//   deck_meta     -- key/value flags, e.g. that the seed deck was imported,
//                    so deleting it does not bring it back on next launch.
//
// Free practice never touches these tables.

import 'package:sqflite/sqflite.dart';

/// v5 -> v6: Pronounce cards were removed. Deletes them and, by cascade,
/// their reviews. (A v5 database keeps its unused `reviews.pron_score`
/// column; nothing reads or writes it.)
Future<void> removePronounceCards(DatabaseExecutor db) async {
  await db.delete('cards', where: 'mode = ?', whereArgs: ['pronounce']);
}

/// v6 -> v7: custom sessions log their grades without rescheduling, and
/// `reviews.practice` marks those rows so the scheduler's own counts (new
/// cards introduced today) leave them out.
///
/// Checks first rather than assuming: a column added twice is an error, and
/// nothing else guarantees the v5 tables were made without it.
Future<void> addReviewPracticeColumn(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(reviews)');
  if (columns.any((c) => c['name'] == 'practice')) return;
  await db.execute(
    'ALTER TABLE reviews ADD COLUMN practice INTEGER NOT NULL DEFAULT 0',
  );
}

/// v7 -> v8: starter decks were named "<Language> starter"; they are all
/// "Starter deck" now (see kYourLanguage). Renames only bundled ones the
/// learner cannot rename themselves.
Future<void> renameStarterDecks(DatabaseExecutor db) => db.update(
  'decks',
  {'name': 'Starter deck'},
  where: 'source = ?',
  whereArgs: ['starter'],
);

/// v8 -> v9: a deck can carry an icon of the learner's choosing (an emoji;
/// null shows the flag of its language). Checks first, like
/// [addReviewPracticeColumn].
Future<void> addDeckIconColumn(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(decks)');
  if (columns.any((c) => c['name'] == 'icon')) return;
  await db.execute('ALTER TABLE decks ADD COLUMN icon TEXT');
}

/// v9 -> v10: a deck's icon is a line icon on a coloured tile -- `icon` now
/// names the icon (lib/widgets/deck_look.dart) rather than holding an emoji,
/// and `color` names the tile's colour. Null in either is the default.
Future<void> addDeckColorColumn(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(decks)');
  if (columns.any((c) => c['name'] == 'color')) return;
  await db.execute('ALTER TABLE decks ADD COLUMN color TEXT');
}

/// v10 -> v11: `note_answers.added_by_learner`, for ways to say it the
/// learner saved from a Recall card. Checks first, like
/// [addReviewPracticeColumn].
Future<void> addLearnerAnswerColumn(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(note_answers)');
  if (columns.any((c) => c['name'] == 'added_by_learner')) return;
  await db.execute(
    'ALTER TABLE note_answers '
    'ADD COLUMN added_by_learner INTEGER NOT NULL DEFAULT 0',
  );
}

/// Creates every flashcard table and index. Safe only on a database that
/// does not have them yet -- callers are the v5 onCreate / onUpgrade steps.
Future<void> createDeckTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE decks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      native_lang TEXT NOT NULL,
      target_lang TEXT NOT NULL,
      source TEXT NOT NULL DEFAULT 'user',
      new_per_day INTEGER NOT NULL DEFAULT 10,
      created_at INTEGER NOT NULL,
      icon TEXT,
      color TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
      native_text TEXT NOT NULL,
      kind TEXT NOT NULL,
      source_ref TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE note_answers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
      text TEXT NOT NULL,
      is_primary INTEGER NOT NULL DEFAULT 0,
      added_by_learner INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE cards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
      mode TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'new',
      due_at INTEGER,
      interval_days REAL NOT NULL DEFAULT 0,
      ease REAL NOT NULL DEFAULT 2.5,
      reps INTEGER NOT NULL DEFAULT 0,
      lapses INTEGER NOT NULL DEFAULT 0,
      UNIQUE (note_id, mode)
    )
  ''');
  await db.execute('''
    CREATE TABLE reviews (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      card_id INTEGER NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
      reviewed_at INTEGER NOT NULL,
      grade TEXT NOT NULL,
      suggested_grade TEXT,
      input TEXT NOT NULL,
      answer_text TEXT,
      clarity INTEGER,
      practice INTEGER NOT NULL DEFAULT 0,
      interval_before REAL NOT NULL,
      interval_after REAL NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE deck_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX notes_deck ON notes(deck_id)');
  await db.execute('CREATE INDEX note_answers_note ON note_answers(note_id)');
  await db.execute('CREATE INDEX cards_due ON cards(due_at)');
  await db.execute('CREATE INDEX reviews_card ON reviews(card_id)');
}
