// Speech recognition through Vosk (Kaldi). This is the app's recognizer --
// what [MispronounceDetector] is built with in [LoadingScreen], and so what
// every practice score comes from.
//
// Word timing is why it replaced Whisper. Whisper has no native notion of
// where a word sits, and when its segment count disagreed with the
// transcript's word count the timing had to be discarded entirely -- which
// was often, and which is [mapWordTimings] returning "no clip" for a whole
// attempt. Vosk reports word boundaries directly from its lattice alignment,
// and its `text` is by construction the join of its `result` words, so the
// count can not disagree and there is nothing to discard. Tapping a word to
// hear yourself say it stops being intermittent.
//
// The cost, paid in [phoneme_alignment.dart] rather than here: Vosk emits
// lowercase, unpunctuated text. Case and punctuation come out in the wash now
// that both sides are compared as IPA — the phonemizer and
// [normalizePhonemes] between them drop the difference. Numbers do not: Vosk
// says "two thirty" where the dataset writes "2:30", and G2P hands those two
// genuinely different sounds.
//
// Three things about the package to keep in mind:
//
//   * setWords must be turned on explicitly. Without it the JSON comes back
//     as `{"text": "..."}` with no `result` array at all -- a transcript with
//     no timing, which is exactly what this class exists to produce;
//   * it takes headerless PCM16 samples, not a file path, which is what
//     [readPcm16Bytes] is for;
//   * acceptWaveformBytes returning true means an utterance ended mid-stream.
//     That result is only available from getResult() at that moment -- a
//     later getFinalResult() returns the *next* utterance, not this one. See
//     [transcribe];
//   * a Recognizer's word clock is NOT reset by Recognizer.reset(). Confirmed
//     against vosk-api's recognizer.cc: Reset() only sets the state machine
//     back to "endpoint"; the running sample offset the clock is built from
//     (samples_round_start_/frame_offset_) is zeroed solely inside CleanUp(),
//     and only once state_ == RECOGNIZER_FINALIZED -- which FinalResult()
//     reaches by tearing the decoder down, not Reset(). Reusing one
//     Recognizer across separate recordings therefore lets the second
//     recording's words keep counting on from wherever the first one left
//     off. [transcribe] builds a fresh Recognizer per file instead of
//     resetting a shared one -- cheap, since the model's weights (what
//     actually costs ~40 MB and real load time) are unaffected by this.
//     Within one file, by contrast, times are already consistent: the loop
//     below only calls getResult() at interior boundaries (state stays
//     "endpoint", never reaching FINALIZED), so nothing resets until
//     getFinalResult() at the very end -- no manual offsetting needed there.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';

import 'asr.dart';
import 'wav_pcm.dart';

/// Where the weights come from when none are bundled. The small en-US model
/// is the one Vosk publishes for phones: ~40 MB, versus ~1.8 GB for the
/// server-side model, which needs more memory than a phone has.
const String kVoskModelUrl =
    'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip';

/// The same weights, bundled, so a fresh install can score offline -- the
/// rest of the app already is (Phonon's own weights ship in the APK), and a
/// recognizer that needs the network on first run would be the one thing that
/// isn't.
///
/// The filename is load-bearing, not decorative. [ModelLoader.loadFromAssets]
/// takes the basename without its extension as both the directory it extracts
/// into and the folder it then expects to find *inside* the archive; rename
/// the zip and [VoskFlutterPlugin.createModel] is handed a path that does not
/// exist.
const String kVoskModelAsset =
    'assets/models/vosk/vosk-model-small-en-us-0.15.zip';

class VoskAsr implements Asr {
  VoskAsr({this.modelAsset = kVoskModelAsset, this.modelUrl = kVoskModelUrl});

  /// Bundled model zip, or null to download [modelUrl] on first use.
  final String? modelAsset;

  /// Used when [modelAsset] is null, or when it turns out not to be bundled
  /// after all (see [_build]). The download is cached on disk by
  /// [ModelLoader], so it is a first-run cost, not a per-transcription one.
  final String modelUrl;

  // Only the Model is cached -- it is what actually costs ~40 MB and real
  // load time. The Recognizer is built fresh per [transcribe] call instead
  // of being reset and reused; see the file header for why reuse is unsafe.
  Model? _model;
  Future<Model>? _loadFuture;

