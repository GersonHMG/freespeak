// Step 4 of the pipeline: where each reference word falls in the recording.
//
// This is a sibling of scoring (score_system.dart's scoreWords), not a
// continuation of it — both read the same alignment, computed once by
// getBestMappedWords, and neither reads the other's output. Kept apart on
// purpose: a word's accuracy and a word's audio clip are different questions
// with different failure modes. A mismatched recognizer segment count should
// be able to sink only the clip, never the score, and mixing the two into one
// pass made that guarantee hard to see.

import 'asr.dart';
import 'phoneme_alignment.dart';

/// Where one reference word falls in the recording, or nowhere.
class WordTiming {
  const WordTiming({this.start, this.end});

  /// No clip available for this word — it was skipped, or timing could not
  /// be trusted for this attempt (see [mapWordTimings]).
  const WordTiming.none() : start = null, end = null;

  final Duration? start;
  final Duration? end;

  /// Whether there is anything to cut a clip from.
  bool get hasClip => start != null && end != null;
}

/// Maps [alignment]'s matches onto time ranges in the recording.
///
/// [alignment] already says which heard words each reference word drew its
/// sounds from — this only needs [timedWords] to have tagged those same spoken
/// words with time ranges for the lookup to mean anything.
///
/// A reference word can draw on more than one heard word (a boundary said as
/// one run-on, "a napple" for "an apple"), so the clip spans them: earliest
/// start to latest end. Cutting only the first would clip the word off
/// mid-sound, which is the one thing playback must not do.
///
/// [spokenWordCount] is the transcript's plain-text word count, checked
/// separately from `timedWords.length`: a recognizer's own word-splitting does
/// not always match a plain whitespace split (contractions, hyphenation), and
/// when the two counts disagree there is no reliable way to say which timed
/// segment is which spoken word. [VoskAsr] cannot trip this -- its text is the
/// join of its timed words -- but the Whisper recognizer it replaced did,
/// routinely, which is what this guard was written for. Rather than pair them by position and risk
/// cutting the wrong word's audio, nothing here is trusted at all —
/// [hasRecording] false has the same effect, for the same reason (a plain
/// [WordTiming.none] is exactly as informative as a mismatched one).
List<WordTiming> mapWordTimings({
  required PhonemeAlignment alignment,
  required List<TimedWord> timedWords,
  required int spokenWordCount,
  required bool hasRecording,
}) {
  final reliable = hasRecording && timedWords.length == spokenWordCount;
  if (!reliable) {
    return List.filled(alignment.words.length, const WordTiming.none());
  }

  return [
    for (final word in alignment.words)
      _spanOf(word.spokenWordIndices, timedWords),
  ];
}

WordTiming _spanOf(List<int> spokenIndices, List<TimedWord> timedWords) {
  Duration? start;
  Duration? end;

  for (final index in spokenIndices) {
    if (index < 0 || index >= timedWords.length) continue;
    final timed = timedWords[index];
    if (start == null || timed.start < start) start = timed.start;
    if (end == null || timed.end > end) end = timed.end;
  }

  if (start == null || end == null) return const WordTiming.none();
  return WordTiming(start: start, end: end);
}
