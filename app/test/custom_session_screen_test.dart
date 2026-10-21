import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/pronunciation/asr.dart';
import 'package:lingo_node/pronunciation/mispronounce_detector.dart';
import 'package:lingo_node/pronunciation/pronunciation_scope.dart';
import 'package:lingo_node/screens/custom_session_screen.dart';
import 'package:lingo_node/tts/phonon_tts.dart';
import 'package:lingo_node/tts/phonon_tts_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentAsr implements Asr {
  @override
  Future<void> ready() async {}
  @override
  Future<Transcript> transcribe(
    String wavPath, {
    List<String>? vocabulary,
  }) async => const Transcript(text: '');
  @override
  Future<void> dispose() async {}
}

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
    final deckId = await decks.createDeck(name: 'Starter');
    for (var i = 0; i < 3; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'frase $i',
        references: ['sentence $i'],
        sourceRef: '$i',
      );
    }
    await decks.addNote(
      deckId: deckId,
      nativeText: 'mía',
      references: ['mine'],
    );
    await tester.pumpWidget(
      PhononTtsScope(
        tts: PhononTts(),
        child: PronunciationScope(
          detector: MispronounceDetector(
            asr: _SilentAsr(),
            phonemize: (word) async => word,
          ),
          child: DeckStoreScope(
            store: decks,
            child: MaterialApp(home: CustomSessionScreen(deckId: deckId)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return deckId;
  }

  testWidgets('shows each pick with how many cards it has', (tester) async {
    await open(tester);

    expect(find.text('Random mix'), findsOneWidget);
    expect(find.text('Any cards from the deck · 4 cards'), findsOneWidget);
    expect(find.text('Your own cards, newest first · 1 card'), findsOneWidget);
    expect(find.text('Last graded Wrong or Partial · 0 cards'), findsOneWidget);
    expect(find.textContaining('Practice only'), findsOneWidget);
  });

  testWidgets('Cards I added starts a practice session over those cards', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('Cards I added'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOM'), findsOneWidget);
    expect(find.text('mía'), findsOneWidget);
    expect(find.text('1 left'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mine');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next card'));
    await tester.pumpAndSettle();

    expect(find.text('Session complete'), findsOneWidget);
    // Practice only: no "Practice more", and the card is still new.
    expect(find.text('Practice more'), findsNothing);
    final db = await history.database;
    expect(
      (await db.query('cards')).map((c) => c['state']),
      everyElement('new'),
    );
    expect((await db.query('reviews')).single['practice'], 1);
  });
}