  bool get isReady => _model != null;

  @override
  Future<void> ready() => _load();

  Future<Model> _load() {
    final model = _model;
    if (model != null) return Future.value(model);
    return _loadFuture ??= _build().catchError((Object err) {
      _loadFuture = null; // allow retry
      throw err;
    });
  }

  Future<Model> _build() async {
    final loader = ModelLoader();
    final path = await _materialize(loader);

    final model = await VoskFlutterPlugin.instance().createModel(path);
    _model = model;
    return model;
  }

  /// Gets the unpacked model onto disk and returns its directory.
  ///
  /// Both paths unzip into the app's data directory and skip the work
  /// entirely when that directory is already populated, so this is only slow
  /// on the first run after an install.
  ///
  /// The fallback exists because [kVoskModelAsset] is 40 MB of APK that a
  /// build may deliberately not carry -- pull the pubspec line and this keeps
  /// working over the network rather than failing to load at all. A missing
  /// asset surfaces as [FlutterError] from `rootBundle.load` inside
  /// [ModelLoader.loadFromAssets]; anything else is a real failure and is
  /// left to propagate so [_load] can clear itself for a retry.
  Future<String> _materialize(ModelLoader loader) async {
    final asset = modelAsset;
    if (asset == null) return loader.loadFromNetwork(modelUrl);

    try {
      return await loader.loadFromAssets(asset);
    } on FlutterError {
      debugPrint('[VoskAsr] $asset not bundled; downloading instead');
      return loader.loadFromNetwork(modelUrl);
    }
  }

  @override
  Future<Transcript> transcribe(
    String wavPath, {
    List<String>? vocabulary,
  }) async {
    final model = await _load();
    // Vosk accepts any rate it was built for, but the recognizer below is
    // pinned to 16 kHz mono -- the format the recorder already produces and
    // [readPcm16Bytes] insists on. The bundled 44.1 kHz debug fixture is what
    // makes this conversion necessary rather than theoretical.
    final conformantPath = await ensureAsrWav(wavPath);
    final pcm = await readPcm16Bytes(conformantPath);

    final recognizer = await VoskFlutterPlugin.instance().createRecognizer(
      model: model,
      sampleRate: kAsrSampleRate,
      // Vosk's grammar is a JSON list of allowed phrases; [_unknownToken]
      // keeps an out-of-list utterance from being forced onto the nearest
      // entry. Words are lowercased to match the model's own lexicon, and a
      // word the lexicon lacks is silently unreachable rather than an error --
      // see [Asr.transcribe].
      //
      // The token is stripped back out of the result (see [VoskResult.parse])
      // -- it belongs in the grammar and nowhere past it.
      grammar: vocabulary == null
          ? null
          : [for (final word in vocabulary) word.toLowerCase(), _unknownToken],
    );
    // The whole point of this class. Off by default, and off means no
    // per-word timing in the result at all.
    await recognizer.setWords(words: true);

    final List<VoskResult> parts;
    try {
      parts = await _runRecognizer(recognizer, pcm);
    } finally {
      // Single-use: nothing after this call reuses this instance, so nothing
      // relies on its word clock outliving this one file.
      await recognizer.dispose();
    }

    final text = [
      for (final part in parts)
        if (part.text.isNotEmpty) part.text,
    ].join(' ');
    final words = [for (final part in parts) ...part.words];

    if (kDebugMode) {
      debugPrint('[VoskAsr] heard: "$text" (${words.length} timed words)');
    }
    return Transcript(text: text, words: words);
  }

