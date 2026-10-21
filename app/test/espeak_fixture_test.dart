// The full phonemizer pipeline, driven by what eSpeak-NG actually said.
//
// These are the assertions that used to live against MalsamiPhonemizer in
// tts_test.dart: real IPA in, function words left unstressed, numbers
// expanded. They were the only host-runnable check on a
// real G2P, so they are carried over rather than lost with it.
//
// The catch is that eSpeak only exists on a phone. Rather than stub it — which
// would test the stub — the words are captured on a device once and replayed
// here. While the fixture is empty every test in this file skips itself and
// says how to fill it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/espeak_phonemizer.dart';

/// The captured words, or an empty map if the fixture has not been filled.
Map<String, String> _loadFixture() {
  final file = File('test/fixtures/espeak_en_us.json');
  if (!file.existsSync()) return const {};
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final words = json['words'] as Map<String, dynamic>? ?? const {};
  return words.map((k, v) => MapEntry(k, v as String));
}

/// The phrases the fixture is captured for, matching `phrases` in the JSON
/// and `_fixturePhrases` in the TTS debugger.
const List<String> _phrases = [
  'Hello world!',
  'the cat sat on a mat',
  r'It costs $5.99',
  'thirty little water bottles',
  'The rain in Spain stays mainly in the plain',
];

void main() {
  final fixture = _loadFixture();

  // A word the fixture does not have is a capture that has gone stale against
  // the phrases below — louder as a failure than as a quiet empty string.
  String backend(String word) {
    final captured = fixture[word.toLowerCase()];
    if (captured == null) {
      fail(
        'No captured eSpeak output for "$word". Re-capture the fixture: '
        'run on a device, TTS debugger, "Copy fixture JSON".',
      );
    }
    return captured;
  }

  final skip = fixture.isEmpty
      ? 'test/fixtures/espeak_en_us.json is empty — capture it on a device '
            'first (TTS debugger, "Copy fixture JSON"). These assertions need '
            'real eSpeak output; stubbing them would test the stub.'
      : null;

  group('EspeakPhonemizer, on captured eSpeak output', () {
    late EspeakPhonemizer espeak;

    setUp(() {
      espeak = EspeakPhonemizer.withBackend(backend);
    });

    test('produces IPA and preserves punctuation', () async {
      final phonemes = await espeak.phonemize('Hello world!', 'en-us');

      expect(phonemes, isNotEmpty);
      expect(phonemes, endsWith('!'));
    });

    test('leaves function words unstressed', () async {
      // Carried over from malsami, and now the sharper test of the two:
      // malsami destressed function words from its lexicon, eSpeak has to do
      // it from rules, and this is where per-word phonemization could cost us
      // — a word phonemized alone has no sentence to be unstressed in.
      final phonemes = await espeak.phonemize('the cat sat on a mat', 'en-us');
      final stresses = 'ˈ'.allMatches(phonemes).length;
      expect(stresses, lessThan(4)); // cat, sat, mat — not the/on/a
    });

    test('expands money rather than dropping the unit', () async {
      // malsami dropped this phrase's figure entirely ("ɪt kˈɔsts."). eSpeak
      // expands currency itself, which is why the $ survives the word cleaner.
      final phonemes = await espeak.phonemize(r'It costs $5.99', 'en-us');

      expect(phonemes, isNotEmpty);
      // Whatever "dollars" comes out as, the figure must not vanish the way
      // it did before.
      expect(phonemes.split(' ').length, greaterThan(3));
    });

    test('keeps eSpeak’s own spellings, unrewritten', () async {
      // The app feeds the model eSpeak's notation, so its markers should
      // survive rather than being compressed into misaki's.
      final phonemes = await espeak.phonemize('thirty little water', 'en-us');
      expect(
        phonemes,
        equals(
          '${[backend('thirty'), backend('little'), backend('water')].join(' ')}.',
        ),
      );
    });

    test('every word of every captured phrase survives to a token', () async {
      for (final phrase in _phrases) {
        final aligned = await espeak.phonemizeAligned(phrase, 'en-us');
        final spoken = phrase
            .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .length;
        expect(
          aligned.words.length,
          spoken,
          reason: 'a word of "$phrase" produced no phonemes at all',
        );
      }
    });
  }, skip: skip);
}
