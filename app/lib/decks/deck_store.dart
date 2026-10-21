// Reads and writes the flashcard tables (deck_schema.dart).
//
// The tables live in practice_history.db, so this store borrows
// PracticeHistoryStore's opened database rather than opening the file a
// second time with a schema version of its own. It never closes it --
// PracticeHistoryStore.dispose does.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/practice_history_store.dart';
import 'deck_models.dart';
import 'languages.dart';
import 'scheduler.dart';
import 'seed_deck.dart';

/// [ChangeNotifier.notifyListeners] is protected; see PracticeHistoryStore's
/// copy of this class for why the store does not extend it directly.
class _ChangeSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Shuffles a list in place. [DeckStore] takes one so a test can keep the
/// queue in a known order.
typedef Shuffler = void Function<T>(List<T> list);

void _randomShuffle<T>(List<T> list) => list.shuffle();

class DeckStore {
  DeckStore(this._history, {Shuffler shuffle = _randomShuffle})
    : _shuffle = shuffle;

  final PracticeHistoryStore _history;
  final Shuffler _shuffle;
  final _ChangeSignal _changes = _ChangeSignal();

  /// Fires after any write: a deck or note added, a review recorded.
  Listenable get changes => _changes;

  Future<Database> get _db => _history.database;

  Future<int> createDeck({
    required String name,
    String nativeLang = kDefaultNativeLang,
    String targetLang = kDefaultTargetLang,
    DeckSource source = DeckSource.user,
    int newPerDay = 10,
    DateTime? now,
  }) async {
    final db = await _db;
    final id = await db.insert('decks', {
      'name': name,
      'native_lang': nativeLang,
      'target_lang': targetLang,
      'source': source.name,
      'new_per_day': newPerDay,
      'created_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
    });
    _changes.fire();
    return id;
  }

