// The app's speech synthesizer: Phonon (phonon-31m-en) running on device
// through its C library, with word timings read from the model's own
// attention (see phonon_ffi.dart). Construct once, load() once, reuse for the
// app's lifetime.
//
// The phonemizer is not part of synthesis -- Phonon reads text -- but it
// stays here because everything that shows or scores pronunciation speaks
// its IPA, and each word's IPA is what splits it into syllables.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'g2p.dart';
import 'phonemizer.dart';
import 'phonon_ffi.dart';
import 'spelling_syllables.dart';
import 'syllabifier.dart';
import 'syllable_cuts.dart';
import 'time_stretch.dart';
import 'wav.dart';
import 'word_align.dart';

const int kSampleRate = kPhononSampleRate;

/// The checkpoint, bundled as assets and copied out to a real directory on
/// first launch: the C library reads files, not the asset bundle.
const String _assetDir = 'assets/models/phonon';
const List<String> _checkpointFiles = [
  'config.json',
  'tokenizer.json',
  'model.q8.gguf',
  'default-voice.safetensors',
];

/// How much longer than natural the model paces its speech, through its own
/// `duration_delta` conditioner: 0.5 makes speech about 17% slower, a touch
/// slower than natural for learners. The pace is the model's, not a stretch
/// of its audio, so it sounds natural; anything slower goes through
/// [timeStretch] (see [kSlowRate]).
const String kPaceDelta = '0.5';

/// The attention head that times words, and how far it reads ahead of the
/// audio at [kPaceDelta]: measured against a forced alignment over 40
/// sentences (experiments/phonon_timestamps_experiment.md).
const int _alignLayer = 3;
const int _alignHead = 0;
const Duration _lookahead = Duration(milliseconds: 190);

/// One word and the span of the waveform in which it is spoken.
class WordTiming {
  const WordTiming({
    required this.text,
    required this.start,
    required this.end,
    this.phonemes = '',
  });

  final String text;
  final Duration start;
  final Duration end;

  /// The IPA the phonemizer gives this word.
  final String phonemes;

  @override
  String toString() =>
      '$text [${start.inMilliseconds}-${end.inMilliseconds}ms]';
}

/// A synthesized phrase: the file to play, when each word is spoken, and the
/// samples themselves so individual words can be cut out without re-running
/// the model.
class Speech {
  Speech({required this.path, required this.words, required this.waveform});

  final String path;
  final List<WordTiming> words;
  final Float32List waveform;

  /// Per-word clip paths, written on first request. See [PhononTts.wordClip].
  final Map<int, String> clips = <int, String>{};

  /// The same clips slowed to [kSlowRate]. See [PhononTts.wordClip].
  final Map<int, String> slowClips = <int, String>{};

  /// The whole phrase slowed down, built on first request. See
  /// [PhononTts.slowSpeech].
  Future<SlowSpeech>? slow;

  /// Per-word syllable audio, built on first request. See
  /// [PhononTts.syllableAudio].
  final Map<int, Future<SyllableAudio?>> syllables =
      <int, Future<SyllableAudio?>>{};
}

/// One word taken apart for slow, syllable-by-syllable listening.
class SyllableAudio {
  SyllableAudio({
    required this.syllables,
    required this.labels,
    required this.spelled,
    required this.path,
    required this.timeline,
    required this.clipPaths,
  });

  final List<PhonemeSyllable> syllables;

  /// What to print for each syllable: the spelling ("how", "ev", "er") when
  /// it could be fitted to the sounds, else the syllables' IPA.
  final List<String> labels;

  /// Whether [labels] are spelling rather than IPA.
  final bool spelled;

  /// Every syllable, slowed, with a pause between each.
  final String path;

  /// Where each syllable sounds in [path].
  final List<(Duration, Duration)> timeline;

  /// Each syllable alone, slowed, for tapping one to hear it.
  final List<String> clipPaths;
}

/// A phrase slowed to [kSlowRate]: its own file, and its words' timings
/// stretched to match.
class SlowSpeech {
  const SlowSpeech({required this.path, required this.words});

  final String path;
  final List<WordTiming> words;
}

/// How fast slowed playback runs -- a whole phrase, or a word's syllables --
/// relative to normal speech.
const double kSlowRate = 0.7;

/// The silence between syllables. Most of what makes the playback sound slow
/// -- and the room the highlight needs to keep up.
const Duration kSyllableGap = Duration(milliseconds: 250);

