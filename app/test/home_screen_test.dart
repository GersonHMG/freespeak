import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_scope.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/screens/home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _app(PracticeHistoryStore store, DeckStore decks) =>
    PracticeHistoryScope(
      store: store,
      child: DeckStoreScope(
        store: decks,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

void main() {
  setUpAll(sqfliteFfiInit);

  late PracticeHistoryStore store;
  late DeckStore decks;

  setUp(() {
    store = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    decks = DeckStore(store);
  });

  tearDown(() async {
    decks.dispose();
    await store.dispose();
  });

  testWidgets('Home offers exactly two modes: Recall and Pronunciation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(store, decks));
    await tester.pumpAndSettle();

    expect(find.text('Recall cards'), findsOneWidget);
    expect(find.text('Pronunciation'), findsOneWidget);
    // Gone from Home: custom sessions live in deck settings, Settings and
    // decks under More.
    expect(find.text('Custom session'), findsNothing);
    expect(find.text('Add a card'), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.text('Word Rematch'), findsNothing);
    expect(find.textContaining('Spanish'), findsNothing);
    // The bottom nav's second tab is More now.
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Practice'), findsNothing);
  });

  testWidgets('the Recall card counts due cards across every deck', (
    tester,
  ) async {
    await tester.pumpWidget(_app(store, decks));
    await tester.pumpAndSettle();
    expect(
      find.text('All caught up — choose a deck to practice'),
      findsOneWidget,
    );

    for (final name in ['One', 'Two']) {
      final deckId = await decks.createDeck(name: name);
      await decks.addNote(
        deckId: deckId,
        nativeText: 'Hola $name.',
        references: ['Hi $name.'],
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('2 cards due today'), findsOneWidget);

    final deckId = (await decks.decks()).first.id;
    final card = (await decks.studyQueue(deckId)).single;
    await decks.recordReview(
      cardId: card.cardId,
      grade: Grade.easy,
      input: AnswerInput.typed,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 card due today'), findsOneWidget);
  });

  testWidgets('both modes open the deck picker', (tester) async {
    await decks.createDeck(name: 'Starter');
    await tester.pumpWidget(_app(store, decks));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recall cards'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a deck'), findsOneWidget);
    expect(find.text('RECALL'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pronunciation'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a deck'), findsOneWidget);
    expect(find.text('Everyday sentences'), findsOneWidget);
  });

  testWidgets('the cards-per-day panel counts today, Recall included', (
    tester,
  ) async {
    await tester.pumpWidget(_app(store, decks));
    await tester.pumpAndSettle();
    expect(find.text('CARDS PER DAY'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    // Just the days: none of the Progress tab's facts under them.
    expect(find.textContaining('Best streak'), findsNothing);
    expect(find.textContaining('Goal of'), findsNothing);
    expect(find.textContaining('/ 15 cards', findRichText: true), findsNothing);

    final deckId = await decks.createDeck(name: 'Starter');
    await decks.addNote(
      deckId: deckId,
      nativeText: 'Hola.',
      references: ['Hi.'],
    );
    final card = (await decks.studyQueue(deckId)).single;
    await decks.recordReview(
      cardId: card.cardId,
      grade: Grade.medium,
      input: AnswerInput.typed,
    );
    await tester.pumpAndSettle();

    // Today's tile and the week's total both read 1.
    final todayTile = find
        .ancestor(of: find.text('Today'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: todayTile, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('1'), findsNWidgets(2));
  });
}
