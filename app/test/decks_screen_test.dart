import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/screens/decks_screen.dart';
import 'package:lingo_node/widgets/deck_look.dart';
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

  Widget app(Widget home) => DeckStoreScope(
    store: decks,
    child: MaterialApp(home: home),
  );

  Future<int> starterDeck() async {
    final id = await decks.createDeck(
      name: 'Spanish starter',
      source: DeckSource.starter,
    );
    await decks.addNote(
      deckId: id,
      nativeText: 'Hola.',
      references: ['Hello.'],
      sourceRef: '1',
    );
    return id;
  }

  testWidgets('a new deck can be created, and cards added to it', (
    tester,
  ) async {
    await tester.pumpWidget(app(const DecksScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New deck'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Travel');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Straight into the new, empty deck.
    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('No cards yet. Add your first one.'), findsOneWidget);

    await tester.tap(find.text('Add card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '¿Dónde está?');
    await tester.enterText(find.byType(TextFormField).at(1), 'Where is it?');
    await tester.tap(find.widgetWithText(FilledButton, 'Add card'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('¿Dónde está?'), findsOneWidget);
    expect(find.text('Where is it?'), findsOneWidget);
    final deck = (await decks.decks()).single;
    expect(deck.source, DeckSource.user);
  });

  testWidgets('a card in an own deck can be edited and deleted', (
    tester,
  ) async {
    final deckId = await decks.createDeck(name: 'Mine');
    await decks.addNote(
      deckId: deckId,
      nativeText: 'Gato',
      references: ['Cat'],
    );
    await tester.pumpWidget(app(DeckScreen(deckId: deckId)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gato'));
    await tester.pumpAndSettle();
    expect(find.text('EDIT CARD'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'A cat');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('A cat'), findsOneWidget);

    await tester.tap(find.text('Gato'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Gato'), findsNothing);
    expect(await decks.notes(deckId), isEmpty);
  });

  testWidgets('a starter deck is read-only', (tester) async {
    final deckId = await starterDeck();
    await tester.pumpWidget(app(DeckScreen(deckId: deckId)));
    await tester.pumpAndSettle();

    expect(find.textContaining('A starter deck'), findsOneWidget);
    expect(find.text('Add card'), findsNothing);
    await tester.tap(find.text('Hola.'));
    await tester.pumpAndSettle();
    expect(find.text('EDIT CARD'), findsNothing);
    // Opens to show the card; only the learner's own ways can change.
    expect(find.text('CARD'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Delete card'), findsNothing);

    await tester.ensureVisible(find.text('Add your own way'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your own way'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Hi there.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Hi there.'), findsOneWidget);
    final note = (await decks.notes(deckId)).single;
    expect(note.ownReferences, ['Hi there.']);
  });

  group('deck settings', () {
    testWidgets('own deck: rename, new cards per day, delete', (tester) async {
      final deckId = await decks.createDeck(name: 'Mine', newPerDay: 10);
      await tester.pumpWidget(app(const DecksScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Deck settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed'), findsOneWidget);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('11'), findsOneWidget);
      expect((await decks.deck(deckId)).newPerDay, 11);

      expect(find.text('Custom session'), findsOneWidget);

      await tester.tap(find.text('Delete deck'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await decks.decks(), isEmpty);
      // Back on the deck list, not on the deleted deck's page.
      expect(find.text('MY DECKS'), findsOneWidget);
    });

    testWidgets('starter deck: no rename or delete, but custom session', (
      tester,
    ) async {
      final deckId = await starterDeck();
      await tester.pumpWidget(app(DeckSettingsScreen(deckId: deckId)));
      await tester.pumpAndSettle();

      expect(find.text('Delete deck'), findsNothing);
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(find.text('Rename deck'), findsNothing);

      await tester.tap(find.text('Custom session'));
      await tester.pumpAndSettle();
      expect(find.text('CUSTOM'), findsOneWidget);
      expect(find.text('Random mix'), findsOneWidget);
    });

    testWidgets('any deck can pick an icon and a colour for its tile', (
      tester,
    ) async {
      final deckId = await starterDeck();
      await tester.pumpWidget(app(DecksScreen()));
      await tester.pumpAndSettle();
      // Unpicked: the default tile, not a flag.
      expect(find.text('🇪🇸'), findsNothing);
      expect(find.byIcon(kDeckIcons[kDefaultDeckIcon]!), findsOneWidget);

      await tester.pumpWidget(app(DeckSettingsScreen(deckId: deckId)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Icon'));
      await tester.pumpAndSettle();
      expect(find.text('COLOR'), findsOneWidget);
      expect(find.text('ICON'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('teal'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(kDeckIcons['travel']!));
      await tester.pumpAndSettle();
      // Saved as picked, no Save button.
      final deck = await decks.deck(deckId);
      expect((deck.icon, deck.color), ('travel', 'teal'));
      // Closing the sheet keeps the pick.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('COLOR'), findsNothing);

      await tester.pumpWidget(app(DecksScreen()));
      await tester.pumpAndSettle();
      final tile = tester.widget<DeckIconTile>(find.byType(DeckIconTile));
      expect((tile.icon, tile.color), ('travel', 'teal'));
    });

    test('an emoji from before v10 reads as the default look', () {
      final deck = Deck(
        id: 1,
        name: 'Old',
        nativeLang: 'es',
        targetLang: 'en',
        source: DeckSource.user,
        newPerDay: 10,
        createdAt: DateTime(2026),
        icon: '✈️',
      );
      expect(deckIconName(deck), kDefaultDeckIcon);
      expect(deckColorName(deck), kDefaultDeckColor);
    });

    test('a starter deck wears its own look until one is picked', () {
      Deck deck(DeckSource source, {String? icon}) => Deck(
        id: 1,
        name: 'Food & ordering',
        nativeLang: 'es',
        targetLang: 'en',
        source: source,
        newPerDay: 10,
        createdAt: DateTime(2026),
        icon: icon,
      );
      final starter = deck(DeckSource.starter);
      expect((deckIconName(starter), deckColorName(starter)), ('food', 'coral'));
      // The learner's pick wins; a deck of their own by that name is theirs.
      expect(deckIconName(deck(DeckSource.starter, icon: 'book')), 'book');
      expect(deckIconName(deck(DeckSource.user)), kDefaultDeckIcon);
    });
  });
}