class PhononTts {
  PhononTts({
    Phonemizer? phonemizer,
    this.lang = 'en-us',
    // The public `phonemizer` is the late field below, which needs `lang` to
    // build its default, so it cannot also be an initializing formal.
    // ignore: prefer_initializing_formals
  }) : _phonemizer = phonemizer;

  final Phonemizer? _phonemizer;

  /// The G2P the app shows and scores pronunciation with — the one supplied,
  /// or the app's default built for [lang].
  late final Phonemizer phonemizer = _phonemizer ?? createPhonemizer(lang);

  final String lang;

  PhononEngine? _engine;
  Future<PhononEngine>? _loadFuture;

  bool get isReady => _engine != null;

  /// Copies the checkpoint out and loads the model once (idempotent,
  /// retry-safe).
  Future<PhononEngine> load() {
    final engine = _engine;
    if (engine != null) return Future.value(engine);
    return _loadFuture ??= _build().catchError((Object err) {
      _loadFuture = null; // allow retry
      throw err;
    });
  }

  Future<PhononEngine> _build() async {
    // Whatever the phonemizer needs loading — eSpeak's data files — is paid
    // here, next to the model load, rather than by the first speak().
    await warmUpPhonemizer(phonemizer);

    final timer = Stopwatch()..start();
    final dir = await _materializeCheckpoint();
    final engine = await PhononEngine.load(dir, lang: 'en');
    engine
      ..setCondition('duration_delta', kPaceDelta)
      ..setAlignment(_alignLayer, _alignHead, _lookahead);
    debugPrint('[PhononTts] loaded in ${timer.elapsedMilliseconds} ms');
    _engine = engine;
    return engine;
  }

