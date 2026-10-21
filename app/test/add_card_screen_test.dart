import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/screens/add_card_screen.dart';
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

  Future<int> open(WidgetTester tester) async {
    final deckId = await decks.createDeck(name: 'Mine');
    await tester.pumpWidget(
      DeckStoreScope(
        store: decks,
        child: MaterialApp(home: AddCardScreen(deckId: deckId)),
      ),
    );
    await tester.pumpAndSettle();
    return deckId;
  }

  Finder field(int i) => find.byType(TextFormField).at(i);

  testWidgets('needs the Spanish and one English translation', (tester) async {
    final deckId = await open(tester);

    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNWidgets(2));
    expect(await decks.notes(deckId), isEmpty);
  });

  testWidgets('saves a card with every translation, primary first', (
    tester,
  ) async {
    final deckId = await open(tester);

    await tester.enterText(field(0), ' Tengo hambre. ');
    await tester.enterText(field(1), "I'm hungry.");
    await tester.tap(find.text('Another translation'));
    await tester.pumpAndSettle();
    await tester.enterText(field(2), 'I am hungry.');
    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();

    final note = (await decks.notes(deckId)).single;
    expect(note.nativeText, 'Tengo hambre.');
    expect(note.references, ["I'm hungry.", 'I am hungry.']);
    expect(note.kind, NoteKind.sentence);
    // It is a new Recall card, due like any other.
    expect(await decks.studyQueue(deckId), hasLength(1));

    // Cleared and back to one translation, ready for the next card.
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.widget<TextFormField>(field(0)).controller!.text, isEmpty);
    expect(tester.widget<TextFormField>(field(1)).controller!.text, isEmpty);
    expect(find.text('1 card added'), findsOneWidget);
  });

  testWidgets('a blank extra translation is dropped, not saved', (
    tester,
  ) async {
    final deckId = await open(tester);

    await tester.enterText(field(0), 'Hola');
    await tester.enterText(field(1), 'Hello');
    await tester.tap(find.text('Another translation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();

    final note = (await decks.notes(deckId)).single;
    expect(note.references, ['Hello']);
    expect(note.kind, NoteKind.word);
  });

  testWidgets('an extra translation can be removed', (tester) async {
    await open(tester);

    await tester.tap(find.text('Another translation'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('labels come from the deck\'s languages', (tester) async {
    final deckId = await decks.createDeck(
      name: 'Mine',
      nativeLang: 'pt',
      targetLang: 'en',
    );
    await tester.pumpWidget(
      DeckStoreScope(
        store: decks,
        child: MaterialApp(home: AddCardScreen(deckId: deckId)),
      ),
    );
    await tester.pumpAndSettle();

    // The prompt side is "your language", never named; the target is.
    expect(find.text('YOUR LANGUAGE'), findsOneWidget);
    expect(find.text('ENGLISH'), findsOneWidget);
    expect(find.textContaining('Portuguese'), findsNothing);
    expect(find.textContaining('PORTUGUESE'), findsNothing);
  });
}
