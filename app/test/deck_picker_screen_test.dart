import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/screens/deck_picker_screen.dart';
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

  Widget app(DeckPurpose purpose) => DeckStoreScope(
    store: decks,
    child: MaterialApp(home: DeckPickerScreen(purpose: purpose)),
  );

  Future<int> deck(String name, {DeckSource source = DeckSource.user}) async {
    final id = await decks.createDeck(name: name, source: source);
    await decks.addNote(
      deckId: id,
      nativeText: 'Hola $name.',
      references: ['Hi $name.'],
      sourceRef: source == DeckSource.user ? null : '1',
    );
    return id;
  }

  testWidgets('own decks come first; premade ones sit behind one row', (
    tester,
  ) async {
    await deck('Common phrases', source: DeckSource.starter);
    await deck('Food & ordering', source: DeckSource.starter);
    await deck('Trip to Lisbon');

    await tester.pumpWidget(app(DeckPurpose.recall));
    await tester.pumpAndSettle();

    expect(find.text('YOUR DECKS'), findsOneWidget);
    expect(find.text('Trip to Lisbon'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Trip to Lisbon')).dy,
      lessThan(tester.getTopLeft(find.text('Premade decks')).dy),
    );
    expect(find.text('2 decks · 2 due'), findsOneWidget);
    // The bundled decks themselves are one tap further in.
    expect(find.text('Common phrases'), findsNothing);
    // The learner has cards of their own, so no nudge to make some.
    expect(find.text('Create a deck'), findsNothing);

    await tester.tap(find.text('Premade decks'));
    await tester.pumpAndSettle();
    expect(find.text('Common phrases'), findsOneWidget);
    expect(find.text('Food & ordering'), findsOneWidget);
    expect(find.text('Trip to Lisbon'), findsNothing);
  });

  testWidgets('with no cards of their own, the learner is asked to make some', (
    tester,
  ) async {
    await deck('Common phrases', source: DeckSource.starter);
    await decks.createDeck(name: 'My cards');

    await tester.pumpWidget(app(DeckPurpose.recall));
    await tester.pumpAndSettle();
    expect(find.text('My cards'), findsOneWidget);
    expect(find.text('No cards yet'), findsOneWidget);

    await tester.tap(find.text('Create a deck'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Travel');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect((await decks.decks()).map((d) => d.name), contains('Travel'));
  });

  testWidgets('Pronunciation keeps the everyday sentences on top', (
    tester,
  ) async {
    await deck('Common phrases', source: DeckSource.starter);

    await tester.pumpWidget(app(DeckPurpose.pronunciation));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Everyday sentences')).dy,
      lessThan(tester.getTopLeft(find.text('YOUR DECKS')).dy),
    );
    expect(find.text('1 deck'), findsOneWidget);
  });
}
