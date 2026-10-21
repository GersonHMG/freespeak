// The seam between the scorer and whatever does speech recognition.
//
// Worth having as its own interface: the recognizer is the only part of this
// feature with a hard external dependency, and the rest of the pipeline is
// pure Dart that must not have to care. That earned its keep -- the app
// shipped on whisper_kit and now scores with Vosk, and nothing below this
// seam noticed. [VoskAsr] is the implementation.

/// Sample rate every implementation is fed at, and that the recorder captures
/// at. 16 kHz is what Vosk's small models are built for;
/// recording at it avoids a resample.
const int kAsrSampleRate = 16000;

/// One word as the recognizer heard it, and where it sits in the recording.
///
/// The alignment step (`alignPhonemes`) is what turns "the recognizer heard
/// these words in this order" into "here is the time range for the word the
/// learner was asked to say" — this is only the raw material for that, one
/// entry per word actually heard, in the order it was heard.
class TimedWord {
  const TimedWord({
    required this.text,
    required this.start,
    required this.end,
    this.confidence,
  });

  final String text;
  final Duration start;
  final Duration end;

  /// How sure the recognizer is of this word, 0-1, or null when it does not
  /// say. Vosk reports it per word (`conf`); the Recall clarity score
  /// (lib/decks/clarity.dart) is built from it.
  final double? confidence;

  @override
  String toString() =>
      '"$text" [${start.inMilliseconds}-${end.inMilliseconds}ms]';
}

/// A transcript, and — when the recognizer could produce them — where each
/// word of it falls in the audio.
class Transcript {
  const Transcript({required this.text, this.words = const []});

  /// The heard text. Empty when nothing intelligible was heard.
  final String text;

  /// One entry per word of [text], in order — empty when word timing was not
  /// requested, or could not be lined up with [text] ([VoskAsr] cannot hit
  /// the latter, since its text is built from these words). Never assume `words.length` matches a
  /// word count derived from [text]; check it, the way [MispronounceDetector]
  /// does before relying on it.
  final List<TimedWord> words;
}

/// Speech in, text (and optionally per-word timing) out.
abstract class Asr {
  /// Loads whatever the recognizer needs, once. Idempotent and retry-safe.
  Future<void> ready();

  /// Transcribes the WAV file at [wavPath] — 16 kHz, 16-bit PCM, mono.
  ///
  /// An empty [Transcript.text] means nothing intelligible was heard, which is
  /// a normal outcome (silence, a mistap) and not an error.
  ///
  /// [vocabulary], when given, limits recognition to those words (plus an
  /// unknown-word token) instead of the recognizer's whole language model.
  /// The Practice drill uses it: an isolated word decoded against a full
  /// vocabulary is easily stolen by a phonetic neighbour ("bear" for "beer"),
  /// which a sentence's context would have ruled out. Implementations with
  /// no grammar support ignore it.
  Future<Transcript> transcribe(String wavPath, {List<String>? vocabulary});

  Future<void> dispose();
}