  // The C library needs real files, but Flutter assets live inside the app
  // bundle. Copy each out once and reuse it on later launches; a size that
  // differs from the asset's means an update or an interrupted copy.
  Future<String> _materializeCheckpoint() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/phonon-31m-en');
    await dir.create(recursive: true);
    for (final name in _checkpointFiles) {
      final data = await rootBundle.load('$_assetDir/$name');
      final file = File('${dir.path}/$name');
      final expected = data.lengthInBytes;
      if (file.existsSync() && await file.length() == expected) continue;
      final part = File('${file.path}.part');
      await part.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, expected),
        flush: true,
      );
      await part.rename(file.path);
    }
    return dir.path;
  }

  /// Text -> playable WAV file path.
  Future<String> speak(String text) async => (await speakTimed(text)).path;

  /// Text -> raw 24 kHz float32 waveform, to handle the audio yourself.
  Future<Float32List> synthesize(String text) async =>
      (await speakTimed(text)).waveform;

  // Synthesis is the expensive part and a practice app replays the same
  // phrase constantly. Bounded so a long session cannot grow without limit; a
  // phrase is a few hundred KB of float32.
  static const int _maxCached = 24;
  final Map<String, Speech> _cache = <String, Speech>{};

  /// Syntheses started but not yet finished, by text. A phrase being
  /// generated in the background can be asked for again -- the learner
  /// reaching it before it is done -- and that second request must wait on
  /// the first rather than pay for the same phrase twice.
  final Map<String, Future<Speech>> _inFlight = <String, Future<Speech>>{};

  /// The tail of the synthesis chain. Each new synthesis waits for this one
  /// before starting: the engine runs one synthesis at a time, and
  /// background and on-demand requests take turns on it.
  Future<void> _lastJob = Future<void>.value();

  /// Text -> audio and per-word timings, reusing a previous synthesis of the
  /// same phrase.
  Future<Speech> speakTimed(String text) {
    final cached = _cache[text];
    if (cached != null) {
      // Re-insert so the most recently used entry is last, and eviction below
      // takes the coldest one.
      _cache.remove(text);
      _cache[text] = cached;
      return Future.value(cached);
    }

    final pending = _inFlight[text];
    if (pending != null) return pending;

    final job = _lastJob.then((_) => _synthesize(text));
    // The chain itself swallows errors: a failed phrase must not stall the
    // ones queued behind it. The caller still sees the error through [job].
    _lastJob = job.then<void>((_) {}, onError: (Object _) {});
    _inFlight[text] = job;
    job.whenComplete(() => _inFlight.remove(text)).ignore();
    return job;
  }

  Future<Speech> _synthesize(String text) async {
    if (text.trim().isEmpty) throw ArgumentError('speakTimed: empty text');
    final engine = await load();
    final result = await engine.speakTimed(text);
    final aligned = await phonemizer.phonemizeAligned(text, lang);
    debugPrint(
      '[PhononTts] ${result.duration.inMilliseconds} ms audio in '
      '${result.elapsed.inMilliseconds} ms: ${result.words}',
    );
    final speech = Speech(
      path: await writeWavFile(result.waveform),
      words: _wordTimings(aligned, result.words),
      waveform: result.waveform,
    );

    _cache[text] = speech;
    if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
    return speech;
  }

  /// The phonemizer's words, timed by what Phonon reports for the words it
  /// read. A word nothing could be attributed to is left out.
  static List<WordTiming> _wordTimings(
    Phonemization aligned,
    List<PhononWord> spoken,
  ) {
    final times = alignWordTimes(
      [for (final w in aligned.words) w.text],
      [for (final w in spoken) (w.word, w.start, w.end)],
    );
    final runes = aligned.phonemes.runes.toList();
    return [
      for (var i = 0; i < aligned.words.length; i++)
        if (times[i] case (final start, final end))
          WordTiming(
            text: aligned.words[i].text,
            start: start,
            end: end,
            phonemes: String.fromCharCodes(
              runes.sublist(
                aligned.words[i].start.clamp(0, runes.length),
                aligned.words[i].end.clamp(0, runes.length),
              ),
            ),
          ),
    ];
  }

  /// Synthesizes every one of [texts] into the [speakTimed] cache ahead of
  /// time, so a screen that plays them later starts instantly instead of
  /// waiting on the model.
  ///
  /// Queued in order on the same chain [speakTimed] uses, so they generate
  /// one at a time. A phrase that fails is skipped rather than aborting the
  /// rest -- it will simply synthesize (and surface its error) at play time.
  /// Safe to leave unawaited: that is how a game screen keeps generating its
  /// later phrases while the learner works on the first.
  Future<void> precompute(Iterable<String> texts) async {
    final jobs = [
      for (final text in texts)
        if (text.trim().isNotEmpty)
          speakTimed(text).then<void>(
            (_) {},
            onError: (Object err) {
              debugPrint('[PhononTts] precompute failed for "$text": $err');
            },
          ),
    ];
    await Future.wait(jobs);
  }

  /// A WAV holding just [index]'s word, cut from the already-synthesized
  /// waveform. No inference: the clip is exactly what was heard in context,
  /// which is what makes it useful for practising a single word.
  ///
  /// With [slow], the clip is stretched to [kSlowRate], pitch unchanged --
  /// what a tapped word plays, so the learner can hear each sound in it.
  Future<String?> wordClip(
    Speech speech,
    int index, {
    bool slow = false,
  }) async {
    if (index < 0 || index >= speech.words.length) return null;

    final cache = slow ? speech.slowClips : speech.clips;
    final cachedPath = cache[index];
    if (cachedPath != null) return cachedPath;

    final word = speech.words[index];
    // A little air on each side, or the clip sounds clipped.
    const padding = Duration(milliseconds: 40);
    final start = _sampleAt(speech, word.start - padding);
    final end = _sampleAt(speech, word.end + padding);
    if (end <= start) return null;

    final clip = Float32List.sublistView(speech.waveform, start, end);
    final path = await writeWavFile(
      slow ? await compute(_fadeAndSlow, clip) : clip,
    );
    cache[index] = path;
    return path;
  }

  /// [speech] slowed to [kSlowRate] with its pitch unchanged. Stacks on
  /// [kPaceDelta]'s already slower pace.
  ///
  /// The stretch maps every moment `t` of the original to about `t / rate`
  /// (give or take the few milliseconds each frame is nudged by), so the word
  /// timings are scaled rather than recomputed.
  Future<SlowSpeech> slowSpeech(Speech speech) {
    return speech.slow ??= _buildSlowSpeech(speech).catchError((Object err) {
      speech.slow = null; // allow retry
      throw err;
    });
  }

  Future<SlowSpeech> _buildSlowSpeech(Speech speech) async {
    final slowed = await compute(_slowDown, speech.waveform);
    Duration stretch(Duration d) =>
        Duration(microseconds: (d.inMicroseconds / kSlowRate).round());
    return SlowSpeech(
      path: await writeWavFile(slowed),
      words: [
        for (final word in speech.words)
          WordTiming(
            text: word.text,
            start: stretch(word.start),
            end: stretch(word.end),
            phonemes: word.phonemes,
          ),
      ],
    );
  }

  /// [index]'s word split into syllables, each cut from the audio already
  /// synthesized for it and slowed to [kSlowRate]. No inference: the cuts
  /// fall at the loudness dips between syllables (see syllable_cuts.dart).
  ///
  /// Null when there is nothing to split -- no phonemes for this word.
  Future<SyllableAudio?> syllableAudio(Speech speech, int index) {
    if (index < 0 || index >= speech.words.length) return Future.value();
    return speech.syllables[index] ??= _buildSyllableAudio(speech, index)
        .catchError((Object err) {
          speech.syllables.remove(index); // allow retry
          throw err;
        });
  }

  Future<SyllableAudio?> _buildSyllableAudio(Speech speech, int index) async {
    final word = speech.words[index];
    final syllables = syllabify(word.phonemes);
    if (syllables.isEmpty) return null;

    final bounds = syllableBoundaries(
      speech.waveform,
      kSampleRate,
      word.start,
      word.end,
      syllables,
    );
    // A little air on each side, but less than a whole word gets: much more
    // and each syllable starts with the tail of the one before it.
    const padding = Duration(milliseconds: 15);
    final ranges = [
      for (var i = 0; i < syllables.length; i++)
        (
          _sampleAt(speech, bounds[i] - padding),
          _sampleAt(speech, bounds[i + 1] + padding),
        ),
    ];
    final (joined, spans, clips) = await compute(_cutAndSlow, (
      speech.waveform,
      ranges,
    ));

    Duration at(int sample) =>
        Duration(microseconds: (sample / kSampleRate * 1e6).round());

    final spelling = spellSyllables(word.text, syllables);
    return SyllableAudio(
      syllables: syllables,
      labels: spelling ?? [for (final s in syllables) s.phonemes],
      spelled: spelling != null,
      path: await writeWavFile(joined),
      timeline: [for (final (start, end) in spans) (at(start), at(end))],
      clipPaths: [for (final clip in clips) await writeWavFile(clip)],
    );
  }

  static int _sampleAt(Speech speech, Duration d) =>
      (d.inMicroseconds / 1e6 * kSampleRate).round().clamp(
        0,
        speech.waveform.length,
      );

  /// The phonemes [text] would be shown and scored as, without synthesizing
  /// anything.
  Future<String> phonemesFor(String text) async {
    await warmUpPhonemizer(phonemizer);
    return phonemizer.phonemize(text, lang);
  }

  Future<void> dispose() async {
    // An engine still synthesizing in the background owns the handle until
    // its call returns.
    await _lastJob;
    _engine?.dispose();
    _engine = null;
    _loadFuture = null;
  }
}

