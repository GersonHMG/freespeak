// The narrow seam between text and its phonemes.
//
// The React Native app injected an eSpeak-NG Emscripten build here;
// [EspeakPhonemizer] supplies it natively. Keeping this interface is what let the lexicon-based backend be swapped out
// for it without touching anything downstream.

/// One source word and the slice of the phoneme string it produced.
///
/// [start] and [end] are rune offsets into [Phonemization.phonemes]. The model
/// reports durations per token, so this is what makes it possible to say which
/// word is being spoken at a given moment.
class PhonemeSpan {
  const PhonemeSpan({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final int start;
  final int end;
}

/// A phonemization together with its word alignment.
class Phonemization {
  const Phonemization({required this.phonemes, required this.words});

  final String phonemes;
  final List<PhonemeSpan> words;
}

/// Turns text into IPA phonemes.
abstract class Phonemizer {
  /// Text -> IPA phoneme string. [lang] is 'en-us' or 'en'.
  Future<String> phonemize(String text, String lang);

  /// Same, but also reporting where each source word landed.
  Future<Phonemization> phonemizeAligned(String text, String lang);
}
