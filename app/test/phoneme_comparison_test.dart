// The IPA the learner reads after an attempt: what the phrase should sound
// like, and what they actually said.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/pronunciation/asr.dart';
import 'package:lingo_node/pronunciation/mispronounce_detector.dart';
import 'package:lingo_node/pronunciation/pronunciation_result.dart';
import 'package:lingo_node/widgets/phoneme_comparison.dart';

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

/// Spelling as pronunciation, so the IPA in these expectations reads as words.
Future<String> _spellingAsPhonemes(String word) async =>
    word.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

Future<PronunciationResult> _score(String heard, String reference) =>
    MispronounceDetector(
      asr: _SilentAsr(),
      phonemize: _spellingAsPhonemes,
    ).scoreTranscript(Transcript(text: heard), reference);

Future<void> _pump(
  WidgetTester tester,
  PronunciationResult result, {
  double width = 400,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: PhonemeComparison(result: result),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows both sides of a misread word', (tester) async {
    await _pump(
      tester,
      await _score('the kwik brown fox', 'the quick brown fox'),
    );

    expect(find.text('TARGET'), findsOneWidget);
    expect(find.text('YOU SAID'), findsOneWidget);
    expect(
      find.textContaining('quick', findRichText: true),
      findsOneWidget,
      reason: 'the target row must carry the reference phonemes',
    );
    expect(
      find.textContaining('kwik', findRichText: true),
      findsOneWidget,
      reason: 'the spoken row must carry what was actually said',
    );
  });

  testWidgets('marks a word that was never said rather than closing the gap', (
    tester,
  ) async {
    await _pump(tester, await _score('the brown fox', 'the quick brown fox'));

    // Without a placeholder the spoken row would read "the brown fox" against
    // a four-word target and every column after the drop would look wrong.
    expect(find.textContaining('·', findRichText: true), findsOneWidget);
  });

  testWidgets('wraps instead of overflowing when the phrase is long', (
    tester,
  ) async {
    const phrase =
        'A small forest brook flowed between the moss covered trees and '
        'carried the autumn leaves away toward the valley below';

    await _pump(tester, await _score(phrase, phrase), width: 220);

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when no word has phonemes', (tester) async {
    await _pump(tester, await _score('', ''));

    expect(find.text('TARGET'), findsNothing);
  });
}
