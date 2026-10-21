// Everything below the recognizer, exercised with strings instead of audio.
//
// That is the whole point of MispronounceDetector.scoreTranscript: the model
// is the part that needs a device, and it is not the part that gets the
// alignment wrong.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/pronunciation/asr.dart';
import 'package:lingo_node/pronunciation/category.dart';
import 'package:lingo_node/pronunciation/mispronounce_detector.dart';
import 'package:lingo_node/pronunciation/phoneme_alignment.dart';
import 'package:lingo_node/pronunciation/phrase_tokens.dart';
import 'package:lingo_node/pronunciation/score_system.dart';
import 'package:lingo_node/pronunciation/word_metrics.dart';
import 'package:lingo_node/pronunciation/word_timing.dart';
import 'package:lingo_node/tts/wav.dart';

/// Stands in for the recognizer. Real G2P needs asset bundles, so the tests
/// use a spelling-is-pronunciation stub: the scorer only requires that both
/// sides go through the same function, not that it is accurate.
Future<String> _spellingAsPhonemes(String word) async =>
    word.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

/// Phonemizes both sides with the stub and aligns them, the way
/// [MispronounceDetector] does before it scores anything.
Future<PhonemeAlignment> _align(
  List<String> reference,
  List<String> spoken,
) async => alignPhonemes(
  reference: [for (final word in reference) await _spellingAsPhonemes(word)],
  spoken: [for (final word in spoken) await _spellingAsPhonemes(word)],
);

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

MispronounceDetector _detector() =>
    MispronounceDetector(asr: _SilentAsr(), phonemize: _spellingAsPhonemes);

/// A transcript with no word timing — the shape most of these tests exercise,
/// since timing is its own group below.
Transcript _heard(String text) => Transcript(text: text);

/// Remembers the vocabulary it was last asked to decode against.
class _RecordingAsr implements Asr {
  List<String>? lastVocabulary;
  bool called = false;
  @override
  Future<void> ready() async {}
  @override
  Future<Transcript> transcribe(
    String wavPath, {
    List<String>? vocabulary,
  }) async {
    called = true;
    lastVocabulary = vocabulary;
    return const Transcript(text: '');
  }

  @override
  Future<void> dispose() async {}
}

/// A conformant (16 kHz mono 16-bit) but silent WAV on disk, so
/// [MispronounceDetector.score] gets past its file check without a mic.
Future<String> _silentWav() async {
  final dir = await Directory.systemTemp.createTemp('lingo_node_test');
  final path = '${dir.path}/silence.wav';
  await File(path).writeAsBytes(encodeWav(Float32List(1600), 16000));
  return path;
}