  /// Feeds [pcm] into [recognizer] in chunks, collecting one [VoskResult]
  /// per utterance boundary plus the trailing one from [Recognizer.
  /// getFinalResult]. Split out from [transcribe] only to keep that method's
  /// try/finally focused on disposal.
  Future<List<VoskResult>> _runRecognizer(
    Recognizer recognizer,
    Uint8List pcm,
  ) async {
    final parts = <VoskResult>[];
    for (var offset = 0; offset < pcm.length; offset += _chunkBytes) {
      final end = offset + _chunkBytes;
      final chunk = Uint8List.sublistView(
        pcm,
        offset,
        end < pcm.length ? end : pcm.length,
      );
      // True means Vosk decided an utterance ended inside this chunk. Its
      // words are readable only right now -- getFinalResult() at the end
      // returns whatever came after it, so skipping this loses the opening
      // of any recording with a pause in it. Its word times are already
      // consistent with what comes after: see the file header on why no
      // manual offset is needed here, unlike across separate [transcribe]
      // calls.
      if (await recognizer.acceptWaveformBytes(chunk)) {
        parts.add(VoskResult.parse(await recognizer.getResult()));
      }
    }
    parts.add(VoskResult.parse(await recognizer.getFinalResult()));
    return parts;
  }

  /// How much audio to hand over per call. 4000 bytes is 2000 samples, an
  /// eighth of a second at 16 kHz -- small enough that Vosk can report an
  /// utterance boundary near where it actually falls, rather than only at the
  /// end of a whole recording.
  static const int _chunkBytes = 4000;

  @override
  Future<void> dispose() async {
    _model?.dispose();
    _model = null;
    _loadFuture = null;
  }
}

/// What Vosk answers with when a grammar is in force and the utterance matched
/// none of its entries.
///
/// It is put into the grammar deliberately — without it an out-of-list attempt
/// is forced onto the nearest real word — but it is a marker, not something
/// anybody said. Left in, it reaches G2P, gets phonemized as the literal text
/// "[unk]", and scores against the reference: the learner mumbles, and the
/// drill answers with a confident percentage derived from a token Vosk emitted
/// to mean "no idea". Stripping it turns that back into an empty transcript,
/// which every caller already treats as "nothing to score" rather than as a 0.
const String _unknownToken = '[unk]';

/// One decoded Vosk JSON payload.
///
/// Shape, with setWords on:
/// ```json
/// {"text": "the quick brown fox",
///  "result": [{"conf": 1.0, "start": 0.87, "end": 1.11, "word": "the"}]}
/// ```
/// `result` is absent for an empty or partial utterance, which is normal --
/// silence produces `{"text": ""}` -- so it is read defensively rather than
/// assumed.
/// Public only so [parse] can be exercised without a model or a microphone —
/// the unknown-token filtering below is the part that has actually been wrong
/// in front of a learner, and it is pure string work.
@visibleForTesting
class VoskResult {
  const VoskResult({required this.text, required this.words});

  final String text;
  final List<TimedWord> words;

  static VoskResult parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (err) {
      debugPrint('[VoskAsr] unparseable result: $err');
      return const VoskResult(text: '', words: []);
    }
    if (decoded is! Map<String, dynamic>) {
      return const VoskResult(text: '', words: []);
    }

    // Both sides are filtered by the same rule, and that matters as much as
    // the filtering does: [mapWordTimings] refuses to trust any timing when
    // the timed-word count disagrees with the transcript's word count, so
    // dropping the token from one side alone would cost a drill its playback.
    final text = _withoutUnknown((decoded['text'] as String? ?? '').trim());
    final result = decoded['result'];
    if (result is! List) {
      return VoskResult(text: text, words: const []);
    }

    return VoskResult(
      text: text,
      words: [
        for (final entry in result)
          if (entry is Map<String, dynamic>)
            if (_timedWord(entry) case final word
                when word.text != _unknownToken)
              word,
      ],
    );
  }

  static String _withoutUnknown(String text) => [
    for (final word in text.split(RegExp(r'\s+')))
      if (word.isNotEmpty && word != _unknownToken) word,
  ].join(' ');

  /// Vosk reports times as seconds with a fractional part. Read through
  /// microseconds rather than milliseconds: the boundaries this exists to
  /// inspect are exactly where rounding to a millisecond would land.
  static TimedWord _timedWord(Map<String, dynamic> entry) {
    Duration at(String key) => Duration(
      microseconds: (((entry[key] as num?) ?? 0).toDouble() * 1e6).round(),
    );

    return TimedWord(
      text: (entry['word'] as String? ?? '').trim(),
      start: at('start'),
      end: at('end'),
      confidence: (entry['conf'] as num?)?.toDouble(),
    );
  }
}
