import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/pronunciation/asr.dart';
import 'package:lingo_node/pronunciation/mispronounce_detector.dart';
import 'package:lingo_node/pronunciation/pronunciation_scope.dart';
import 'package:lingo_node/screens/recall_review_screen.dart';
import 'package:lingo_node/widgets/grade_buttons.dart';
import 'package:lingo_node/widgets/record_button.dart';
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

void _keepOrder<T>(List<T> list) {}

void main() {
  setUpAll(sqfliteFfiInit);

  late PracticeHistoryStore history;
  late DeckStore decks;

  setUp(() {
    history = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    // Queue in the order the cards were added, so the tests know which
    // card comes first.
    decks = DeckStore(history, shuffle: _keepOrder);
  });

  tearDown(() async {
    decks.dispose();
    await history.dispose();
  });

  // Unloaded engines are enough: a widget test has no microphone, so the
  // say-it step is only checked up to recording.
  Widget app(int deckId) => PhononTtsScope(
    tts: PhononTts(),
    child: PronunciationScope(
      detector: MispronounceDetector(
        asr: _SilentAsr(),
        phonemize: (word) async => word,
      ),
      child: DeckStoreScope(
        store: decks,
        child: MaterialApp(home: RecallReviewScreen(deckId: deckId)),
      ),
    ),
  );

  Future<int> deck() async {
    final deckId = await decks.createDeck(name: 'Starter');
    await decks.addNote(
      deckId: deckId,
      nativeText: 'Tengo hambre.',
      references: ["I'm hungry.", 'I am hungry.'],
    );
    await decks.addNote(
      deckId: deckId,
      nativeText: '¿Dónde está la estación?',
      references: ['Where is the station?'],
    );
    return deckId;
  }

  testWidgets('shows the Spanish and hides the references until answered', (
    tester,
  ) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    expect(find.text('RECALL'), findsOneWidget);
    expect(find.text('Tengo hambre.'), findsOneWidget);
    expect(find.text('2 left'), findsOneWidget);
    expect(find.text('Type or say it in English'), findsOneWidget);
    expect(find.byTooltip('Dictate'), findsOneWidget);
    expect(find.text("I don't know"), findsOneWidget);
    expect(find.text('Show answer'), findsNothing);
    expect(find.text("I'm hungry."), findsNothing);
    expect(find.text('Perfect'), findsNothing);
  });

  testWidgets('a typed answer is shown beside every reference', (tester) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  I have hunger ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('YOUR ANSWER'), findsOneWidget);
    expect(find.text('I have hunger'), findsOneWidget);
    // One way at a time, the main one first; a swipe up shows the next.
    expect(find.text('WAY 1 OF 2'), findsOneWidget);
    expect(find.text("I'm hungry."), findsOneWidget);
    expect(find.text('I am hungry.'), findsNothing);
    await tester.fling(find.text("I'm hungry."), const Offset(0, -200), 1000);
    await tester.pumpAndSettle();
    expect(find.text('WAY 2 OF 2'), findsOneWidget);
    expect(find.text('I am hungry.'), findsOneWidget);
    expect(find.text("I'm hungry."), findsNothing);
    // And the dots go straight to one.
    await tester.tap(find.bySemanticsLabel('Way 1 of 2'));
    await tester.pumpAndSettle();
    expect(find.text("I'm hungry."), findsOneWidget);
    expect(find.text('How close was your answer?'), findsOneWidget);
    // No clarity for a typed answer, and "I have hunger" is too far from
    // "I'm hungry" for its wording to say right or wrong (s = 0.5, see
    // answer_match.dart): no grade is pre-selected.
    expect(find.textContaining('Clarity'), findsNothing);
    expect(
      tester.widget<GradeButtons>(find.byType(GradeButtons)).suggested,
      isNull,
    );

    await tester.tap(find.text('Partial'));
    await tester.pumpAndSettle();

    // Graded: the card stays turned over for the "say it" step.
    expect(find.text('NOW SAY IT'), findsOneWidget);
    expect(find.text('YOUR ANSWER'), findsNothing);
    expect(find.byType(RecordButton), findsOneWidget);

    await tester.tap(find.text('Next card'));
    await tester.pumpAndSettle();
    expect(find.text('¿Dónde está la estación?'), findsOneWidget);
    expect(find.text('NOW SAY IT'), findsNothing);
    final review = (await (await history.database).query('reviews')).single;
    expect(review['input'], 'typed');
    expect(review['answer_text'], 'I have hunger');
    expect(review['clarity'], isNull);
    expect(review['suggested_grade'], isNull);
  });

  testWidgets('an empty typed answer does nothing', (tester) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('Check'));
    await tester.pumpAndSettle();

    expect(find.text('YOUR ANSWER'), findsNothing);
    expect(find.text('Perfect'), findsNothing);
  });

  testWidgets("I don't know grades Wrong and goes straight to say it", (
    tester,
  ) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    await tester.tap(find.text("I don't know"));
    await tester.pumpAndSettle();

    // Turned over, with no grade to choose: it was Wrong.
    expect(find.text("I'm hungry."), findsWidgets);
    expect(find.text('YOUR ANSWER'), findsNothing);
    expect(find.text('How close was your answer?'), findsNothing);
    expect(find.text('Perfect'), findsNothing);
    expect(find.text('NOW SAY IT'), findsOneWidget);
    final review = (await (await history.database).query('reviews')).single;
    expect(review['grade'], 'difficult');
    expect(review['answer_text'], isNull);
  });

  testWidgets('a single reference is "one way to say it"', (tester) async {
    final deckId = await decks.createDeck(name: 'One');
    await decks.addNote(
      deckId: deckId,
      nativeText: 'Hola.',
      references: ['Hello.'],
    );
    await tester.pumpWidget(app(deckId));
    await tester.pumpAndSettle();

    await tester.tap(find.text("I don't know"));
    await tester.pumpAndSettle();
    expect(find.text('ONE WAY TO SAY IT'), findsOneWidget);
  });

  testWidgets('no microphone and no going back before grading', (tester) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();
    // Answering is writing (typed or dictated): no pronunciation record
    // button yet -- that is the say-it step's.
    expect(find.byType(RecordButton), findsNothing);

    await tester.enterText(find.byType(TextField), 'I have hunger');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text("I'm hungry."), findsOneWidget);

    // Once turned over, the only way on is a grade.
    expect(find.text('Try again'), findsNothing);
    expect(find.byType(RecordButton), findsNothing);
    expect(find.text('Perfect'), findsOneWidget);
  });

  testWidgets('the say-it step can be skipped without recording', (
    tester,
  ) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    await tester.tap(find.text("I don't know"));
    await tester.pumpAndSettle();

    expect(find.text('NOW SAY IT'), findsOneWidget);
    expect(
      find.text('Hold the microphone and say the sentence.'),
      findsOneWidget,
    );
    // The reference to say is still on the card, with its Hear button.
    expect(find.text("I'm hungry."), findsWidgets);

    await tester.tap(find.text('Next card'));
    await tester.pumpAndSettle();
    expect(find.text('¿Dónde está la estación?'), findsOneWidget);
    // Nothing was said, so no pronunciation attempt was saved.
    expect(await (await history.database).query('attempts'), isEmpty);
  });

  group('leaving', () {
    // Pushed over a home route, so there is somewhere to go back to.
    Future<void> openPushed(WidgetTester tester, int deckId) async {
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
              child: MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecallReviewScreen(deckId: deckId),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first while cards are left', (tester) async {
      await openPushed(tester, await deck());

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Leave session?'), findsOneWidget);
      expect(find.text('Cards you graded are saved.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Tengo hambre.'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('leaves without asking once nothing is due', (tester) async {
      await openPushed(tester, await decks.createDeck(name: 'Empty'));

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Leave session?'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });
  });

  testWidgets('after the day\'s cards, more come without stopping', (
    tester,
  ) async {
    final deckId = await decks.createDeck(name: 'Small', newPerDay: 1);
    for (final (es, en) in [('Uno.', 'One.'), ('Dos.', 'Two.')]) {
      await decks.addNote(deckId: deckId, nativeText: es, references: [en]);
    }
    await tester.pumpWidget(app(deckId));
    await tester.pumpAndSettle();
    expect(find.text('Uno.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'One');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next card'));
    await tester.pumpAndSettle();
    // No "nothing due" stop: the next card is straight there.
    expect(find.text('Dos.'), findsOneWidget);
    expect(find.text('Practice more'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Two');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfect'));
    await tester.pumpAndSettle();
    // The last card still gets its say-it step before the end.
    expect(find.text('NOW SAY IT'), findsOneWidget);
    await tester.tap(find.text('Next card'));
    await tester.pumpAndSettle();
    expect(find.text('All done'), findsOneWidget);
    // Both cards were Perfect: out of the cards shown, not the deck.
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Keep going'), findsNothing);
  });

  testWidgets('a round of five ends with its Perfect share', (tester) async {
    final deckId = await decks.createDeck(name: 'Big');
    for (var i = 0; i < 6; i++) {
      await decks.addNote(
        deckId: deckId,
        nativeText: 'Frase $i.',
        references: ['Sentence $i.'],
      );
    }
    await tester.pumpWidget(app(deckId));
    await tester.pumpAndSettle();
    expect(find.text('5 left'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      if (i < 4) {
        await tester.enterText(find.byType(TextField), 'Sentence');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await tester.tap(find.text(i == 0 ? 'Partial' : 'Perfect'));
      } else {
        await tester.tap(find.text("I don't know"));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next card'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    // The sixth card, and the ones graded Wrong or Partial come back too.
    expect(find.text('Session complete'), findsNothing);
    expect(find.textContaining(' left'), findsOneWidget);
  });

  testWidgets('an answer can be saved as another way to say it', (
    tester,
  ) async {
    final deckId = await deck();
    await tester.pumpWidget(app(deckId));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), "I'm starving");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add another way'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add another way'));
    await tester.pumpAndSettle();
    // The dialog starts with the answer just written.
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, "I'm starving");
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('One of the ways to say it'), findsOneWidget);
    expect(find.text('YOURS'), findsOneWidget);
    final note = (await decks.notes(deckId)).first;
    expect(note.ownReferences, ["I'm starving"]);
    expect(note.primaryReference, "I'm hungry.");
  });

  testWidgets('an answer the card already has is not offered again', (
    tester,
  ) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'i am hungry');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('One of the ways to say it'), findsOneWidget);
    await tester.ensureVisible(find.text('Add another way'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add another way'));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
  });

  testWidgets('labels follow the deck\'s target language', (tester) async {
    final deckId = await decks.createDeck(
      name: 'Français',
      nativeLang: 'es',
      targetLang: 'fr',
    );
    await decks.addNote(
      deckId: deckId,
      nativeText: 'Hola.',
      references: ['Bonjour.'],
    );
    await tester.pumpWidget(app(deckId));
    await tester.pumpAndSettle();

    expect(find.text('HOW DO YOU SAY IT IN FRENCH?'), findsOneWidget);
    expect(find.text('Type or say it in French'), findsOneWidget);
  });

  testWidgets('the card shows the prompt in front and only the answer behind', (
    tester,
  ) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    // Front: the "your language" tag and prompt, no translation. The
    // prompt language is never named.
    expect(find.text('YOUR LANGUAGE'), findsOneWidget);
    expect(find.text('SPANISH'), findsNothing);
    expect(find.text('Tengo hambre.'), findsOneWidget);
    expect(find.text("I'm hungry."), findsNothing);

    // Tapping the card does not turn it over: that would answer for the
    // learner.
    await tester.tap(find.text('Tengo hambre.'));
    await tester.pumpAndSettle();
    expect(find.text("I'm hungry."), findsNothing);

    await tester.enterText(find.byType(TextField), 'I am hungry');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('ENGLISH'), findsOneWidget);
    expect(find.text("I'm hungry."), findsOneWidget);
    // The back does not repeat the prompt.
    expect(find.text('Tengo hambre.'), findsNothing);
    expect(find.text('YOUR LANGUAGE'), findsNothing);
  });

  testWidgets('after answering, a swipe peeks at the front and back again', (
    tester,
  ) async {
    await tester.pumpWidget(app(await deck()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'I am hungry');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Tengo hambre.'), findsNothing);
    expect(find.text('Swipe the card to see the question'), findsOneWidget);

    await tester.fling(find.text("I'm hungry."), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Tengo hambre.'), findsOneWidget);
    expect(find.text("I'm hungry."), findsNothing);
    // Only a look: the grade buttons are still waiting.
    expect(find.text('Perfect'), findsOneWidget);

    await tester.fling(find.text('Tengo hambre.'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text("I'm hungry."), findsOneWidget);
  });
}
