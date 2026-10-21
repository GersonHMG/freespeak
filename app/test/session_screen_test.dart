import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lingo_node/data/practice_history_scope.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/pronunciation/asr.dart';
import 'package:lingo_node/pronunciation/mispronounce_detector.dart';
import 'package:lingo_node/pronunciation/pronunciation_scope.dart';
import 'package:lingo_node/screens/session_screen.dart';
import 'package:lingo_node/tts/phonon_tts.dart';
import 'package:lingo_node/tts/phonon_tts_scope.dart';
import 'package:lingo_node/widgets/record_button.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// A fixed list rather than the app's real (randomly-sampled) phrase set: the
// widget under test only cares that SessionScreen renders whatever it is
// given, not what the session's actual sample happens to be.
const List<String> _testPhrases = [
  'The quick brown fox jumps over the lazy dog',
  "It's all over between us.",
  'A small forest brook flowed between the moss-covered trees.',
];
final int _phraseCount = _testPhrases.length;

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

// The session screen reads all three engines from their scopes but only
// touches them when a button is pressed, so unloaded instances (and, for the
// history store, an in-memory database) are enough to render. No-isolate
// sqflite so the store's futures resolve under the widget test's fake clock.
// Scopes sit above MaterialApp, not under its `home`, so a route the screen
// pushes (SessionCompleteScreen) is still inside them -- the same reason
// LoadingScreen nests its own Navigator under the scopes in the real app.
Widget _app() => PhononTtsScope(
  tts: PhononTts(),
  child: PronunciationScope(
    detector: MispronounceDetector(
      asr: _SilentAsr(),
      phonemize: (word) async => word,
    ),
    child: PracticeHistoryScope(
      store: PracticeHistoryStore(
        databaseFactory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
      child: const MaterialApp(home: SessionScreen(phrases: _testPhrases)),
    ),
  ),
);

/// A session pushed onto a route, the way every entry point but the loading
/// screen reaches it -- which is also what gives its AppBar a back button to
/// exercise. [showsSummary] false is the Revisit sentences / Custom Practice
/// shape: one phrase, opened from a list that finishing should return to.
Widget _pushedApp({required bool showsSummary}) => PhononTtsScope(
  tts: PhononTts(),
  child: PronunciationScope(
    detector: MispronounceDetector(
      asr: _SilentAsr(),
      phonemize: (word) async => word,
    ),
    child: PracticeHistoryScope(
      store: PracticeHistoryStore(
        databaseFactory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      ),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SessionScreen(
                      phrases: const [
                        'The quick brown fox jumps over the lazy dog',
                      ],
                      awardsPoints: false,
                      showsSummary: showsSummary,
                    ),
                  ),
                ),
                child: const Text('Revisit'),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _openPushed(
  WidgetTester tester, {
  required bool showsSummary,
}) async {
  await tester.pumpWidget(_pushedApp(showsSummary: showsSummary));
  await tester.tap(find.text('Revisit'));
  await tester.pumpAndSettle();
}

Future<void> _openRevisit(WidgetTester tester) =>
    _openPushed(tester, showsSummary: false);

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('session screen renders the first phrase', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.widgetWithText(AppBar, 'SESSION'), findsOneWidget);
    expect(
      find.textContaining('quick brown fox', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Hold to record'), findsOneWidget);
    expect(find.text('Skip phrase'), findsOneWidget);
  });

  testWidgets('skip advances to the next phrase', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.text('Skip phrase'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('all over between us', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('finishing the last phrase shows the completion screen', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    for (var i = 1; i < _phraseCount; i++) {
      await tester.tap(find.text('Skip phrase'));
      await tester.pumpAndSettle();
    }

    // Skip becomes Finish on the last phrase -- and only there.
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Skip phrase'), findsNothing);

    // Finish awaits a sqflite read (the day's points before the session).
    // The store above uses the no-isolate FFI factory so that read completes
    // on the test's fake clock; the isolate-backed one never would. The
    // completion screen then runs one-shot entrance animations; pump a fixed
    // amount rather than settling so a looping confetti overlay cannot hang
    // the test.
    await tester.tap(find.text('Finish'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Session Complete!'), findsOneWidget);
    expect(find.text('Back to Home'), findsOneWidget);
    // pushReplacement, not push: the session screen (and its Finish button)
    // is gone rather than stacked underneath.
    expect(find.text('Finish'), findsNothing);
  });

  group('one-phrase revisit', () {
    testWidgets('has no skip, finish or done button', (tester) async {
      await _openRevisit(tester);

      // A revisit is not a set: there is nothing to skip through and no
      // summary to finish into. The back arrow is the way out.
      expect(find.text('Skip phrase'), findsNothing);
      expect(find.text('Finish'), findsNothing);
      expect(find.text('Done'), findsNothing);
    });

    testWidgets('the back arrow returns to the list without confirming', (
      tester,
    ) async {
      await _openRevisit(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Leave session?'), findsNothing);
      expect(find.text('Revisit'), findsOneWidget);
      expect(find.text('Session Complete!'), findsNothing);
    });
  });

  testWidgets('a real session still confirms before leaving', (tester) async {
    // The prompt exists to protect progress that ends in a summary -- the
    // revisit cases above must not have taken it away from the set it guards.
    await _openPushed(tester, showsSummary: true);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Leave session?'), findsOneWidget);
  });

  // Pressing Record for real needs a microphone, which a widget test does not
  // have, so the button's own states are checked directly instead.
  testWidgets('record button reports recording and scoring', (tester) async {
    Widget button({required bool isRecording, required bool isScoring}) =>
        MaterialApp(
          home: Scaffold(
            body: RecordButton(
              isRecording: isRecording,
              isScoring: isScoring,
              onRecordStart: () {},
              onRecordStop: () {},
              onRecordCancel: () {},
            ),
          ),
        );

    await tester.pumpWidget(button(isRecording: false, isScoring: false));
    expect(find.text('Hold to record'), findsOneWidget);

    await tester.pumpWidget(button(isRecording: true, isScoring: false));
    expect(find.text('Slide to cancel'), findsOneWidget);

    await tester.pumpWidget(button(isRecording: false, isScoring: true));
    expect(find.text('Scoring...'), findsOneWidget);
  });
}
