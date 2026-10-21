import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/syllabifier.dart';

List<String> _split(String ipa) => [for (final s in syllabify(ipa)) s.phonemes];

void main() {
  group('syllabify', () {
    test('however: stressed lax vowel keeps its consonant', () {
      expect(_split('haʊˈɛvɚ'), ['haʊ', 'ˈɛv', 'ɚ']);
    });

    test('maximal onset takes the whole legal cluster', () {
      expect(_split('ˈɛkstɹə'), ['ˈɛk', 'stɹə']);
      expect(_split('bɪɡˈɪn'), ['bɪ', 'ɡˈɪn']);
    });

    test('long vowels may end a stressed syllable', () {
      expect(_split('wˈɔːɾɚ'), ['wˈɔː', 'ɾɚ']);
    });

    test('ŋ never starts a syllable', () {
      expect(_split('sˈɪŋɚ'), ['sˈɪŋ', 'ɚ']);
    });

    test('syllabic consonants are nuclei', () {
      expect(_split('bˈʌʔn̩'), ['bˈʌʔ', 'n̩']);
    });

    test('diphthongs are one nucleus, other vowel pairs are two', () {
      expect(_split('fˈaɪɚ'), ['fˈaɪ', 'ɚ']);
      expect(_split('bˈoʊt'), ['bˈoʊt']);
    });

    test('affricates are not split', () {
      expect(_split('pˈɪktʃɚ'), ['pˈɪk', 'tʃɚ']);
    });

    test('three syllables with secondary stress', () {
      expect(_split('wˈʌndɚfəl'), ['wˈʌn', 'dɚ', 'fəl']);
      final syllables = syllabify('ˌʌndɚstˈænd');
      expect([for (final s in syllables) s.phonemes], ['ˌʌn', 'dɚ', 'stˈænd']);
      expect(
        [for (final s in syllables) s.stress],
        [SyllableStress.secondary, SyllableStress.none, SyllableStress.primary],
      );
    });

    test('syllables cover every rune in order', () {
      const ipa = 'ˌɪntɚnˈæʃənəl';
      final syllables = syllabify(ipa);
      expect(syllables.first.start, 0);
      expect(syllables.last.end, ipa.runes.length);
      for (var i = 1; i < syllables.length; i++) {
        expect(syllables[i].start, syllables[i - 1].end);
      }
      expect(syllables.map((s) => s.phonemes).join(), ipa);
    });

    test('a word with no vowel is one syllable, an empty one none', () {
      expect(_split('hm'), ['hm']);
      expect(syllabify(''), isEmpty);
    });
  });
}