void main() {
  group('score vocabulary', () {
    test('is forwarded to the recognizer when given', () async {
      final asr = _RecordingAsr();
      final detector = MispronounceDetector(
        asr: asr,
        phonemize: _spellingAsPhonemes,
      );

      await detector.score(
        await _silentWav(),
        'beer',
        vocabulary: const ['beer', 'bear'],
      );

      expect(asr.called, isTrue);
      expect(asr.lastVocabulary, ['beer', 'bear']);
    });

    test('is absent when not given, so sessions use the full model', () async {
      final asr = _RecordingAsr();
      final detector = MispronounceDetector(
        asr: asr,
        phonemize: _spellingAsPhonemes,
      );

      await detector.score(await _silentWav(), 'beer');

      expect(asr.called, isTrue);
      expect(asr.lastVocabulary, isNull);
    });
  });

  group('editDistance', () {
    test('is zero for identical strings', () {
      expect(editDistance('water', 'water'), 0);
    });

    test('counts each edit once', () {
      expect(editDistance('kitten', 'sitting'), 3);
    });

    test('falls back to length against an empty string', () {
      expect(editDistance('', 'abc'), 3);
      expect(editDistance('abc', ''), 3);
    });

    test('counts a multi-byte phoneme as one substitution', () {
      // ɹ and ɾ are both outside the BMP-adjacent ASCII range; a UTF-16
      // implementation would still get this right, but a byte-wise one would
      // report 2 for a single wrong sound.
      expect(editDistance('wɔɾəɹ', 'wɔTəɹ'), 1);
    });
  });

  group('alignRunes', () {
    int charged(List<EditStep> path) =>
        path.where((s) => s.op != EditOp.match).length;

    test('matches every rune of an identical pair', () {
      final path = alignRunes('water', 'water');
      expect(path.length, 5);
      expect(path.every((s) => s.op == EditOp.match), isTrue);
    });

    test('charges the same total the scalar distance reports', () {
      expect(charged(alignRunes('kitten', 'sitting')), 3);
    });

    test('consumes the reference strictly left to right', () {
      // The whole attribution scheme rests on this: a caller walking the path
      // keeps its own cursor into `a`, which is only meaningful if `a` is
      // consumed in order.
      final consumed = [
        for (final step in alignRunes('kitten', 'sitting'))
          if (step.aIndex >= 0) step.aIndex,
      ];
      expect(consumed, [0, 1, 2, 3, 4, 5]);
    });

    test(
      'reports an unspoken rune as a deletion and an extra as an insert',
      () {
        final dropped = alignRunes('ab', 'b');
        expect(dropped.where((s) => s.op == EditOp.delete).length, 1);
        expect(dropped.where((s) => s.op == EditOp.match).length, 1);

        final added = alignRunes('b', 'ab');
        expect(added.where((s) => s.op == EditOp.insert).length, 1);
        expect(added.where((s) => s.op == EditOp.match).length, 1);
      },
    );

    test('free end gaps drop leading and trailing extras from the path', () {
      final path = alignRunes('cat', 'xxcatyy', freeEndGaps: true);
      expect(path.length, 3);
      expect(path.every((s) => s.op == EditOp.match), isTrue);
    });

    test('free end gaps do not excuse an extra in the middle', () {
      expect(charged(alignRunes('cat', 'caxt', freeEndGaps: true)), 1);
    });

    test('free end gaps never make a reference rune free', () {
      // Nothing was said at all; every sound of the phrase is still owed.
      expect(charged(alignRunes('cat', '', freeEndGaps: true)), 3);
    });
  });

  group('alignPhonemes', () {
    // The test phonemizer is spelling, so these read as words on purpose.
    PhonemeAlignment align(List<String> reference, List<String> spoken) =>
        alignPhonemes(reference: reference, spoken: spoken);

    test('charges nothing and credits each word on a clean read', () {
      final result = align(['the', 'quick', 'fox'], ['the', 'quick', 'fox']);

      expect(result.totalMismatches, 0);
      expect(result.totalPhonemes, 11);
      expect(
        [for (final w in result.words) w.spokenPhonemes],
        ['the', 'quick', 'fox'],
      );
      expect(
        [for (final w in result.words) w.spokenWordIndices],
        [
          [0],
          [1],
          [2],
        ],
      );
    });

    test('a word dropped mid-phrase is the only word charged for it', () {
      // The regression this whole alignment exists to fix: the old word-level
      // DTW had no way to skip a column, so "fox" was shoved into "quick"'s
      // slot and every later word was credited one place early.
      final result = align(['the', 'quick', 'fox'], ['the', 'fox']);

      expect(result.words[0].mismatches, 0);
      expect(result.words[0].spokenWordIndices, [0]);

      expect(result.words[1].wasSkipped, isTrue);
      expect(result.words[1].spokenPhonemes, isEmpty);
      expect(result.words[1].mismatches, 5);

      expect(result.words[2].mismatches, 0);
      expect(result.words[2].spokenWordIndices, [1]);
    });

    test('total mismatches equal the distance over the joined sequences', () {
      // The property that keeps the phrase score a real ratio rather than an
      // average of per-word averages.
      final result = align(['the', 'quick', 'fox'], ['the', 'kwik', 'fox']);

      expect(result.totalMismatches, editDistance('thequickfox', 'thekwikfox'));
    });

    test(
      'an inserted sound at a boundary is charged to the word it precedes',
      () {
        final result = align(['ab', 'cd'], ['ab', 'xcd']);

        expect(result.words[0].mismatches, 0);
        expect(result.words[1].mismatches, 1);
      },
    );

    test('speech past the end of the phrase costs nothing', () {
      final result = align(['ab'], ['ab', 'zzz']);

      expect(result.totalMismatches, 0);
      expect(result.words[0].spokenWordIndices, [0]);
    });

    test('a word run together with its neighbour credits both speakers', () {
      // "a napple" for "an apple" — one heard word straddles two reference
      // words, which word-level matching could only ever report as one of the
      // two being missing.
      final result = align(['an', 'apple'], ['a', 'napple']);

      expect(result.totalMismatches, 0);
      expect(result.words[0].spokenWordIndices, [0, 1]);
      expect(result.words[1].spokenWordIndices, [1]);
    });

    test('a word with no phonemes is neither scored nor charged', () {
      final result = align(['ab', '.', 'cd'], ['ab', 'cd']);

      expect(result.words[1].phonemes, 0);
      expect(result.words[1].mismatches, 0);
      expect(result.totalMismatches, 0);
      expect(result.totalPhonemes, 4);
    });

    test('silence charges every phoneme of every word', () {
      final result = align(['the', 'fox'], const []);

      expect(result.totalMismatches, 6);
      expect(result.words.every((w) => w.wasSkipped), isTrue);
    });

    test('keeps /s/, which the old normalizer silently ate', () {
      expect(normalizePhonemes('sɪt'), 'sɪt');
      expect(normalizePhonemes('ˈsiː kwəns'), 'siːkwəns');
    });
  });

  group('tokenizePhrase', () {
    test('round-trips the original text', () {
      const text = 'She sells seashells by the sea shore.';
      expect(tokenizePhrase(text).map((t) => t.raw).join(), text);
    });

    test('gives one token per word for ordinary text', () {
      expect(phraseWords('the quick brown fox').length, 4);
    });

    test('survives irregular whitespace without losing a word', () {
      final words = phraseWords('  two   spaces  ');
      expect(words.map((w) => w.word), ['two', 'spaces']);
    });
  });

  group('normalizeWord', () {
    test('strips the punctuation a word wears in a sentence', () {
      expect(normalizeWord('Can?'), 'can');
      expect(normalizeWord('leave.'), 'leave');
      expect(normalizeWord('Book'), 'book');
      expect(normalizeWord('"quoted,"'), 'quoted');
    });

    test('keeps punctuation that is part of the word', () {
      // Stripping these would change the word rather than tidy it: "its" is a
      // different word from "it's", and "mosscovered" is not a word at all.
      expect(normalizeWord("It's"), "it's");
      expect(normalizeWord('moss-covered'), 'moss-covered');
    });

    test('leaves an already-bare word alone', () {
      expect(normalizeWord('book'), 'book');
    });

    test('empties a token that was only punctuation', () {
      // The caller's signal that there is no word here to store or drill.
      expect(normalizeWord('--'), isEmpty);
      expect(normalizeWord('...'), isEmpty);
    });
  });

  // Step 3 in isolation: given an alignment (not computed here — scoreWords
  // does not decide who matched whom, only how well), grade each word. No
  // ASR, no timing, nothing but text and a phonemizer stub.
  group('scoreWords', () {
    test('grades a clean read as fully correct', () async {
      const words = ['the', 'quick', 'fox'];
      final result = scoreWords(words, words, await _align(words, words));

      expect(result.overall, 100);
      expect(result.words.every((w) => !w.wasSkipped), isTrue);
    });

    test('a word nothing landed on carries the sentinel in .spoken', () async {
      // The empty-string the alignment uses for "drew no phonemes" must not
      // leak into WordScore.spoken -- that was a real bug caught while writing
      // the original refactor, and the sentinel is what the UI keys off.
      const reference = ['the', 'quick', 'fox'];
      const spoken = ['the', 'quick'];
      final result = scoreWords(
        reference,
        spoken,
        await _align(reference, spoken),
      );

      final fox = result.words[2];
      expect(fox.wasSkipped, isTrue);
      expect(fox.spoken, wordNotFoundToken);
      expect(fox.accuracy, 0);
    });

    test('names every heard word a reference word drew from', () async {
      // Two heard words feeding one reference word is exactly what word-level
      // matching could not express.
      const reference = ['an', 'apple'];
      const spoken = ['a', 'napple'];
      final result = scoreWords(
        reference,
        spoken,
        await _align(reference, spoken),
      );

      expect(result.words[0].spoken, 'a napple');
      expect(result.overall, 100);
    });

    test('one WordScore per reference word, in order', () async {
      const reference = ['she', 'sells', 'seashells'];
      const spoken = ['she', 'sells', 'shells'];
      final result = scoreWords(
        reference,
        spoken,
        await _align(reference, spoken),
      );

      expect(result.words.map((w) => w.reference), reference);
    });
  });

  // Step 4 in isolation: given the same shape of alignment, locate a time
  // range per word -- no phonemizing, no accuracy math, nothing but indices
  // and durations.
  group('mapWordTimings', () {
    const oneSecond = Duration(seconds: 1);
    const twoSeconds = Duration(seconds: 2);

    test('maps a clean read one time range per word', () async {
      const words = ['the', 'quick', 'fox'];
      final alignment = await _align(words, words);
      final timings = mapWordTimings(
        alignment: alignment,
        timedWords: [
          TimedWord(text: 'the', start: Duration.zero, end: oneSecond),
          TimedWord(text: 'quick', start: oneSecond, end: twoSeconds),
          TimedWord(
            text: 'fox',
            start: twoSeconds,
            end: const Duration(seconds: 3),
          ),
        ],
        spokenWordCount: 3,
        hasRecording: true,
      );

      expect(timings.every((t) => t.hasClip), isTrue);
      expect(timings[1].start, oneSecond);
      expect(timings[1].end, twoSeconds);
    });

    test('a word nothing landed on has no clip', () async {
      final alignment = await _align(['the', 'quick', 'fox'], ['the', 'quick']);
      final timings = mapWordTimings(
        alignment: alignment,
        timedWords: [
          TimedWord(text: 'the', start: Duration.zero, end: oneSecond),
          TimedWord(text: 'quick', start: oneSecond, end: twoSeconds),
        ],
        spokenWordCount: 2,
        hasRecording: true,
      );

      expect(timings[0].hasClip, isTrue); // "the"
      expect(timings[1].hasClip, isTrue); // "quick"
      expect(timings[2].hasClip, isFalse); // "fox", skipped
    });

    test('drops every timing when there is no recording behind them', () async {
      const words = ['the', 'quick', 'fox'];
      final alignment = await _align(words, words);
      final timings = mapWordTimings(
        alignment: alignment,
        timedWords: [
          TimedWord(text: 'the', start: Duration.zero, end: oneSecond),
          TimedWord(text: 'quick', start: oneSecond, end: twoSeconds),
          TimedWord(
            text: 'fox',
            start: twoSeconds,
            end: const Duration(seconds: 3),
          ),
        ],
        spokenWordCount: 3,
        hasRecording: false,
      );

      expect(timings.every((t) => !t.hasClip), isTrue);
    });

    test('drops every timing on a segment/word count mismatch', () async {
      const words = ['the', 'quick', 'fox'];
      final alignment = await _align(words, words);
      final timings = mapWordTimings(
        alignment: alignment,
        // Two segments for a three-word transcript: the recognizer's own
        // word-splitting disagreed with the plain-text split somewhere.
        timedWords: [
          TimedWord(text: 'the', start: Duration.zero, end: oneSecond),
          TimedWord(
            text: 'quick fox',
            start: oneSecond,
            end: const Duration(seconds: 3),
          ),
        ],
        spokenWordCount: 3,
        hasRecording: true,
      );

      expect(timings.every((t) => !t.hasClip), isTrue);
    });
  });

  group('categoryForAccuracy', () {
    test('grades against the 80/60 boundaries, inclusive on the low side', () {
      expect(categoryForAccuracy(100), PronunciationCategory.good);
      expect(categoryForAccuracy(80), PronunciationCategory.good);
      expect(categoryForAccuracy(79.9), PronunciationCategory.mediocre);
      expect(categoryForAccuracy(65), PronunciationCategory.mediocre);
      expect(categoryForAccuracy(60), PronunciationCategory.mediocre);
      expect(categoryForAccuracy(59.9), PronunciationCategory.bad);
      expect(categoryForAccuracy(0), PronunciationCategory.bad);
    });

    test('needsWork covers everything short of good', () {
      expect(PronunciationCategory.good.needsWork, isFalse);
      expect(PronunciationCategory.mediocre.needsWork, isTrue);
      expect(PronunciationCategory.bad.needsWork, isTrue);
    });
  });

  group('lettersTranscribedCorrectly', () {
    test('flags the letters that survived', () {
      expect(lettersTranscribedCorrectly('cat', 'cot'), [true, false, true]);
    });

    test('marks the tail wrong when the heard word is shorter', () {
      expect(lettersTranscribedCorrectly('water', 'wat'), [
        true,
        true,
        true,
        false,
        false,
      ]);
    });
  });

  group('scoreTranscript', () {
    test('scores a perfect read at 100', () async {
      final result = await _detector().scoreTranscript(
        _heard('the quick brown fox'),
        'the quick brown fox',
      );
      expect(result.overall, 100);
      expect(result.mispronounced, isEmpty);
    });

    test('is case and punctuation insensitive', () async {
      final result = await _detector().scoreTranscript(
        _heard('The quick brown fox!'),
        'the quick brown fox',
      );
      expect(result.overall, 100);
    });

    test('penalizes only the word that was wrong', () async {
      final result = await _detector().scoreTranscript(
        _heard('the kwik brown fox'),
        'the quick brown fox',
      );

      expect(result.words[1].needsWork, isTrue);
      expect(result.words[0].needsWork, isFalse);
      expect(result.words[2].needsWork, isFalse);
      expect(result.words[3].needsWork, isFalse);
      expect(result.overall, lessThan(100));
    });

    test(
      'reports a word skipped at the end of the phrase as skipped',
      () async {
        final result = await _detector().scoreTranscript(
          _heard('the quick brown'),
          'the quick brown fox',
        );

        final fox = result.words[3];
        expect(fox.wasSkipped, isTrue);
        expect(fox.accuracy, 0);
        expect(fox.letters, everyElement(isFalse));
      },
    );

    test('a mid-phrase skip is reported where it happened', () async {
      // The old word-level DTW could not skip a reference word except at the
      // very end, so it shoved "the" into "quick"'s slot and reported no skip
      // at all. Phoneme alignment deletes the sounds of "quick" in place,
      // which costs "quick" and leaves its neighbours alone.
      final result = await _detector().scoreTranscript(
        _heard('the brown fox'),
        'the quick brown fox',
      );

      final quick = result.words[1];
      expect(quick.wasSkipped, isTrue);
      expect(quick.spoken, wordNotFoundToken);
      expect(quick.accuracy, 0);

      expect(result.words[0].needsWork, isFalse);
      expect(result.words[2].needsWork, isFalse);
      expect(result.words[3].needsWork, isFalse);
    });

    test('returns a zero, not a NaN, when nothing was heard', () async {
      final result = await _detector().scoreTranscript(
        _heard(''),
        'the quick brown fox',
      );
      expect(result.overall, 0);
      expect(result.words, hasLength(4));
      expect(result.mispronounced, hasLength(4));
    });

    test('keeps one score per reference word', () async {
      const phrase = 'she sells seashells by the sea shore';
      final result = await _detector().scoreTranscript(
        _heard('she sells shells'),
        phrase,
      );
      expect(result.words, hasLength(phraseWords(phrase).length));
    });

    test('token indices line up with what SpokenText renders', () async {
      const phrase = 'the quick brown fox';
      final result = await _detector().scoreTranscript(_heard(phrase), phrase);
      final tokens = tokenizePhrase(phrase);

      for (final word in result.words) {
        expect(tokens[word.tokenIndex].word, word.word);
        expect(result.wordAt(word.tokenIndex), same(word));
      }
    });
  });

  // Word timing: what lets a second tap on a word play back exactly the slice
  // of the recording where the learner said it. This is the phoneme
  // alignment's spokenWordIndices reused for a second purpose (see
  // MispronounceDetector's header comment) rather than new alignment logic, so
  // these tests are mostly about the plumbing around it: the timing survives
  // when everything lines up, and — just as important — it is dropped rather
  // than guessed at when it does not.
  group('word timing', () {
    const phrase = 'the quick brown fox';
    const oneSecond = Duration(seconds: 1);
    const twoSeconds = Duration(seconds: 2);

    Transcript timed(List<(String, Duration, Duration)> words) => Transcript(
      text: words.map((w) => w.$1).join(' '),
      words: [
        for (final w in words) TimedWord(text: w.$1, start: w.$2, end: w.$3),
      ],
    );

    test('carries a clean read\'s timing onto its matching word', () async {
      final transcript = timed([
        ('the', Duration.zero, oneSecond),
        ('quick', oneSecond, twoSeconds),
        ('brown', twoSeconds, const Duration(seconds: 3)),
        ('fox', const Duration(seconds: 3), const Duration(seconds: 4)),
      ]);

      final result = await _detector().scoreTranscript(
        transcript,
        phrase,
        recordingPath: '/tmp/attempt.wav',
      );

      final quick = result.words[1];
      expect(quick.hasSpokenClip, isTrue);
      expect(quick.spokenStart, oneSecond);
      expect(quick.spokenEnd, twoSeconds);
      expect(result.recordingPath, '/tmp/attempt.wav');
    });

    test('a word that was not said has no clip to play', () async {
      // "quick" was not said, so there is no audio of it to cut. The old
      // word-level alignment had to hand this slot some real spoken word and
      // ended up playing back "the" when the learner tapped "quick".
      final transcript = timed([
        ('the', Duration.zero, oneSecond),
        ('brown', oneSecond, twoSeconds),
        ('fox', twoSeconds, const Duration(seconds: 3)),
      ]);

      final result = await _detector().scoreTranscript(
        transcript,
        phrase,
        recordingPath: '/tmp/attempt.wav',
      );

      final quick = result.words[1];
      expect(quick.hasSpokenClip, isFalse);

      final brown = result.words[2];
      expect(brown.hasSpokenClip, isTrue);
      expect(brown.spokenStart, oneSecond);
      expect(brown.spokenEnd, twoSeconds);
    });

    test('has no clip for a word with no recording behind it', () async {
      // Same transcript as the clean-read case, but scored without a
      // recordingPath -- the shape every existing unit test above uses.
      final transcript = timed([
        ('the', Duration.zero, oneSecond),
        ('quick', oneSecond, twoSeconds),
        ('brown', twoSeconds, const Duration(seconds: 3)),
        ('fox', const Duration(seconds: 3), const Duration(seconds: 4)),
      ]);

      final result = await _detector().scoreTranscript(transcript, phrase);

      expect(result.recordingPath, isNull);
      expect(result.words.every((w) => !w.hasSpokenClip), isTrue);
    });

    test(
      'drops timing rather than pairing it by guesswork on a mismatch',
      () async {
        // Three timed segments for a four-word transcript: the recognizer's own
        // word-splitting disagreed with the plain-text split somewhere. No
        // index in `words` can be trusted to mean the same word in both, so
        // none of it should be used.
        final mismatched = Transcript(
          text: 'the quick brown fox',
          words: [
            TimedWord(text: 'the', start: Duration.zero, end: oneSecond),
            TimedWord(text: 'quick', start: oneSecond, end: twoSeconds),
            TimedWord(
              text: 'brown fox',
              start: twoSeconds,
              end: const Duration(seconds: 4),
            ),
          ],
        );

        final result = await _detector().scoreTranscript(
          mismatched,
          phrase,
          recordingPath: '/tmp/attempt.wav',
        );

        expect(result.words.every((w) => !w.hasSpokenClip), isTrue);
      },
    );
  });
}
