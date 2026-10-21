import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/tts/spelling_syllables.dart';
import 'package:lingo_node/tts/syllabifier.dart';

List<String>? _spell(String word, String ipa) =>
    spellSyllables(word, syllabify(ipa));

void main() {
  group('spellSyllables', () {
    test('follows the phonemic boundaries', () {
      expect(_spell('however', 'haʊˈɛvɚ'), ['how', 'ev', 'er']);
      expect(_spell('water', 'wˈɔːɾɚ'), ['wa', 'ter']);
      expect(_spell('wonderful', 'wˈʌndɚfəl'), ['won', 'der', 'ful']);
    });

    test('x spells two sounds', () {
      expect(_spell('extra', 'ˈɛkstɹə'), ['ex', 'tra']);
    });

    test('doubled consonants split down the middle', () {
      expect(_spell('better', 'bˈɛɾɚ'), ['bet', 'ter']);
      expect(_spell('little', 'lˈɪɾəl'), ['lit', 'tle']);
    });

    test('consonant + le stays together', () {
      expect(_spell('table', 'tˈeɪbəl'), ['ta', 'ble']);
    });

    test('a silent final e is not a syllable', () {
      expect(_spell('make', 'mˈeɪk'), ['make']);
      expect(_spell('became', 'bɪkˈeɪm'), ['be', 'came']);
    });

    test('gives up when the letters cannot match the sounds', () {
      expect(_spell('idea', 'aɪdˈiːə'), isNull);
      expect(_spell("don't", 'dˈoʊnt'), ["don't"]);
      expect(_spell("o'clock", 'əklˈɑːk'), isNull);
    });
  });
}
