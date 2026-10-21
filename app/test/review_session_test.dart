import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/review_session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late PracticeHistoryStore history;
  late DeckStore decks;
  final now = DateTime(2026, 10, 18, 9);

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

  Future<ReviewSession> sessionWith(int notes) async {
    final deckId = await decks.createDeck(name: 'Test');
    for (var i = 0; i < notes; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'frase $i',
        references: ['sentence $i'],
      );
    }
    final session = ReviewSession(decks, deckId: deckId);
    addTearDown(session.dispose);
    await session.load(now: now);
    return session;
  }

  test('loads the queue for today', () async {
    final session = await sessionWith(2);
    expect(session.isLoaded, isTrue);
    expect(session.remaining, 2);
    expect(session.current, isNotNull);
  });

  test('grading moves on, counts and notifies', () async {
    final session = await sessionWith(2);
    final first = session.current!.cardId;
    var notified = 0;
    session.addListener(() => notified++);

    await session.grade(Grade.medium, input: AnswerInput.spoken, now: now);

    expect(session.reviewed, 1);
    expect(session.remaining, 1);
    expect(session.current!.cardId, isNot(first));
    expect(notified, greaterThanOrEqualTo(1));
  });

  test('Difficult on a first look requeues the card at the end', () async {
    final session = await sessionWith(2);
    final first = session.current!.cardId;

    await session.grade(Grade.difficult, input: AnswerInput.typed, now: now);
    expect(session.remaining, 2);
    await session.grade(Grade.easy, input: AnswerInput.typed, now: now);

    expect(session.current!.cardId, first);
    expect(session.current!.schedule.state, CardState.learning);
    await session.grade(Grade.medium, input: AnswerInput.typed, now: now);
    expect(session.current, isNull);
    expect(session.reviewed, 3);
  });

  test('passes answer details through to the review log', () async {
    final session = await sessionWith(1);

    await session.grade(
      Grade.easy,
      input: AnswerInput.spoken,
      suggestedGrade: Grade.easy,
      answerText: 'sentence zero',
      clarity: 91,
      now: now,
    );

    final db = await history.database;
    final review = (await db.query('reviews')).single;
    expect(review['input'], 'spoken');
    expect(review['answer_text'], 'sentence zero');
    expect(review['clarity'], 91);
    expect(review['suggested_grade'], 'easy');
  });

  test('the daily sitting tops itself up until the deck runs out', () async {
    final deckId = await decks.createDeck(name: 'Small', newPerDay: 1);
    for (var i = 0; i < 3; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'frase $i',
        references: ['sentence $i'],
      );
    }
    final session = ReviewSession(decks, deckId: deckId);
    addTearDown(session.dispose);
    await session.load(now: now);
    expect(session.remaining, 1); // new_per_day
    expect(session.deck!.name, 'Small');

    // The day's one card graded: the other two come straight after.
    await session.grade(Grade.easy, input: AnswerInput.typed, now: now);
    expect(session.remaining, 2);
    await session.grade(Grade.easy, input: AnswerInput.typed, now: now);
    await session.grade(Grade.easy, input: AnswerInput.typed, now: now);

    // Every card has been through the sitting: now it ends.
    expect(session.current, isNull);
    expect(session.reviewed, 3);
  });

  test('a sitting with nothing due starts on more cards anyway', () async {
    final deckId = await decks.createDeck(name: 'Small', newPerDay: 1);
    for (var i = 0; i < 2; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'frase $i',
        references: ['sentence $i'],
      );
    }
    final first = ReviewSession(decks, deckId: deckId);
    addTearDown(first.dispose);
    await first.load(now: now);
    await first.grade(Grade.easy, input: AnswerInput.typed, now: now);

    // Nothing due and today's new card already taken: still not empty.
    final second = ReviewSession(decks, deckId: deckId);
    addTearDown(second.dispose);
    await second.load(now: now);
    expect(second.current, isNotNull);
  });

  test('a round ends after five cards, and keepGoing starts another', () async {
    final session = await sessionWith(7);
    expect(session.remaining, ReviewSession.roundLength);

    for (final grade in [
      Grade.easy,
      Grade.easy,
      Grade.medium,
      Grade.easy,
      Grade.difficult,
    ]) {
      await session.grade(grade, input: AnswerInput.typed, now: now);
    }
    expect(session.isRoundOver, isTrue);
    expect(session.current, isNull);
    expect(session.remaining, 0);
    expect(session.hasMore, isTrue);
    expect(session.reviewed, 5);
    expect(session.grades, {
      Grade.easy: 3,
      Grade.medium: 1,
      Grade.difficult: 1,
    });

    session.keepGoing();
    expect(session.current, isNotNull);
    expect(session.reviewed, 0);
    expect(session.grades.values, everyElement(0));
  });

  test('a practice session keeps its order and moves no due date', () async {
    final deckId = await decks.createDeck(name: 'Test');
    for (var i = 0; i < 2; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'frase $i',
        references: ['sentence $i'],
      );
    }
    final cards = await decks.customCards(deckId, CustomPick.random);
    final session = ReviewSession.practice(decks, deckId: deckId, cards: cards);
    addTearDown(session.dispose);
    await session.load(now: now);
    expect(session.current!.cardId, cards.first.cardId);

    // Wrong does not requeue in practice.
    await session.grade(Grade.difficult, input: AnswerInput.typed, now: now);
    await session.grade(Grade.easy, input: AnswerInput.typed, now: now);
    expect(session.current, isNull);

    final db = await history.database;
    expect(
      (await db.query('cards')).map((c) => c['state']),
      everyElement('new'),
    );
    expect(await session.practiceMore(now: now), 0);
  });
}
