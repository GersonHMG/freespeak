import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lingo_node/data/practice_history_scope.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/pronunciation/asr.dart';
import 'package:lingo_node/pronunciation/mispronounce_detector.dart';
import 'package:lingo_node/pronunciation/pronunciation_scope.dart';
import 'package:lingo_node/screens/practice_screen.dart';
import 'package:lingo_node/tts/phonon_tts.dart';
import 'package:lingo_node/tts/phonon_tts_scope.dart';
import 'package:lingo_node/widgets/slow_hear_button.dart';
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

// Same scaffolding as session_screen_test.dart: unloaded engines are enough
// to render, since nothing runs until a button is held. Scopes sit above
// MaterialApp so the drill's pushed summary route stays inside them.
Widget _app(Widget screen) => PhononTtsScope(
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
      child: MaterialApp(home: screen),
    ),
  ),
);

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets(
    'single-word mode shows the word and an attempt counter, no advance button',
    (tester) async {
      await tester.pumpWidget(_app(PracticeScreen.singleWord('beer')));

      expect(find.widgetWithText(AppBar, 'PRACTICE'), findsOneWidget);
      expect(find.text('beer', findRichText: true), findsOneWidget);
      expect(find.text('NO ATTEMPTS YET'), findsOneWidget);
      expect(find.text('Hold to record'), findsOneWidget);
      // The learner drills one word as long as they like and leaves by the
      // back arrow; only drill mode advances through a set.
      expect(find.text('Done'), findsNothing);
      expect(find.text('Next word'), findsNothing);
      expect(find.text('Finish'), findsNothing);
    },
  );

  testWidgets('drill mode steps through its words to a summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const PracticeScreen.drill(['beer', 'world', 'flat'])),
    );

    expect(find.text('beer', findRichText: true), findsOneWidget);
    expect(find.text('Next word'), findsOneWidget);

    await tester.tap(find.text('Next word'));
    await tester.pumpAndSettle();
    expect(find.text('world', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Next word'));
    await tester.pumpAndSettle();
    expect(find.text('flat', findRichText: true), findsOneWidget);
    // Last word: the advance button becomes Finish, and only there.
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Next word'), findsNothing);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(find.text('Practice Complete!'), findsOneWidget);
    // Nothing was recorded, and the summary says so instead of showing 0%.
    expect(find.text('No words recorded this time.'), findsOneWidget);
    expect(find.text('Back to Home'), findsOneWidget);
    // pushReplacement: the drill itself is gone.
    expect(find.text('Finish'), findsNothing);
  });

  testWidgets('the slow syllable button is shown only when asked for', (
    tester,
  ) async {
    await tester.pumpWidget(_app(PracticeScreen.singleWord('however')));
    expect(find.byType(SlowHearButton), findsNothing);

    // Custom Practice's single words, like Word Rematch, get it.
    await tester.pumpWidget(
      _app(PracticeScreen.singleWord('however', showsSyllables: true)),
    );
    expect(find.byType(SlowHearButton), findsOneWidget);

    await tester.pumpWidget(_app(const PracticeScreen.drill(['beer'])));
    expect(find.byType(SlowHearButton), findsOneWidget);
  });
}
