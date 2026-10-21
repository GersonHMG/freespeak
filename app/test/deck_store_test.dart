// DeckStore against the desktop sqflite FFI backend, in memory -- see
// practice_history_store_test.dart for why.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_schema.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late PracticeHistoryStore history;
  late DeckStore decks;

  // Morning, so a same-day "later" stays inside today.
  final day1 = DateTime(2026, 10, 18, 9);

  setUp(() {
    history = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    decks = DeckStore(history);
  });

  tearDown(() async {
    decks.dispose();
    await history.dispose();
  });

  Future<int> deckWith(int notes, {int newPerDay = 10}) async {
    final deckId = await decks.createDeck(name: 'Test', newPerDay: newPerDay);
    for (var i = 0; i < notes; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'frase $i',
        references: ['sentence $i', 'alt $i'],
      );
    }
    return deckId;
  }

  test(
    'addNote stores references primary first and one card per mode',
    () async {
      final deckId = await decks.createDeck(name: 'Basics');
      await decks.addNote(
        deckId: deckId,
        nativeText: 'Tengo hambre.',
        references: ["I'm hungry.", 'I am hungry.'],
        sourceRef: '12345',
      );

      final notes = await decks.notes(deckId);
      expect(notes.single.primaryReference, "I'm hungry.");
      expect(notes.single.references, ["I'm hungry.", 'I am hungry.']);
      expect(notes.single.sourceRef, '12345');

      final db = await history.database;
      final cards = await db.query('cards', orderBy: 'id');
      expect(cards.map((c) => c['mode']), ['recall']);
      expect(cards.map((c) => c['state']), ['new']);
    },
  );

  test('addNote refuses a note with no references', () async {
    final deckId = await decks.createDeck(name: 'Basics');
    expect(
      () => decks.addNote(deckId: deckId, nativeText: 'Hola', references: []),
      throwsArgumentError,
    );
  });

  test('a fresh deck queues new cards up to new_per_day', () async {
    final deckId = await deckWith(4, newPerDay: 3);

    final queue = await decks.studyQueue(deckId, now: day1);

    expect(queue, hasLength(3));
    expect(queue.map((c) => c.note.id).toSet(), hasLength(3));
    expect(queue.every((c) => c.schedule.state == CardState.newCard), isTrue);
  });

  group('randomness', () {
    // Reversal stands in for a shuffle: deterministic, and visibly not the
    // order the cards were added in.
    void reverse<T>(List<T> list) {
      final reversed = list.reversed.toList();
      list
        ..clear()
        ..addAll(reversed);
    }

    late DeckStore reversing;
    setUp(() => reversing = DeckStore(history, shuffle: reverse));
    tearDown(() => reversing.dispose());

    test('new cards are drawn from the shuffled pool', () async {
      final deckId = await deckWith(4, newPerDay: 3);

      final queue = await reversing.studyQueue(deckId, now: day1);

      // The pool reversed is frase 3, 2, 1, 0; the first three are drawn,
      // then the picked queue is shuffled (reversed) once more.
      expect(queue.map((c) => c.note.nativeText), [
        'frase 1',
        'frase 2',
        'frase 3',
      ]);
    });

    test('due and new cards are shuffled together', () async {
      final deckId = await deckWith(3, newPerDay: 10);
      final first = (await decks.studyQueue(
        deckId,
        now: day1,
      )).firstWhere((c) => c.note.nativeText == 'frase 0');
      await decks.recordReview(
        cardId: first.cardId,
        grade: Grade.medium,
        input: AnswerInput.typed,
        now: day1,
      );

      final day2 = DateTime(2026, 10, 19, 9);
      final queue = await reversing.studyQueue(deckId, now: day2);

      // Due comes first in the unshuffled list, so last once reversed.
      expect(queue.last.cardId, first.cardId);
      expect(queue, hasLength(3));
    });

    test('the default store does not keep the order cards were added', () async {
      final deckId = await deckWith(30, newPerDay: 30);
      final orders = {
        for (var i = 0; i < 5; i++)
          (await decks.studyQueue(
            deckId,
            now: day1,
          )).map((c) => c.note.nativeText).join(','),
      };
      // Five shuffles of 30 cards all landing in one order: about 1 in 10^128.
      expect(orders, hasLength(greaterThan(1)));
    });
  });

  test('new cards introduced today count against new_per_day', () async {
    final deckId = await deckWith(5, newPerDay: 2);
    final first = await decks.studyQueue(deckId, now: day1);
    for (final card in first) {
      await decks.recordReview(
        cardId: card.cardId,
        grade: Grade.medium,
        input: AnswerInput.typed,
        now: day1,
      );
    }

    final later = await decks.studyQueue(
      deckId,
      now: day1.add(const Duration(hours: 2)),
    );
    expect(later, isEmpty);
  });

  test('a Difficult card comes back the same day', () async {
    final deckId = await deckWith(1);
    final card = (await decks.studyQueue(deckId, now: day1)).single;

    await decks.recordReview(
      cardId: card.cardId,
      grade: Grade.difficult,
      input: AnswerInput.spoken,
      now: day1,
    );

    final again = await decks.studyQueue(
      deckId,
      now: day1.add(const Duration(minutes: 5)),
    );
    expect(again.map((c) => c.cardId), [card.cardId]);
    expect(again.single.schedule.state, CardState.learning);
  });

  test('a reviewed card is due again on the day its interval says', () async {
    final deckId = await deckWith(1);
    final card = (await decks.studyQueue(deckId, now: day1)).single;
    await decks.recordReview(
      cardId: card.cardId,
      grade: Grade.easy,
      input: AnswerInput.typed,
      now: day1,
    );

    final day3 = DateTime(2026, 10, 20, 9);
    final day4 = DateTime(2026, 10, 21, 9);
    expect(await decks.studyQueue(deckId, now: day3), isEmpty);
    final onDue = await decks.studyQueue(deckId, now: day4);
    expect(onDue.map((c) => c.cardId), [card.cardId]);
  });

  test(
    'recordReview logs the review with what was suggested and scored',
    () async {
      final deckId = await deckWith(1);
      final card = (await decks.studyQueue(deckId, now: day1)).single;

      final next = await decks.recordReview(
        cardId: card.cardId,
        grade: Grade.medium,
        suggestedGrade: Grade.easy,
        input: AnswerInput.spoken,
        answerText: 'sentence zero',
        clarity: 74,
        now: day1,
      );
      expect(next.intervalDays, 1);

      final db = await history.database;
      final review = (await db.query('reviews')).single;
      expect(review['card_id'], card.cardId);
      expect(review['grade'], 'medium');
      expect(review['suggested_grade'], 'easy');
      expect(review['input'], 'spoken');
      expect(review['answer_text'], 'sentence zero');
      expect(review['clarity'], 74);
      expect(review['interval_before'], 0);
      expect(review['interval_after'], 1);
    },
  );

  test('deleting a deck cascades to its notes, cards and reviews', () async {
    final deckId = await deckWith(1);
    final card = (await decks.studyQueue(deckId, now: day1)).single;
    await decks.recordReview(
      cardId: card.cardId,
      grade: Grade.medium,
      input: AnswerInput.typed,
      now: day1,
    );

    final db = await history.database;
    await db.delete('decks', where: 'id = ?', whereArgs: [deckId]);

    for (final table in ['notes', 'note_answers', 'cards', 'reviews']) {
      expect(await db.query(table), isEmpty, reason: table);
    }
  });

  test('a v4 database upgrades with its attempts intact', () async {
    final dir = await Directory.systemTemp.createTemp('deck_store_test');
    final dbPath = p.join(dir.path, 'practice_history.db');
    final legacy = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
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
    await legacy.insert('attempts', {
      'timestamp': day1.millisecondsSinceEpoch,
      'sentence': 'Hello there.',
      'sentence_length': 2,
      'sentence_score': 80,
      'points': 10,
    });
    await legacy.close();

    final upgraded = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: dbPath,
    );
    final upgradedDecks = DeckStore(upgraded);
    addTearDown(() async {
      upgradedDecks.dispose();
      await upgraded.dispose();
      await dir.delete(recursive: true);
    });

    expect(await upgraded.totalPointsEarned(), 10);
    final deckId = await upgradedDecks.createDeck(name: 'After upgrade');
    await upgradedDecks.addNote(
      deckId: deckId,
      nativeText: 'Hola',
      references: ['Hello'],
      kind: NoteKind.word,
    );
    expect((await upgradedDecks.notes(deckId)).single.kind, NoteKind.word);
    expect(await (await upgraded.database).getVersion(), 11);
  });

  test('a v5 database loses its Pronounce cards and their reviews', () async {
    final dir = await Directory.systemTemp.createTemp('deck_store_test');
    final dbPath = p.join(dir.path, 'practice_history.db');
    final v5 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) async {
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
          await createDeckTables(db);
        },
      ),
    );
    final deckId = await v5.insert('decks', {
      'name': 'Old',
      'native_lang': 'es',
      'target_lang': 'en',
      'created_at': 0,
    });
    final noteId = await v5.insert('notes', {
      'deck_id': deckId,
      'native_text': 'Hola',
      'kind': 'sentence',
      'created_at': 0,
    });
    await v5.insert('note_answers', {
      'note_id': noteId,
      'text': 'Hello',
      'is_primary': 1,
    });
    await v5.insert('cards', {'note_id': noteId, 'mode': 'recall'});
    final pronounceId = await v5.insert('cards', {
      'note_id': noteId,
      'mode': 'pronounce',
    });
    await v5.insert('reviews', {
      'card_id': pronounceId,
      'reviewed_at': 0,
      'grade': 'easy',
      'input': 'spoken',
      'interval_before': 0,
      'interval_after': 3,
    });
    await v5.close();

    final upgraded = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: dbPath,
    );
    addTearDown(() async {
      await upgraded.dispose();
      await dir.delete(recursive: true);
    });

    final db = await upgraded.database;
    expect((await db.query('cards')).map((c) => c['mode']), ['recall']);
    expect(await db.query('reviews'), isEmpty);
    expect(await db.getVersion(), 11);
  });

  group('extraCards', () {
    test(
      'gives more new cards past new_per_day, none already queued',
      () async {
        final deckId = await deckWith(5, newPerDay: 2);
        final today = await decks.studyQueue(deckId, now: day1);

        final extra = await decks.extraCards(
          deckId,
          count: 2,
          except: {for (final c in today) c.cardId},
          now: day1,
        );

        expect(extra, hasLength(2));
        expect(
          extra.map((c) => c.cardId).toSet().intersection({
            for (final c in today) c.cardId,
          }),
          isEmpty,
        );
        expect(
          extra.every((c) => c.schedule.state == CardState.newCard),
          isTrue,
        );
      },
    );

    test('falls back to cards due soonest once no new ones are left', () async {
      final deckId = await deckWith(2);
      for (final card in await decks.studyQueue(deckId, now: day1)) {
        await decks.recordReview(
          cardId: card.cardId,
          grade: Grade.easy,
          input: AnswerInput.typed,
          now: day1,
        );
      }

      final extra = await decks.extraCards(deckId, now: day1);

      expect(extra, hasLength(2));
      expect(extra.every((c) => c.schedule.state == CardState.review), isTrue);
    });
  });

  group('customCards', () {
    test('random draws from the whole deck, at most count', () async {
      final deckId = await deckWith(5);
      expect(
        await decks.customCards(deckId, CustomPick.random, count: 3),
        hasLength(3),
      );
      expect(await decks.customCards(deckId, CustomPick.random), hasLength(5));
    });

    test('added keeps only the learner\'s own cards, newest first', () async {
      final deckId = await decks.createDeck(name: 'Mixed');
      await decks.addNote(
        deckId: deckId,
        nativeText: 'imported',
        references: ['x'],
        sourceRef: '1',
      );
      await decks.addNote(
        deckId: deckId,
        nativeText: 'mine, older',
        references: ['x'],
        now: day1,
      );
      await decks.addNote(
        deckId: deckId,
        nativeText: 'mine, newer',
        references: ['x'],
        now: day1.add(const Duration(hours: 1)),
      );

      final cards = await decks.customCards(deckId, CustomPick.added);

      expect(cards.map((c) => c.note.nativeText), [
        'mine, newer',
        'mine, older',
      ]);
    });

    test('missed is cards whose last grade was Wrong or Partial', () async {
      final deckId = await deckWith(3);
      final queue = await decks.studyQueue(deckId, now: day1);
      final byText = {for (final c in queue) c.note.nativeText: c.cardId};
      Future<void> grade(String text, Grade grade, DateTime at) =>
          decks.recordReview(
            cardId: byText[text]!,
            grade: grade,
            input: AnswerInput.typed,
            now: at,
          );
      await grade('frase 0', Grade.difficult, day1);
      await grade('frase 1', Grade.medium, day1);
      await grade('frase 2', Grade.difficult, day1);
      // Fixed since: no longer missed.
      await grade('frase 2', Grade.easy, day1.add(const Duration(minutes: 5)));

      final missed = await decks.customCards(deckId, CustomPick.missed);

      expect(missed.map((c) => c.note.nativeText).toSet(), {
        'frase 0',
        'frase 1',
      });
    });
  });

  test('a practice grade is logged but leaves the schedule alone', () async {
    final deckId = await deckWith(1, newPerDay: 1);
    final card = (await decks.studyQueue(deckId, now: day1)).single;

    final after = await decks.recordReview(
      cardId: card.cardId,
      grade: Grade.easy,
      input: AnswerInput.typed,
      practice: true,
      now: day1,
    );

    expect(after.state, CardState.newCard);
    final db = await history.database;
    expect((await db.query('cards')).single['state'], 'new');
    expect((await db.query('reviews')).single['practice'], 1);
    // And it is not counted as today's new card: the daily one still comes.
    expect(await decks.studyQueue(deckId, now: day1), hasLength(1));
  });

  group('editing', () {
    test('updateNote rewrites the card but keeps its schedule', () async {
      final deckId = await deckWith(1);
      final card = (await decks.studyQueue(deckId, now: day1)).single;
      await decks.recordReview(
        cardId: card.cardId,
        grade: Grade.easy,
        input: AnswerInput.typed,
        now: day1,
      );

      await decks.updateNote(
        card.note.id,
        nativeText: 'nueva',
        references: ['new one', 'another'],
      );

      final note = (await decks.notes(deckId)).single;
      expect(note.nativeText, 'nueva');
      expect(note.references, ['new one', 'another']);
      final db = await history.database;
      expect((await db.query('cards')).single['state'], 'review');
      expect(await db.query('reviews'), hasLength(1));
    });

    test('deleteNote and deleteDeck remove everything under them', () async {
      final deckId = await deckWith(2);
      final first = (await decks.notes(deckId)).first;
      await decks.deleteNote(first.id);
      expect(await decks.notes(deckId), hasLength(1));

      await decks.deleteDeck(deckId);
      final db = await history.database;
      for (final table in ['decks', 'notes', 'note_answers', 'cards']) {
        expect(await db.query(table), isEmpty, reason: table);
      }
    });

    test('renameDeck, setNewPerDay and deckSummaries', () async {
      final deckId = await deckWith(3, newPerDay: 2);
      await decks.renameDeck(deckId, 'Renamed');
      await decks.setNewPerDay(deckId, 1);

      final summary = (await decks.deckSummaries(now: day1)).single;
      expect(summary.deck.name, 'Renamed');
      expect(summary.cardCount, 3);
      expect(summary.dueCount, 1);
    });

    test('deckSummaries counts shown cards and last-graded Perfect', () async {
      final deckId = await deckWith(3, newPerDay: 3);
      final empty = await decks.createDeck(name: 'Empty');
      expect(
        (await decks.deckSummaries(now: day1))
            .firstWhere((s) => s.deck.id == deckId)
            .progressPercent,
        isNull,
      );

      final cards = await decks.studyQueue(deckId, now: day1);
      Future<void> grade(int i, Grade g) => decks.recordReview(
        cardId: cards[i].cardId,
        grade: g,
        input: AnswerInput.typed,
        now: day1,
      );
      await grade(0, Grade.easy);
      await grade(1, Grade.easy);
      await grade(1, Grade.difficult); // the last grade is the one that counts

      final summaries = await decks.deckSummaries(now: day1);
      final summary = summaries.firstWhere((s) => s.deck.id == deckId);
      expect(summary.shownCount, 2);
      expect(summary.perfectCount, 1);
      expect(summary.progressPercent, 50);
      final none = summaries.firstWhere((s) => s.deck.id == empty);
      expect(none.shownCount, 0);
      expect(none.progressPercent, isNull);
    });

    test('only user decks are editable', () async {
      final mine = await decks.createDeck(name: 'Mine');
      final starter = await decks.createDeck(
        name: 'Starter',
        source: DeckSource.starter,
      );
      expect((await decks.deck(mine)).isEditable, isTrue);
      expect((await decks.deck(starter)).isEditable, isFalse);
    });
  });

  test('a v7 database renames its starter decks', () async {
    final dir = await Directory.systemTemp.createTemp('deck_store_test');
    final dbPath = p.join(dir.path, 'practice_history.db');
    final v7 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
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
          await createDeckTables(db);
        },
      ),
    );
    for (final (name, source) in [
      ('Spanish starter', 'starter'),
      ('My Spanish', 'user'),
    ]) {
      await v7.insert('decks', {
        'name': name,
        'native_lang': 'es',
        'target_lang': 'en',
        'source': source,
        'created_at': 0,
      });
    }
    await v7.close();

    final upgraded = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: dbPath,
    );
    addTearDown(() async {
      await upgraded.dispose();
      await dir.delete(recursive: true);
    });

    final db = await upgraded.database;
    expect((await db.query('decks', orderBy: 'id')).map((d) => d['name']), [
      'Starter deck',
      'My Spanish',
    ]);
  });

  test('a deck takes an icon and a colour, and can go back to none', () async {
    final deckId = await decks.createDeck(name: 'Trips');
    var deck = await decks.deck(deckId);
    expect((deck.icon, deck.color), (null, null));

    await decks.setDeckLook(deckId, icon: 'travel', color: 'teal');
    deck = await decks.deck(deckId);
    expect((deck.icon, deck.color), ('travel', 'teal'));

    await decks.setDeckLook(deckId, icon: null, color: null);
    deck = await decks.deck(deckId);
    expect((deck.icon, deck.color), (null, null));
  });

  test('a v8 database gains the deck icon and colour columns', () async {
    final dir = await Directory.systemTemp.createTemp('deck_store_test');
    final dbPath = p.join(dir.path, 'practice_history.db');
    final v8 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, version) async {
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
          await createDeckTables(db);
          // The v8 decks table, from before the icon and colour.
          await db.execute('ALTER TABLE decks DROP COLUMN icon');
          await db.execute('ALTER TABLE decks DROP COLUMN color');
        },
      ),
    );
    await v8.insert('decks', {
      'name': 'Mine',
      'native_lang': 'es',
      'target_lang': 'en',
      'source': 'user',
      'created_at': 0,
    });
    await v8.close();

    final upgraded = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: dbPath,
    );
    final upgradedDecks = DeckStore(upgraded);
    addTearDown(() async {
      upgradedDecks.dispose();
      await upgraded.dispose();
      await dir.delete(recursive: true);
    });

    final deckId = (await upgradedDecks.decks()).single.id;
    expect((await upgradedDecks.deck(deckId)).icon, isNull);
    await upgradedDecks.setDeckLook(deckId, icon: 'book', color: 'coral');
    final deck = await upgradedDecks.deck(deckId);
    expect((deck.icon, deck.color), ('book', 'coral'));
    expect(await (await upgraded.database).getVersion(), 11);
  });

  group('own references', () {
    test('are kept apart from the deck\'s and refuse duplicates', () async {
      final deckId = await deckWith(1);
      final noteId = (await decks.notes(deckId)).single.id;

      expect(await decks.addOwnReference(noteId, ' I love it '), isTrue);
      // Same words, other case and punctuation: already there.
      expect(await decks.addOwnReference(noteId, 'i LOVE it!'), isFalse);
      expect(await decks.addOwnReference(noteId, 'Sentence 0.'), isFalse);
      expect(await decks.addOwnReference(noteId, '  '), isFalse);

      final note = (await decks.notes(deckId)).single;
      expect(note.references, ['sentence 0', 'alt 0']);
      expect(note.ownReferences, ['I love it']);
      expect(note.primaryReference, 'sentence 0');
    });

    test('survive an edit of the deck\'s references', () async {
      final deckId = await deckWith(1);
      final noteId = (await decks.notes(deckId)).single.id;
      await decks.addOwnReference(noteId, 'mine');

      await decks.updateNote(
        noteId,
        nativeText: 'frase',
        references: ['new main'],
      );

      final note = (await decks.notes(deckId)).single;
      expect(note.references, ['new main']);
      expect(note.ownReferences, ['mine']);
    });

    test('removing one leaves the deck\'s references alone', () async {
      final deckId = await deckWith(1);
      final noteId = (await decks.notes(deckId)).single.id;
      await decks.addOwnReference(noteId, 'mine');

      await decks.removeOwnReference(noteId, 'mine');
      await decks.removeOwnReference(noteId, 'alt 0');

      final note = (await decks.notes(deckId)).single;
      expect(note.references, ['sentence 0', 'alt 0']);
      expect(note.ownReferences, isEmpty);
    });
  });

  test('practisedCards tallies each graded card, latest first', () async {
    final deckId = await deckWith(3);
    final [first, second, _] = await decks.studyQueue(deckId, now: day1);
    Future<void> grade(StudyCard card, Grade grade, Duration later) =>
        decks.recordReview(
          cardId: card.cardId,
          grade: grade,
          input: AnswerInput.typed,
          practice: true,
          now: day1.add(later),
        );
    await grade(first, Grade.difficult, Duration.zero);
    await grade(second, Grade.easy, const Duration(minutes: 1));
    await grade(first, Grade.easy, const Duration(minutes: 2));

    final cards = await decks.practisedCards();
    expect(cards.map((c) => c.cardId), [first.cardId, second.cardId]);
    expect(cards.first.nativeText, first.note.nativeText);
    expect(cards.first.reference, first.note.primaryReference);
    expect(cards.first.grades, {
      Grade.difficult: 1,
      Grade.medium: 0,
      Grade.easy: 1,
    });
    expect(cards.first.lastGrade, Grade.easy);
    expect(cards.first.timesPractised, 2);
    expect(await decks.gradeCounts(), {
      Grade.difficult: 1,
      Grade.medium: 0,
      Grade.easy: 2,
    });
  });
}
