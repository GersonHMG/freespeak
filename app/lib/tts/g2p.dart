// Where the app's G2P is constructed.
//
// It used to be a choice — a port of misaki's lexicon tier, and eSpeak-NG in
// two notations. The lexicon backend was retired (it returned nothing for
// out-of-dictionary words and cost ~18 MB of JSON), and the misaki rewrites
// with it, so what is left is eSpeak in its own notation. The indirection
// stays because [Phonemizer] is the seam the model, the scorer and the UI all
// sit behind; a future backend drops in here and nowhere else.

import 'espeak_phonemizer.dart';
import 'phonemizer.dart';

/// The app's phonemizer, for [voice] (`en-us` or `en-gb`).
///
/// On a platform without the native library this still returns one rather than
/// throwing or substituting something else. It constructs fine anywhere and
/// fails only at [EspeakPhonemizer.ready], with a message that names the
/// platform — which is the right moment, because the widget tests construct a
/// `PhononTts()` and never reach it.
Phonemizer createPhonemizer([String voice = 'en-us']) =>
    EspeakPhonemizer(voice: voice);

/// Whichever warm-up the phonemizer needs, so callers do not have to know
/// which one they were handed.
///
/// Worth paying up front next to the model load: eSpeak unpacks its data on a
/// cold install.
Future<void> warmUpPhonemizer(Phonemizer phonemizer) async {
  if (phonemizer is EspeakPhonemizer) await phonemizer.ready();
}
