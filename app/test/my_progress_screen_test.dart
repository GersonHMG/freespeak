import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_scope.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/screens/my_progress_screen.dart';
import 'package:lingo_node/widgets/score_trend_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late PracticeHistoryStore history;
  late DeckStore decks;

  setUp(() {
    history = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    decks = DeckStore(history);
  });

  tearDown(() async {
    decks.dispose();
    await history.dispose();
  });

  Widget app() => PracticeHistoryScope(
    store: history,
    child: DeckStoreScope(
      store: decks,
      child: const MaterialApp(home: MyProgressScreen()),
    ),
  );

  testWidgets('Progress shows cards per day, grades given, and pronunciation', (
    tester,
  ) async {
    final deckId = await decks.createDeck(name: 'Test');
    for (var i = 0; i < 3; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'frase $i',
        references: ['sentence $i'],
      );
    }
    final queue = await decks.studyQueue(deckId);
    for (final (i, grade) in [
      Grade.difficult,
      Grade.medium,
      Grade.easy,
    ].indexed) {
      await decks.recordReview(
        cardId: queue[i].cardId,
        grade: grade,
        input: AnswerInput.typed,
      );
    }

    // A small phone: nothing may overflow.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Cards per day as numbers, today marked.
    expect(find.text('CARDS PER DAY'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('Goal of 15 met 0 of 7 days'), findsOneWidget);

    // Every grade given, by name.
    expect(find.text('CARDS PRACTISED'), findsOneWidget);
    expect(find.text('3 total'), findsOneWidget);
    for (final label in ['Wrong', 'Partial', 'Perfect']) {
      expect(find.text(label), findsOneWidget);
    }

    // No flashcard jargon, no points, no removed sections.
    for (final gone in [
      'Mature',
      'RETENTION',
      'REVIEWS',
      'REMEMBERED',
      'pts',
      'YOUR CARDS',
      'COMING UP',
      'Goal 15',
    ]) {
      expect(find.textContaining(gone), findsNothing);
    }

    // The score trend: today's 3 grades (Wrong, Partial, Perfect) average
    // 50. The whole card opens the day-by-day breakdown.
    expect(find.text('SCORE · LAST 3 DAYS'), findsOneWidget);
    expect(find.text('50 / 100', findRichText: true), findsOneWidget);
    expect(find.text('Needs work'), findsNothing); // no band word
    expect(find.byType(ScoreTrendChart), findsOneWidget);
    expect(find.text('ACTIVITY'), findsNothing);
    await tester.tap(find.text('SCORE · LAST 3 DAYS'));
    await tester.pumpAndSettle();
    expect(find.text('DAY BY DAY'), findsOneWidget);
    expect(find.text('3 answers'), findsOneWidget);
    // The headline again, and today's own row with its score.
    expect(find.text('50 / 100', findRichText: true), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A grade opens the cards given it...
    await tester.scrollUntilVisible(find.text('Wrong'), 200);
    await tester.tap(find.text('Wrong'));
    await tester.pumpAndSettle();
    expect(find.text('CARDS PRACTISED'), findsOneWidget);
    expect(find.text(queue[0].note.nativeText), findsOneWidget);
    expect(find.text(queue[0].note.primaryReference), findsOneWidget);
    expect(find.text(queue[1].note.nativeText), findsNothing);
    // ...and All shows every practised card.
    await tester.tap(find.text('All 3'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(find.text('frase $i'), findsOneWidget);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Pronunciation opens the mispronounced words, without saying so.
    expect(find.text('See mispronounced words'), findsNothing);
    await tester.scrollUntilVisible(find.text('PRONUNCIATION'), 200);
    await tester.tap(find.text('PRONUNCIATION'));
    await tester.pumpAndSettle();
    expect(find.text('Revisit mispronunciations'), findsOneWidget);
    expect(find.text('Words'), findsOneWidget);
  });
}
