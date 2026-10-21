// eSpeak-NG, reduced to the one thing this app wants from it: a word in, its
// IPA out.
//
// Adapted from flutter_kokoro_tts (MIT, Pius Ikeoffiah) — see
// LICENSE.flutter_kokoro_tts. That package keeps this behind `lib/src/` and
// exposes only a whole TTS pipeline whose output drops the phonemes and the
// per-token durations lingo_node is built on, so the useful half is lifted
// out here and the ONNX half is left behind.
//
// The native library itself is eSpeak-NG, GPL v3. See LICENSE.md.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _InitializeC =
    Int32 Function(
      Int32 output,
      Int32 buflength,
      Pointer<Utf8> path,
      Int32 options,
    );
typedef _InitializeDart =
    int Function(int output, int buflength, Pointer<Utf8> path, int options);

typedef _SetVoiceByNameC = Int32 Function(Pointer<Utf8> name);
typedef _SetVoiceByNameDart = int Function(Pointer<Utf8> name);

typedef _TextToPhonemesC =
    Pointer<Utf8> Function(
      Pointer<Pointer<Void>> textptr,
      Int32 textmode,
      Int32 phonememode,
    );
typedef _TextToPhonemesDart =
    Pointer<Utf8> Function(
      Pointer<Pointer<Void>> textptr,
      int textmode,
      int phonememode,
    );

typedef _TerminateC = Int32 Function();
typedef _TerminateDart = int Function();

/// `espeak_Initialize`'s output mode: hand the audio back rather than play it.
/// Nothing here wants audio, but the parameter is not optional.
const int _audioOutputRetrieval = 0x002;

/// Return on error instead of calling exit() and taking the app with it.
const int _dontExit = 0x8000;

/// `espeak_TextToPhonemes` modes: UTF-8 in, IPA out.
const int _textModeUtf8 = 1;
const int _phonemeModeIpa = 0x02;

/// Whether the native library exists on this platform.
///
/// Only Android and iOS are built. Everywhere else — including the test host
/// — this is false, and callers are expected to use a different phonemizer
/// rather than discover it as a missing-symbol crash.
bool get espeakIsSupported => Platform.isAndroid || Platform.isIOS;

/// Text -> IPA, through eSpeak-NG.
///
/// Not safe to use from more than one isolate: eSpeak keeps its state in
/// process globals, so a second [initialize] would reconfigure the first.
class Espeak {
  DynamicLibrary? _lib;
  _InitializeDart? _initialize;
  _SetVoiceByNameDart? _setVoiceByName;
  _TextToPhonemesDart? _textToPhonemes;
  _TerminateDart? _terminate;

  bool _ready = false;
  bool get isReady => _ready;

  /// Loads the library and points eSpeak at its data.
  ///
  /// [dataPath] is the directory *containing* `espeak-ng-data`, or that
  /// directory itself. [voice] is an eSpeak voice name — it selects the
  /// pronunciation rules, not a speaking voice, since nothing here synthesizes
  /// audio.
  ///
  /// The data files are checked before the native call: eSpeak's own reaction
  /// to a missing `phontab` is to abort the process, which is not a thing to
  /// find out about in a crash log.
  void initialize({required String dataPath, String voice = 'en-us'}) {
    if (_ready) return;
    if (!espeakIsSupported) {
      throw UnsupportedError(
        'espeak_ng builds its native library for Android and iOS only, '
        'not ${Platform.operatingSystem}.',
      );
    }
    if (dataPath.isEmpty) {
      throw ArgumentError.value(dataPath, 'dataPath', 'must not be empty');
    }

    final direct = File('$dataPath/phontab');
    final nested = File('$dataPath/espeak-ng-data/phontab');
    if (!direct.existsSync() && !nested.existsSync()) {
      throw StateError(
        'No espeak-ng data at $dataPath: expected phontab there or in an '
        'espeak-ng-data subdirectory.',
      );
    }

    _load();

    final pathPtr = dataPath.toNativeUtf8();
    try {
      final result = _initialize!(
        _audioOutputRetrieval,
        0,
        pathPtr,
        _dontExit,
      );
      // On success this returns the sample rate, so anything non-negative is
      // fine; only a negative value is a failure.
      if (result < 0) throw StateError('espeak_Initialize failed: $result');

      final voicePtr = voice.toNativeUtf8();
      try {
        final set = _setVoiceByName!(voicePtr);
        if (set < 0) throw StateError('No espeak voice named "$voice".');
      } finally {
        calloc.free(voicePtr);
      }
      _ready = true;
    } finally {
      calloc.free(pathPtr);
    }
  }

  void _load() {
    if (_lib != null) return;
    // iOS links espeak-ng into the app binary rather than shipping a separate
    // library, so its symbols are already in the process.
    _lib = Platform.isIOS || Platform.isMacOS
        ? DynamicLibrary.process()
        : DynamicLibrary.open('libespeak-ng.so');

    final lib = _lib!;
    _initialize = lib
        .lookupFunction<_InitializeC, _InitializeDart>('espeak_Initialize');
    _setVoiceByName = lib
        .lookupFunction<_SetVoiceByNameC, _SetVoiceByNameDart>(
          'espeak_SetVoiceByName',
        );
    _textToPhonemes = lib
        .lookupFunction<_TextToPhonemesC, _TextToPhonemesDart>(
          'espeak_TextToPhonemes',
        );
    _terminate = lib
        .lookupFunction<_TerminateC, _TerminateDart>('espeak_Terminate');
  }

  /// IPA for [text]. Clauses come back separated by a space.
  ///
  /// eSpeak consumes its input one clause at a time, advancing the pointer it
  /// was given and returning null when there is nothing left — hence the loop
  /// rather than a single call.
  String phonemize(String text) {
    if (!_ready) throw StateError('Espeak.initialize() has not been called.');

    final textPtr = text.toNativeUtf8();
    final cursor = calloc<Pointer<Void>>();
    cursor.value = textPtr.cast<Void>();
    try {
      final out = StringBuffer();
      while (true) {
        final phonemes = _textToPhonemes!(
          cursor,
          _textModeUtf8,
          _phonemeModeIpa,
        );
        if (phonemes == nullptr) break;
        final clause = phonemes.toDartString();
        if (clause.isEmpty) break;
        if (out.isNotEmpty) out.write(' ');
        out.write(clause);
      }
      return out.toString().trim();
    } finally {
      calloc.free(cursor);
      calloc.free(textPtr);
    }
  }

  void dispose() {
    if (!_ready) return;
    _terminate?.call();
    _ready = false;
  }
}
