// The native eSpeak call only exists on a phone, so these drive
// [EspeakPhonemizer] through its stub seam. What is under test is everything
// around that call — the punctuation carry-through and the running rune
// offsets the word spans depend on — which is the part that would otherwise
// break silently and only be noticed as a word landing at the wrong moment in
// the audio.
//
// eSpeak's IPA is passed to the model as-is, so the expectations here are
// eSpeak's own spellings: `eɪ` rather than misaki's `A`, `ɾ` rather than `T`.

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/espeak_phonemizer.dart';
import 'package:lingo_node/tts/phonemizer.dart';

/// Stands in for eSpeak: espeak-flavoured IPA for the words these tests use,
/// and a marker for anything else so an unexpected lookup is visible.
const Map<String, String> _lexicon = {
  'a': 'ə',
  "it's": 'ɪts',
  'it': 'ɪt',
  'costs': 'kɑsts',
  'joke': 'dʒoʊk',
  'the': 'ðə',
  'rain': 'ɹeɪn',
  'in': 'ɪn',
  'spain': 'speɪn',
  'water': 'wɔɾɚ',
  'bird': 'bɝd',
  'red': 'red',
  'hello': 'həloʊ',
  'world': 'wɜrld',
  '5.99': 'faɪv pɔɪnt naɪn naɪn',
};

/// What eSpeak says for a word that is the whole of its input, where that
/// differs from the word inside a phrase: alone, it carries the clause's
/// stress, so a function word comes back in its strong form.
const Map<String, String> _alone = {'a': 'ˈeɪ'};

/// Like eSpeak, takes one word or several and separates the words of its
/// answer with spaces.
String _stub(String text) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.length == 1) {
    final word = words.single.toLowerCase();
    return _alone[word] ?? _lexicon[word] ?? '??';
  }
  return words.map((w) => _lexicon[w.toLowerCase()] ?? '??').join(' ');
}

EspeakPhonemizer _phonemizer() => EspeakPhonemizer.withBackend(_stub);

/// The substring each span claims, read back out of the phoneme string.
List<String> _slices(Phonemization p) {
  final runes = p.phonemes.runes.toList();
  return [
    for (final word in p.words)
      String.fromCharCodes(runes.sublist(word.start, word.end)),
  ];
}

void main() {
  group('EspeakPhonemizer', () {
    test('needs no native library once a backend is supplied', () {
      expect(_phonemizer().isReady, isTrue);
    });

    test('joins words with a single space and closes the phrase', () async {
      final result = await _phonemizer().phonemizeAligned(
        'The rain in Spain',
        'en-us',
      );
      expect(result.phonemes, 'ðə ɹeɪn ɪn speɪn.');
    });

    test('every span points at the phonemes its word produced', () async {
      final result = await _phonemizer().phonemizeAligned(
        'The rain in Spain',
        'en-us',
      );
      expect(result.words.map((w) => w.text), <String>[
        'The',
        'rain',
        'in',
        'Spain',
      ]);
      expect(_slices(result), <String>['ðə', 'ɹeɪn', 'ɪn', 'speɪn']);
    });

    test('spans stay aligned across words of differing length', () async {
      // The offsets are tracked as the string is written rather than measured
      // afterwards. Anything that measured after the fact would put the second
      // word's span in the wrong place.
      final result = await _phonemizer().phonemizeAligned(
        'bird water',
        'en-us',
      );
      expect(result.phonemes, 'bɝd wɔɾɚ.');
      expect(_slices(result), <String>['bɝd', 'wɔɾɚ']);
    });

    test('carries punctuation through rather than phonemizing it', () async {
      final result = await _phonemizer().phonemizeAligned(
        'Hello, world!',
        'en-us',
      );
      expect(result.phonemes, 'həloʊ, wɜrld!');
      // The marks are not words, so they claim no span.
      expect(result.words.map((w) => w.text), <String>['Hello', 'world']);
      expect(_slices(result), <String>['həloʊ', 'wɜrld']);
    });

    test('adds a terminal mark only when the phrase lacks one', () async {
      final espeak = _phonemizer();
      expect((await espeak.phonemizeAligned('red', 'en-us')).phonemes, 'red.');
      expect((await espeak.phonemizeAligned('red!', 'en-us')).phonemes, 'red!');
    });

    test('keeps a decimal intact so it is read as a number', () async {
      // The mark sits between two digits, so the punctuation split leaves it
      // alone and the whole figure reaches eSpeak as one word.
      final result = await _phonemizer().phonemizeAligned('5.99', 'en-us');
      expect(result.words.single.text, '5.99');
      expect(result.phonemes, startsWith('faɪv pɔɪnt'));
    });

    test('collapses whitespace instead of emitting empty words', () async {
      final result = await _phonemizer().phonemizeAligned(
        '  the   rain  ',
        'en-us',
      );
      expect(result.phonemes, 'ðə ɹeɪn.');
      expect(result.words.length, 2);
    });

    test('passes eSpeak through untouched, character for character', () async {
      // The one guarantee that replaced the misaki rewrites: what eSpeak said
      // is what the model gets, apart from whitespace and punctuation.
      final result = await _phonemizer().phonemizeAligned('bird', 'en-us');
      expect(result.phonemes, '${_lexicon['bird']}.');
    });

    test(
      'sends a run of words in one call, so function words stay weak',
      () async {
        // Sent alone, "a" is the whole clause and takes its stress: "it's EI
        // joke". Inside the phrase it is the unstressed /ə/.
        final result = await _phonemizer().phonemizeAligned(
          "It's a joke",
          'en-us',
        );
        expect(result.phonemes, 'ɪts ə dʒoʊk.');
        expect(_slices(result), <String>['ɪts', 'ə', 'dʒoʊk']);
      },
    );

    test('a word on its own is still phonemized alone', () async {
      final result = await _phonemizer().phonemizeAligned('a', 'en-us');
      expect(result.phonemes, 'ˈeɪ.');
    });

    test('falls back to a word at a time when the counts disagree', () async {
      // "5.99" comes back as four words, so the run's answer cannot be split
      // one piece per word; every span must still land on its own word.
      final result = await _phonemizer().phonemizeAligned(
        'It costs 5.99',
        'en-us',
      );
      expect(result.words.map((w) => w.text), <String>['It', 'costs', '5.99']);
      expect(_slices(result), <String>['ɪt', 'kɑsts', 'faɪv pɔɪnt naɪn naɪn']);
    });

    test('a token with nothing speakable in it takes no span', () async {
      final result = await _phonemizer().phonemizeAligned(
        'the & rain',
        'en-us',
      );
      expect(result.phonemes, 'ðə ɹeɪn.');
      expect(result.words.map((w) => w.text), <String>['the', 'rain']);
      expect(_slices(result), <String>['ðə', 'ɹeɪn']);
    });

    test('phonemize agrees with the aligned form', () async {
      final espeak = _phonemizer();
      const text = 'Hello, world!';
      expect(
        await espeak.phonemize(text, 'en-us'),
        (await espeak.phonemizeAligned(text, 'en-us')).phonemes,
      );
    });
  });
}