  /// A learner setting, kept in `deck_meta` beside the import markers.
  Future<String?> setting(String key) async {
    final db = await _db;
    final rows = await db.query(
      'deck_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['setting:$key'],
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await _db;
    await db.insert('deck_meta', {
      'key': 'setting:$key',
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.fire();
  }

  /// The language the learner said they speak, or null before they were
  /// asked (a first launch, or an install from before the question).
  Future<String?> nativeLanguage() => setting('native_lang');

  /// The deck Home studies: the one chosen with the learner's language,
  /// or, failing that, the first deck there is. Null with no deck at all.
  Future<int?> activeDeckId() async {
    final db = await _db;
    final chosen = int.tryParse(await setting('active_deck') ?? '');
    if (chosen != null) {
      final exists = await db.query(
        'decks',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [chosen],
      );
      if (exists.isNotEmpty) return chosen;
    }
    final first = await db.query(
      'decks',
      columns: ['id'],
      orderBy: 'id',
      limit: 1,
    );
    return first.isEmpty ? null : first.single['id']! as int;
  }

  /// [activeDeckId], or -- with no deck at all -- a new, empty "My cards"
  /// deck in the learner's language, made the active one.
  Future<int> ensureActiveDeckId() async {
    final existing = await activeDeckId();
    if (existing != null) return existing;
    final deckId = await createDeck(
      name: 'My cards',
      nativeLang: await nativeLanguage() ?? kDefaultNativeLang,
    );
    await setSetting('active_deck', '$deckId');
    return deckId;
  }

  /// A deck whose prompts are in [nativeLang] -- the bundled starter one
  /// first, if there is one -- or null.
  Future<int?> deckForLanguage(String nativeLang) async {
    final db = await _db;
    final rows = await db.query(
      'decks',
      columns: ['id'],
      where: 'native_lang = ?',
      whereArgs: [nativeLang],
      orderBy: "source = 'user', id",
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['id']! as int;
  }

  Future<Deck> deck(int deckId) async {
    final db = await _db;
    return Deck.fromRow(
      (await db.query('decks', where: 'id = ?', whereArgs: [deckId])).single,
    );
  }

  /// How many times the learner has given each grade, over every card and
  /// deck, custom sessions included ("I don't know" is a Wrong). Every
  /// grade is present, zero when never given.
  Future<Map<Grade, int>> gradeCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT grade, COUNT(*) AS count FROM reviews GROUP BY grade',
    );
    final counts = {for (final grade in Grade.values) grade: 0};
    for (final row in rows) {
      final grade = Grade.values.asNameMap()[row['grade']];
      if (grade != null) counts[grade] = row['count']! as int;
    }
    return counts;
  }

  /// Every card graded at least once, across all decks, most recently
  /// practised first: what [gradeCounts] adds up, card by card.
  Future<List<PractisedCard>> practisedCards() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        c.id AS card_id,
        n.native_text,
        (SELECT a.text FROM note_answers a WHERE a.note_id = n.id
         ORDER BY a.is_primary DESC, a.id LIMIT 1) AS reference,
        SUM(r.grade = 'difficult') AS difficult,
        SUM(r.grade = 'medium') AS medium,
        SUM(r.grade = 'easy') AS easy,
        MAX(r.reviewed_at) AS last_at,
        (SELECT r2.grade FROM reviews r2 WHERE r2.card_id = c.id
         ORDER BY r2.reviewed_at DESC, r2.id DESC LIMIT 1) AS last_grade
      FROM reviews r
      JOIN cards c ON c.id = r.card_id
      JOIN notes n ON n.id = c.note_id
      GROUP BY c.id
      ORDER BY last_at DESC, c.id DESC
    ''');
    return [
      for (final row in rows)
        PractisedCard(
          cardId: row['card_id']! as int,
          nativeText: row['native_text']! as String,
          reference: (row['reference'] as String?) ?? '',
          grades: {
            for (final grade in Grade.values)
              grade: (row[grade.name] as int?) ?? 0,
          },
          lastGrade: Grade.values.byName(row['last_grade']! as String),
          lastPractised: DateTime.fromMillisecondsSinceEpoch(
            row['last_at']! as int,
          ),
        ),
    ];
  }

  /// Deletes everything the learner has: every deck, card and grade, every
  /// setting (their language included, so the app asks it again), and --
  /// through [PracticeHistoryStore.clearAll] -- every pronunciation attempt.
  /// The bundled starter decks come back when a language is chosen again,
  /// as on a first launch. Irreversible: Settings asks the learner to type
  /// "delete" first.
  Future<void> deleteAllData() async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final table in [
        'reviews',
        'cards',
        'note_answers',
        'notes',
        'decks',
        'deck_meta',
      ]) {
        await txn.delete(table);
      }
    });
    await _history.clearAll();
    _changes.fire();
  }

  /// Every deck with its card count, today's due count and how its graded
  /// cards stand (custom sessions included), oldest first.
  Future<List<DeckSummary>> deckSummaries({DateTime? now}) async {
    final db = await _db;
    final counts = {
      for (final row in await db.rawQuery('''
        SELECT n.deck_id, COUNT(*) AS cards
        FROM cards c JOIN notes n ON n.id = c.note_id
        GROUP BY n.deck_id
      '''))
        row['deck_id']! as int: row['cards']! as int,
    };
    final graded = {
      for (final row in await db.rawQuery('''
        SELECT n.deck_id,
               COUNT(*) AS shown,
               SUM(g.last_grade = 'easy') AS perfect
        FROM (
          SELECT c.note_id,
                 (SELECT r.grade FROM reviews r WHERE r.card_id = c.id
                  ORDER BY r.reviewed_at DESC, r.id DESC LIMIT 1) AS last_grade
          FROM cards c
          WHERE EXISTS (SELECT 1 FROM reviews r WHERE r.card_id = c.id)
        ) g
        JOIN notes n ON n.id = g.note_id
        GROUP BY n.deck_id
      '''))
        row['deck_id']! as int: (
          row['shown']! as int,
          (row['perfect'] as int?) ?? 0,
        ),
    };
    return [
      for (final deck in await decks())
        DeckSummary(
          deck: deck,
          cardCount: counts[deck.id] ?? 0,
          dueCount: (await studyQueue(deck.id, now: now)).length,
          shownCount: graded[deck.id]?.$1 ?? 0,
          perfectCount: graded[deck.id]?.$2 ?? 0,
        ),
    ];
  }

  Future<void> renameDeck(int deckId, String name) async {
    final db = await _db;
    await db.update(
      'decks',
      {'name': name},
      where: 'id = ?',
      whereArgs: [deckId],
    );
    _changes.fire();
  }

  Future<void> setNewPerDay(int deckId, int newPerDay) async {
    final db = await _db;
    await db.update(
      'decks',
      {'new_per_day': newPerDay},
      where: 'id = ?',
      whereArgs: [deckId],
    );
    _changes.fire();
  }

  /// Sets the deck's icon and tile colour, by name; null is the default.
  /// Any deck, starter ones included -- how a deck looks in the list is the
  /// learner's, even when its cards are not.
  Future<void> setDeckLook(
    int deckId, {
    required String? icon,
    required String? color,
  }) async {
    final db = await _db;
    await db.update(
      'decks',
      {'icon': icon, 'color': color},
      where: 'id = ?',
      whereArgs: [deckId],
    );
    _changes.fire();
  }

  /// Deletes the deck with all its cards and their history (the schema
  /// cascades). Only the learner's own decks: see [Deck.isEditable].
  Future<void> deleteDeck(int deckId) async {
    final db = await _db;
    await db.delete('decks', where: 'id = ?', whereArgs: [deckId]);
    _changes.fire();
  }

  /// Rewrites a note's prompt and references in place. Its card keeps its
  /// schedule and history: correcting a card's wording is not a new card.
  Future<void> updateNote(
    int noteId, {
    required String nativeText,
    required List<String> references,
  }) async {
    if (references.isEmpty) {
      throw ArgumentError.value(references, 'references', 'needs at least one');
    }
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'notes',
        {'native_text': nativeText},
        where: 'id = ?',
        whereArgs: [noteId],
      );
      // The deck's own references only: what the learner saved while
      // studying is not part of this form and stays.
      await txn.delete(
        'note_answers',
        where: 'note_id = ? AND added_by_learner = 0',
        whereArgs: [noteId],
      );
      final batch = txn.batch();
      for (final (i, reference) in references.indexed) {
        batch.insert('note_answers', {
          'note_id': noteId,
          'text': reference,
          'is_primary': i == 0 ? 1 : 0,
        });
      }
      await batch.commit(noResult: true);
    });
    _changes.fire();
  }

  /// Saves [text] as another way to say [noteId]'s prompt, the learner's
  /// own -- on any deck, a starter deck's included. Returns false, saving
  /// nothing, when it is blank or the note already has it (see [answerKey]).
  Future<bool> addOwnReference(int noteId, String text) async {
    final key = answerKey(text);
    if (key.isEmpty) return false;
    final db = await _db;
    final added = await db.transaction((txn) async {
      final existing = await txn.query(
        'note_answers',
        columns: ['text'],
        where: 'note_id = ?',
        whereArgs: [noteId],
      );
      if (existing.any((row) => answerKey(row['text']! as String) == key)) {
        return false;
      }
      await txn.insert('note_answers', {
        'note_id': noteId,
        'text': text.trim(),
        'is_primary': 0,
        'added_by_learner': 1,
      });
      return true;
    });
    if (added) _changes.fire();
    return added;
  }

  /// Removes one of the learner's own ways to say [noteId]'s prompt. The
  /// deck's references cannot be removed this way.
  Future<void> removeOwnReference(int noteId, String text) async {
    final db = await _db;
    await db.delete(
      'note_answers',
      where: 'note_id = ? AND text = ? AND added_by_learner = 1',
      whereArgs: [noteId, text],
    );
    _changes.fire();
  }

  /// Deletes a note with its card and their history.
  Future<void> deleteNote(int noteId) async {
    final db = await _db;
    await db.delete('notes', where: 'id = ?', whereArgs: [noteId]);
    _changes.fire();
  }

  Future<List<Deck>> decks() async {
    final db = await _db;
    final rows = await db.query('decks', orderBy: 'id');
    return [for (final row in rows) Deck.fromRow(row)];
  }

  /// Adds a note with its reference translations -- the first is primary --
  /// and its new Recall card.
  Future<int> addNote({
    required int deckId,
    required String nativeText,
    required List<String> references,
    NoteKind kind = NoteKind.sentence,
    String? sourceRef,
    DateTime? now,
  }) async {
    final db = await _db;
    final noteId = await db.transaction(
      (txn) => _insertNote(
        txn,
        deckId: deckId,
        nativeText: nativeText,
        references: references,
        kind: kind,
        sourceRef: sourceRef,
        now: now ?? DateTime.now(),
      ),
    );
    _changes.fire();
    return noteId;
  }

  /// Imports [deck] as a new deck, once per [key]: returns the new deck's id,
  /// or null when [key] was imported before -- even if the learner has since
  /// deleted that deck, which is theirs to delete. All or nothing: one
  /// transaction for the deck, its notes and the marker.
  Future<int?> importDeckOnce(
    String key,
    SeedDeck deck, {
    DateTime? now,
  }) async {
    final db = await _db;
    final at = now ?? DateTime.now();
    final metaKey = 'imported:$key';
    final deckId = await db.transaction((txn) async {
      final done = await txn.query(
        'deck_meta',
        where: 'key = ?',
        whereArgs: [metaKey],
      );
      if (done.isNotEmpty) return null;

      final deckId = await txn.insert('decks', {
        'name': deck.name,
        'native_lang': deck.nativeLang,
        'target_lang': deck.targetLang,
        'source': deck.source.name,
        'new_per_day': deck.newPerDay,
        'created_at': at.millisecondsSinceEpoch,
      });
      for (final note in deck.notes) {
        await _insertNote(
          txn,
          deckId: deckId,
          nativeText: note.nativeText,
          references: note.references,
          kind: note.kind,
          sourceRef: note.sourceRef,
          now: at,
        );
      }
      await txn.insert('deck_meta', {
        'key': metaKey,
        'value': at.toIso8601String(),
      });
      return deckId;
    });
    if (deckId != null) _changes.fire();
    return deckId;
  }

  Future<int> _insertNote(
    Transaction txn, {
    required int deckId,
    required String nativeText,
    required List<String> references,
    required NoteKind kind,
    required String? sourceRef,
    required DateTime now,
  }) async {
    if (references.isEmpty) {
      throw ArgumentError.value(references, 'references', 'needs at least one');
    }
    final noteId = await txn.insert('notes', {
      'deck_id': deckId,
      'native_text': nativeText,
      'kind': kind.name,
      'source_ref': sourceRef,
      'created_at': now.millisecondsSinceEpoch,
    });
    final batch = txn.batch();
    for (final (i, reference) in references.indexed) {
      batch.insert('note_answers', {
        'note_id': noteId,
        'text': reference,
        'is_primary': i == 0 ? 1 : 0,
      });
    }
    batch.insert('cards', {
      'note_id': noteId,
      'mode': CardMode.recall.name,
      ...CardSchedule.fresh.toRow(),
    });
    await batch.commit(noResult: true);
    return noteId;
  }

  /// Every note in [deckId], oldest first.
  Future<List<Note>> notes(int deckId) async {
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'deck_id = ?',
      whereArgs: [deckId],
      orderBy: 'id',
    );
    final references = await _referencesForDeck(db, deckId);
    return [for (final row in rows) _note(row, references)];
  }

  /// Today's cards for [deckId], shuffled:
  ///
  /// * every card already on a schedule and due before tomorrow (learning
  ///   cards from earlier in this sitting included);
  /// * plus new cards drawn at random, up to the deck's `new_per_day` minus
  ///   the new cards already introduced today.
  ///
  /// New cards are drawn at random rather than in the order they were added,
  /// so a deck written five sentences per pattern does not serve one pattern
  /// at a time; and due and new cards are mixed rather than due first.
  Future<List<StudyCard>> studyQueue(int deckId, {DateTime? now}) async {
    final db = await _db;
    final at = now ?? DateTime.now();
    final today = startOfDay(at).millisecondsSinceEpoch;
    final tomorrow = startOfDay(at, plusDays: 1).millisecondsSinceEpoch;

    final deck = Deck.fromRow(
      (await db.query('decks', where: 'id = ?', whereArgs: [deckId])).single,
    );

    final introducedToday =
        (await db.rawQuery(
              '''
              SELECT COUNT(*) AS count FROM (
                SELECT r.card_id, MIN(r.reviewed_at) AS first_review
                FROM reviews r
                JOIN cards c ON c.id = r.card_id
                JOIN notes n ON n.id = c.note_id
                WHERE n.deck_id = ? AND r.practice = 0
                GROUP BY r.card_id
              ) WHERE first_review >= ?
              ''',
              [deckId, today],
            )).first['count']!
            as int;

    final due = await db.rawQuery(
      '''
      SELECT $cardColumns
      FROM cards c JOIN notes n ON n.id = c.note_id
      WHERE n.deck_id = ? AND c.state != 'new' AND c.due_at < ?
      ''',
      [deckId, tomorrow],
    );
    final fresh = [
      ...await db.rawQuery(
        '''
        SELECT $cardColumns
        FROM cards c JOIN notes n ON n.id = c.note_id
        WHERE n.deck_id = ? AND c.state = 'new'
        ''',
        [deckId],
      ),
    ];
    _shuffle(fresh);
    final newLeft = math.max(0, deck.newPerDay - introducedToday);

    final picked = [...due, ...fresh.take(newLeft)];
    _shuffle(picked);
    return _studyCards(db, deckId, picked);
  }

  /// More cards once today's queue is done (a daily sitting tops itself up
  /// with these, see ReviewSession): up to [count]
  /// new cards drawn at random, ignoring `new_per_day`; when the deck runs
  /// out of new cards, the rest come from scheduled cards not yet due,
  /// soonest first. Graded like any other review. [except] keeps out cards
  /// already in this sitting.
  Future<List<StudyCard>> extraCards(
    int deckId, {
    int count = 10,
    Set<int> except = const {},
    DateTime? now,
  }) async {
    final db = await _db;
    final tomorrow = startOfDay(
      now ?? DateTime.now(),
      plusDays: 1,
    ).millisecondsSinceEpoch;
    bool keep(Map<String, Object?> row) =>
        !except.contains(row['card_id']! as int);

    final fresh = [
      for (final row in await db.rawQuery(
        '''
        SELECT $cardColumns
        FROM cards c JOIN notes n ON n.id = c.note_id
        WHERE n.deck_id = ? AND c.state = 'new'
        ''',
        [deckId],
      ))
        if (keep(row)) row,
    ];
    _shuffle(fresh);
    final picked = fresh.take(count).toList();
    if (picked.length < count) {
      final ahead = await db.rawQuery(
        '''
        SELECT $cardColumns
        FROM cards c JOIN notes n ON n.id = c.note_id
        WHERE n.deck_id = ? AND c.state != 'new' AND c.due_at >= ?
        ORDER BY c.due_at, c.id
        ''',
        [deckId, tomorrow],
      );
      picked.addAll(ahead.where(keep).take(count - picked.length));
    }
    return _studyCards(db, deckId, picked);
  }

  /// Cards for a custom session (practice only -- see [recordReview]'s
  /// `practice`), by [pick], at most [count] (all when null):
  ///
  /// * [CustomPick.random] -- the whole deck, shuffled;
  /// * [CustomPick.added] -- notes the learner wrote (no `source_ref`, unlike
  ///   imported ones), newest first;
  /// * [CustomPick.missed] -- cards whose latest grade, practice included,
  ///   was Wrong or Partial, shuffled.
  Future<List<StudyCard>> customCards(
    int deckId,
    CustomPick pick, {
    int? count,
  }) async {
    final db = await _db;
    final rows = [
      ...switch (pick) {
        CustomPick.random => await db.rawQuery(
          '''
          SELECT $cardColumns
          FROM cards c JOIN notes n ON n.id = c.note_id
          WHERE n.deck_id = ?
          ''',
          [deckId],
        ),
        CustomPick.added => await db.rawQuery(
          '''
          SELECT $cardColumns
          FROM cards c JOIN notes n ON n.id = c.note_id
          WHERE n.deck_id = ? AND n.source_ref IS NULL
          ORDER BY n.created_at DESC, n.id DESC
          ''',
          [deckId],
        ),
        CustomPick.missed => await db.rawQuery(
          '''
          SELECT $cardColumns
          FROM cards c JOIN notes n ON n.id = c.note_id
          JOIN reviews r ON r.card_id = c.id
          WHERE n.deck_id = ?
            AND r.id = (SELECT MAX(id) FROM reviews WHERE card_id = c.id)
            AND r.grade IN (?, ?)
          ''',
          [deckId, Grade.difficult.name, Grade.medium.name],
        ),
      },
    ];
    if (pick != CustomPick.added) _shuffle(rows);
    return _studyCards(
      db,
      deckId,
      count == null ? rows : rows.take(count).toList(),
    );
  }

  static const String cardColumns =
      'c.id AS card_id, c.note_id, c.state, c.due_at, '
      'c.interval_days, c.ease, c.reps, c.lapses, '
      'n.deck_id, n.native_text, n.kind, n.source_ref';

  Future<List<StudyCard>> _studyCards(
    DatabaseExecutor db,
    int deckId,
    List<Map<String, Object?>> rows,
  ) async {
    final references = await _referencesForDeck(db, deckId);
    return [
      for (final row in rows)
        StudyCard(
          cardId: row['card_id']! as int,
          schedule: CardSchedule.fromRow(row),
          note: _note({...row, 'id': row['note_id']}, references),
        ),
    ];
  }

  /// Grades card [cardId], reschedules it and logs the review. Returns the
  /// new schedule.
  ///
  /// [suggestedGrade] is what the answer's match against the card's ways to
  /// say it pre-selected (see answer_match.dart), null where it suggested
  /// nothing. [clarity] is a spoken answer's clarity score (mean Vosk word
  /// confidence, 0-100), null for a typed one.
  ///
  /// [practice] (a custom session) logs the grade but leaves the card's
  /// schedule as it was, and returns it unchanged. It still counts toward
  /// the daily goal and "cards I got wrong".
  Future<CardSchedule> recordReview({
    required int cardId,
    required Grade grade,
    required AnswerInput input,
    Grade? suggestedGrade,
    String? answerText,
    int? clarity,
    bool practice = false,
    DateTime? now,
  }) async {
    final db = await _db;
    final at = now ?? DateTime.now();
    final next = await db.transaction((txn) async {
      final row = (await txn.query(
        'cards',
        where: 'id = ?',
        whereArgs: [cardId],
      )).single;
      final before = CardSchedule.fromRow(row);
      final after = practice ? before : scheduleReview(before, grade, at);
      if (!practice) {
        await txn.update(
          'cards',
          after.toRow(),
          where: 'id = ?',
          whereArgs: [cardId],
        );
      }
      await txn.insert('reviews', {
        'card_id': cardId,
        'reviewed_at': at.millisecondsSinceEpoch,
        'grade': grade.name,
        'suggested_grade': suggestedGrade?.name,
        'input': input.name,
        'answer_text': answerText,
        'clarity': clarity,
        'practice': practice ? 1 : 0,
        'interval_before': before.intervalDays,
        'interval_after': after.intervalDays,
      });
      return after;
    });
    _changes.fire();
    return next;
  }

  /// Every reference translation in [deckId], by note id: the deck's own,
  /// then the learner's. One query for the whole deck
  /// rather than an `IN (...)` list, which SQLite caps at 999 parameters on
  /// older Android builds.
  Future<Map<int, ({List<String> deck, List<String> own})>> _referencesForDeck(
    DatabaseExecutor db,
    int deckId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT a.note_id, a.text, a.added_by_learner
      FROM note_answers a JOIN notes n ON n.id = a.note_id
      WHERE n.deck_id = ?
      ORDER BY a.note_id, a.is_primary DESC, a.id
      ''',
      [deckId],
    );
    final references = <int, ({List<String> deck, List<String> own})>{};
    for (final row in rows) {
      final note = references.putIfAbsent(
        row['note_id']! as int,
        () => (deck: <String>[], own: <String>[]),
      );
      (row['added_by_learner'] == 1 ? note.own : note.deck).add(
        row['text']! as String,
      );
    }
    return references;
  }

  Note _note(
    Map<String, Object?> row,
    Map<int, ({List<String> deck, List<String> own})> references,
  ) {
    final id = row['id']! as int;
    return Note(
      id: id,
      deckId: row['deck_id']! as int,
      nativeText: row['native_text']! as String,
      kind: NoteKind.values.byName(row['kind']! as String),
      sourceRef: row['source_ref'] as String?,
      references: references[id]?.deck ?? const [],
      ownReferences: references[id]?.own ?? const [],
    );
  }

  void dispose() => _changes.dispose();
}
