// The pipeline, end to end: a recording and the phrase it was meant to be.
//
// Four steps, each a named function this file only conducts:
//
//   1. record      — the learner's attempt, as a WAV file    [PronunciationRecorder]
//   2. recognize   — audio -> transcript + word timestamps   [Asr.transcribe]
//   3. score       — text/phonemes -> a grade per word       [scoreWords]
//   4. map timing  — the same alignment -> a clip per word   [mapWordTimings]
//
// Recording (1) happens before this class is ever called — [score] starts
// from a WAV path. Recognition (2) is a single call to whichever [Asr] this
// was built with. Steps 3 and 4 are the two that used to be tangled together
// in one loop; they are siblings now, not a sequence: both are computed from
// the same phoneme alignment ([alignPhonemes], step "2.5" in spirit — who
// matched whom — shared by both 3 and 4 rather than owned by either), and
// neither reads the other's output. [_merge] is what stitches their two
// parallel lists back into the single [ScoredWord] list the UI reads.
//
// Only step 2's recognizer and step 3's phonemizer touch the outside world;
// both arrive as constructor arguments, so [scoreTranscript] — steps 3 and 4,
// plus the merge — is pure and testable with strings, no audio or model
// required.

import 'package:flutter/foundation.dart';

import 'asr.dart';
import 'phoneme_alignment.dart';
import 'phrase_tokens.dart';
import 'pronunciation_result.dart';
import 'score_system.dart';
import 'wav_pcm.dart';
import 'word_timing.dart';

class MispronounceDetector {
  MispronounceDetector({required Asr asr, required Grapheme2Phoneme phonemize})
    : _asr = asr,
      _phonemize = phonemize;

  final Asr _asr;
  final Grapheme2Phoneme _phonemize;

  /// Phonemizations, by word. A practice session repeats the same phrase and
  /// the same common words constantly, and G2P is dictionary lookups plus a
  /// rule-based fallback — cheap, but not so cheap it should run twice for
  /// "the".
  final Map<String, String> _phonemeCache = <String, String>{};

  static const int _maxCachedPhonemizations = 512;

  /// Warms up the recognizer. Worth calling before the first recording: the
  /// model load is seconds, and paying for it after the learner has already
  /// spoken reads as the scorer being slow.
  Future<void> ready() => _asr.ready();

  Future<String> _phonemesFor(String word) async {
    final key = word.toLowerCase();
    final cached = _phonemeCache[key];
    if (cached != null) return cached;

    final phonemes = await _phonemize(word);
    if (_phonemeCache.length >= _maxCachedPhonemizations) {
      _phonemeCache.remove(_phonemeCache.keys.first);
    }
    _phonemeCache[key] = phonemes;
    return phonemes;
  }

  /// Step 2 onward: scores the recording at [wavPath] against [referenceText].
  ///
  /// [vocabulary] is forwarded to [Asr.transcribe]; see there for what it
  /// does and why the Practice drill passes one.
  Future<PronunciationResult> score(
    String wavPath,
    String referenceText, {
    List<String>? vocabulary,
  }) async {
    // Resolved once, here, rather than inside [Asr.transcribe]: the resulting
    // [PronunciationResult.recordingPath] has to be the exact file the
    // recognizer decoded, since that is the file step 4's time ranges are
    // measured against. Whichever [Asr] this is fed to is still free to run
    // its own conversion defensively — this just makes sure the detector and
    // the recognizer agree on which file that was.
    final recordingPath = await ensureAsrWav(wavPath);
    final transcript = await _asr.transcribe(
      recordingPath,
      vocabulary: vocabulary,
    ); // step 2
    return scoreTranscript(
      transcript,
      referenceText,
      recordingPath: recordingPath,
    );
  }

  /// Step 2 alone: recognizes [wavPath] without scoring it against a
  /// reference. Returns the transcript together with the exact file path the
  /// recognizer decoded -- [Transcript.words]' times are measured against
  /// this path, which may differ from [wavPath] itself (see
  /// [ensureAsrWav]) -- the same reason [score] resolves it once, there.
  Future<(String path, Transcript transcript)> transcribe(
    String wavPath,
  ) async {
    final recordingPath = await ensureAsrWav(wavPath);
    final transcript = await _asr.transcribe(recordingPath);
    return (recordingPath, transcript);
  }

  /// Steps 3 and 4, starting from a transcript instead of audio.
  ///
  /// Split out so everything below the recognizer can be exercised without a
  /// microphone or a model — which is most of what can actually go wrong here.
  /// [recordingPath] is optional for the same reason: a test transcript has no
  /// recording behind it, and every [ScoredWord] in the result correctly
  /// reports having no clip to play when it is omitted.
  Future<PronunciationResult> scoreTranscript(
    Transcript transcript,
    String referenceText, {
    String? recordingPath,
  }) async {
    final spokenText = transcript.text;
    final referenceTokens = phraseWords(referenceText);
    final referenceWords = [for (final t in referenceTokens) t.word];
    final spokenWords = [for (final t in phraseWords(spokenText)) t.word];

    // Who matched whom — the one thing steps 3 and 4 both need and neither
    // owns. Phonemizing is the only asynchronous part; the alignment itself
    // and everything downstream of it are pure.
    final alignment = alignPhonemes(
      reference: [for (final word in referenceWords) await _phonemesFor(word)],
      spoken: [for (final word in spokenWords) await _phonemesFor(word)],
    );

    // Step 3: a grade per word.
    final phraseScore = scoreWords(referenceWords, spokenWords, alignment);

    // Step 4: a clip per word, from the same alignment.
    final timings = mapWordTimings(
      alignment: alignment,
      timedWords: transcript.words,
      spokenWordCount: spokenWords.length,
      hasRecording: recordingPath != null,
    );

    final result = PronunciationResult(
      referenceText: referenceText,
      spokenText: spokenText,
      overall: phraseScore.overall,
      words: _merge(referenceTokens, phraseScore.words, timings),
      recordingPath: recordingPath,
    );

    if (kDebugMode) {
      debugPrint('[MispronounceDetector] said : "$spokenText"');
      debugPrint('[MispronounceDetector] score: ${result.overall}%');
      for (final word in result.words) {
        debugPrint(
          '  $word  [${word.referencePhonemes} vs '
          '${word.spokenPhonemes}]'
          '${word.hasSpokenClip ? '  clip: ${word.spokenStart}-${word.spokenEnd}' : ''}',
        );
      }
    }
    return result;
  }

  /// Zips step 3's grades and step 4's clips back into one list, alongside
  /// each word's render position ([PhraseToken.index]) so [SpokenText] can
  /// look a word's score up by the same index it renders. The two inputs are
  /// guaranteed the same length and order — both were built by iterating the
  /// same [referenceTokens] — so this is a plain zip, not another alignment.
  List<ScoredWord> _merge(
    List<PhraseToken> referenceTokens,
    List<WordScore> scores,
    List<WordTiming> timings,
  ) {
    return [
      for (var i = 0; i < referenceTokens.length; i++)
        ScoredWord(
          tokenIndex: referenceTokens[i].index,
          word: scores[i].reference,
          spoken: scores[i].spoken,
          accuracy: scores[i].accuracy,
          category: scores[i].category,
          referencePhonemes: scores[i].referencePhonemes,
          spokenPhonemes: scores[i].spokenPhonemes,
          letters: scores[i].letters,
          spokenStart: timings[i].start,
          spokenEnd: timings[i].end,
        ),
    ];
  }

  Future<void> dispose() async {
    await _asr.dispose();
  }
}
