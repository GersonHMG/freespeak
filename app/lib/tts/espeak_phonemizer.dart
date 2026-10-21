// Phonemizer backed by eSpeak-NG, via the vendored `espeak_ng` package.
//
// The app's only G2P. It replaced a Dart port of misaki's lexicon tier, which
// was exact where it had an entry but returned nothing at all for a word it
// did not — leaving that word silently absent from the audio — and cost ~18 MB
// of dictionary JSON. eSpeak-NG is misaki's own answer to that gap, and the
// React Native app this was ported from used eSpeak IPA exclusively.
//
// eSpeak's IPA is kept unmodified. There used to be a pass that rewrote it
// into misaki's notation — compressed diphthongs, the flap as `T`, no length
// marks. That was dropped in favour of eSpeak's own spellings, which is what
// the React Native version shipped.
//
// [phonemizeAligned] hands eSpeak each run of words between punctuation marks
// in one call, not a word at a time. eSpeak decides stress across the whole
// clause, and a function word sent alone is the whole clause, so it came back
// stressed in its strong form: "It's a joke" was read "it's EI joke", "the" as
// /ðiː/. eSpeak reports no word boundaries, but it separates the words of its
// IPA with single spaces, so the output is split back into one piece per input
// word to keep [PhonemeSpan] — the word timings, the per-word clips and the
// scorer all depend on it. When the counts disagree (eSpeak merged or expanded
// something), that run falls back to a word at a time.

import 'dart:io';

import 'package:espeak_ng/espeak_ng.dart';
import 'package:flutter/foundation.dart';

import 'espeak_data.dart';
import 'phoneme_text.dart';
import 'phonemizer.dart';

/// Whitespace runs, used to split a speakable span into words.
final RegExp _whitespace = RegExp(r'\s+');

/// Text in (one word or several), its eSpeak IPA out, words separated by
/// spaces. The native library behind [EspeakPhonemizer], as a function, so
/// tests can stand in for it.
typedef EspeakBackend = String Function(String word);

class EspeakPhonemizer implements Phonemizer {
  EspeakPhonemizer({this.voice = 'en-us'}) : _backend = null;

  /// An instance driven by [backend] instead of the native library.
  ///
  /// The FFI is only reachable on a phone, which would put every rule in this
  /// file — the punctuation carry-through, the running rune offsets the word
  /// spans depend on — beyond the reach of the test suite. Those rules are the
  /// part most likely to break silently, so they are tested against a stub and
  /// the native call is left as the only untested step.
  EspeakPhonemizer.withBackend(EspeakBackend backend, {this.voice = 'en-us'})
    : _backend = backend;

  /// The eSpeak voice whose rules are applied — `en-us` or `en-gb`. It selects
  /// a pronunciation, not a speaking voice: nothing here synthesizes audio.
  ///
  /// Fixed at construction rather than taken from [phonemize]'s `lang`,
  /// because eSpeak is initialized once and keeps its voice in process state.
  /// A phonemizer built for one dialect stays on it.
  final String voice;

  /// Whether the native eSpeak library exists on this platform.
  ///
  /// Android and iOS only, so everywhere else — including the test host —
  /// this is false and phonemizing throws rather than returning nonsense.
  static bool get isSupported => espeakIsSupported;

  final EspeakBackend? _backend;

  Espeak? _engine;
  Future<Espeak>? _initFuture;

  bool get isReady => _engine != null || _backend != null;

  /// Extracts the data files and initializes the native library once
  /// (idempotent, retry-safe).
  ///
  /// Cheap after the first run, but that first run unpacks the data files, so
  /// it belongs next to the model load rather than on the first tap.
  Future<Espeak> ready() {
    final engine = _engine;
    if (engine != null) return Future.value(engine);
    return _initFuture ??= _init().catchError((Object err) {
      _initFuture = null; // allow retry
      throw err;
    });
  }

  Future<Espeak> _init() async {
    // Espeak.initialize() refuses too, but naming the alternative here is
    // more use than a message about a missing library.
    if (!isSupported) {
      throw UnsupportedError(
        'EspeakPhonemizer needs the native espeak-ng, which is built for '
        'Android and iOS only — there is no G2P on '
        '${Platform.operatingSystem}.',
      );
    }

    final dataPath = await ensureEspeakData();
    final engine = Espeak()..initialize(dataPath: dataPath, voice: voice);
    _engine = engine;
    return engine;
  }

  @override
  Future<String> phonemize(String text, String lang) async =>
      (await phonemizeAligned(text, lang)).phonemes;