/// Cuts each range out of the waveform, fades its edges, slows it, and joins
/// the lot with [kSyllableGap] between. Runs in compute(): the stretch is the
/// one step here with real arithmetic in it.
(Float32List, List<(int, int)>, List<Float32List>) _cutAndSlow(
  (Float32List, List<(int, int)>) message,
) {
  final (waveform, ranges) = message;
  // 5 ms: long enough to hide the cut, short enough not to swallow a stop.
  const fade = kSampleRate * 5 ~/ 1000;
  final clips = [
    for (final (start, end) in ranges)
      timeStretch(
        fadeEdges(
          Float32List.sublistView(waveform, start, end < start ? start : end),
          fade,
        ),
        kSlowRate,
        sampleRate: kSampleRate,
      ),
  ];
  final gap = kSyllableGap.inMicroseconds * kSampleRate ~/ 1000000;
  final (joined, spans) = joinWithGaps(clips, gap);
  return (joined, spans, clips);
}

Float32List _slowDown(Float32List waveform) =>
    timeStretch(waveform, kSlowRate, sampleRate: kSampleRate);

/// One word's clip, slowed. Faded first: stretching repeats the frames at the
/// cut edges, which would otherwise draw out any click there.
Float32List _fadeAndSlow(Float32List clip) => timeStretch(
  fadeEdges(clip, kSampleRate * 5 ~/ 1000),
  kSlowRate,
  sampleRate: kSampleRate,
);

// Runs in a background isolate via compute(), so the per-sample encode loop
// never lands on the UI isolate.
Uint8List _encodeWav24k(Float32List waveform) =>
    encodeWav(waveform, kSampleRate);

// Several files can be written within one millisecond (a word's syllable
// clips are), so the timestamp alone does not make a name unique.
int _wavCounter = 0;

/// Encodes [waveform] as a WAV file in the cache directory, returning its path.
Future<String> writeWavFile(Float32List waveform) async {
  final bytes = await compute(_encodeWav24k, waveform);
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/tts-${DateTime.now().millisecondsSinceEpoch}'
    '-${_wavCounter++}.wav',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