  @override
  Future<Phonemization> phonemizeAligned(String text, String lang) async {
    // A stubbed instance never loads the native library, so it never has an
    // engine to wait for.
    final EspeakBackend speak = _backend ?? (await ready()).phonemize;

    final out = StringBuffer();
    final words = <PhonemeSpan>[];
    // Rune offset written so far, tracked as we go rather than measured at the
    // end, because the word spans have to survive every per-token rewrite.
    var offset = 0;
    var needsSpace = false;

    void write(String s) {
      out.write(s);
      offset += s.runes.length;
    }

    void emitSpan(String span) {
      final tokens = [
        for (final word in span.split(_whitespace))
          if (word.isNotEmpty) word,
      ];
      final spoken = _phonemesForRun(speak, tokens);
      for (var i = 0; i < tokens.length; i++) {
        final phonemes = spoken[i];
        if (phonemes.isEmpty) continue;
        if (needsSpace) write(' ');
        final start = offset;
        write(phonemes);
        words.add(PhonemeSpan(text: tokens[i], start: start, end: offset));
        needsSpace = true;
      }
    }

    var prev = 0;
    for (final match in punctuationRun.allMatches(text)) {
      emitSpan(text.substring(prev, match.start));
      // Punctuation is in the vocab already and is what gives the model its
      // prosodic boundaries, so it is carried through rather than phonemized.
      write(match[0]!);
      needsSpace = true;
      prev = match.end;
    }
    emitSpan(text.substring(prev));

    final result = withTerminalPunctuation(out.toString().trimRight());

    if (kDebugMode) {
      debugPrint('[EspeakPhonemizer] text     : $text');
      debugPrint('[EspeakPhonemizer] phonemes : $result');
    }
    return Phonemization(phonemes: result, words: words);
  }

  // One entry per token of a punctuation-free run, in order: its phonemes, or
  // '' for a token with nothing speakable in it. Every rewrite happens per
  // word, so the caller's running offset stays valid — a later pass over the
  // whole string would shift the spans it has already recorded.
  List<String> _phonemesForRun(EspeakBackend speak, List<String> tokens) {
    final cleaned = [for (final token in tokens) _cleaned(token)];
    final speakable = [
      for (final c in cleaned)
        if (c.isNotEmpty) c,
    ];

    // The whole run in one call, so eSpeak sees each word in its clause.
    // Only trusted when it hands back exactly one piece per word sent: a word
    // that cleaned to several (`a/b`), a number it reads out in full, or a
    // multi-word idiom it runs together would otherwise shift every span
    // after it onto the wrong word.
    if (speakable.length > 1) {
      final pieces = speak(speakable.join(' '))
          .trim()
          .split(_whitespace)
          .where((p) => p.isNotEmpty)
          .toList();
      if (pieces.length == speakable.length) {
        var next = 0;
        return [
          for (var i = 0; i < tokens.length; i++)
            if (cleaned[i].isEmpty) '' else pieces[next++],
        ];
      }
      if (kDebugMode) {
        debugPrint(
          '[EspeakPhonemizer] "${speakable.join(' ')}" came back as '
          '${pieces.length} words for ${speakable.length}; '
          'phonemizing it a word at a time',
        );
      }
    }

    return [
      for (var i = 0; i < tokens.length; i++)
        _phonemesFor(speak, tokens[i], cleaned[i]),
    ];
  }

  // What of [word] eSpeak should see; '' when nothing in it is speakable.
  String _cleaned(String word) {
    // eSpeak reads its input as text, so anything it would sound out as a
    // symbol rather than a letter is stripped first.
    //
    // The period and the hyphen stay. [punctuationRun] has already taken out
    // every mark that is punctuation *in this phrase*, so a period reaching
    // here is the one inside `5.99` — the decimal that makes eSpeak read a
    // number rather than two — and a hyphen is always word-internal, since it
    // is not in [keptPunctuation] at all.
    //
    // The currency and percent signs stay for the opposite reason: eSpeak
    // expands them itself, so `$5.99` is "five dollars ninety nine" rather
    // than "five point nine nine" with the unit thrown away. None of them are
    // in [keptPunctuation] either, so they arrive attached to their number.
    return word.replaceAll(RegExp(r"[^A-Za-z0-9'.\-$€£¥%]"), ' ').trim();
  }

  // One word's phonemes, eSpeak seeing it alone — the fallback when a run's
  // output could not be split back into its words.
  String _phonemesFor(EspeakBackend speak, String word, String cleaned) {
    if (cleaned.isEmpty) return '';

    // eSpeak separates the clauses it consumed with spaces. Collapsed to one
    // space rather than removed: a single source token can legitimately come
    // back as several spoken words — `5.99` is "five point nine nine" — and
    // running them together would turn several words into one.
    var phonemes = speak(cleaned).replaceAll(_whitespace, ' ').trim();
    if (phonemes.isEmpty) {
      if (kDebugMode) debugPrint('[EspeakPhonemizer] nothing for "$word"');
      return '';
    }
    return phonemes;
  }

  Future<void> dispose() async {
    _engine?.dispose();
    _engine = null;
    _initFuture = null;
  }
}
