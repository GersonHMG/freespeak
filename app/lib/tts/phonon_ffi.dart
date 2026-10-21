// Phonon TTS through its C library (libptts_ffi), with word timestamps read
// from the model's own attention -- see experiments/xn-ptts/ptts/src/timestamps.rs.
//
// The raw engine under PhononTts (phonon_tts.dart). Pure dart:ffi, no Flutter,
// so it also runs from a plain Dart script against the desktop build.
//
// The C calls block for the whole synthesis, so [PhononEngine.speakTimed] runs
// them on a background isolate; the handle crosses as an address.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// One word and when Phonon speaks it.
class PhononWord {
  const PhononWord({
    required this.word,
    required this.start,
    required this.end,
    required this.timed,
  });

  factory PhononWord.fromJson(Map<String, dynamic> json) => PhononWord(
    word: json['word'] as String,
    start: _seconds(json['start_s'] as num),
    end: _seconds(json['end_s'] as num),
    timed: json['timed'] as bool,
  );

  /// As the model read it: normalized text, punctuation stripped.
  final String word;
  final Duration start;
  final Duration end;

  /// False when the attention never reached this word and its times are a
  /// neighbour's.
  final bool timed;

  static Duration _seconds(num s) => Duration(microseconds: (s * 1e6).round());

  @override
  String toString() =>
      '$word [${start.inMilliseconds}-${end.inMilliseconds}ms]';
}

/// A synthesized phrase: 24 kHz mono audio and its word timings.
class PhononSpeech {
  const PhononSpeech({
    required this.waveform,
    required this.words,
    required this.elapsed,
  });

  final Float32List waveform;
  final List<PhononWord> words;

  /// Wall time the synthesis took, for the real-time factor.
  final Duration elapsed;

  Duration get duration => Duration(
    microseconds: (waveform.length / kPhononSampleRate * 1e6).round(),
  );
}

const int kPhononSampleRate = 24000;

typedef _NewC = Pointer<Void> Function(Pointer<Utf8>, Uint32, Pointer<Utf8>);
typedef _NewDart = Pointer<Void> Function(Pointer<Utf8>, int, Pointer<Utf8>);
typedef _SpeakTimedC = Bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Pointer<Float>>,
  Pointer<Size>,
  Pointer<Pointer<Utf8>>,
);
typedef _SpeakTimedDart = bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Pointer<Float>>,
  Pointer<Size>,
  Pointer<Pointer<Utf8>>,
);
typedef _FreeTimedC = Void Function(Pointer<Float>, Size, Pointer<Utf8>);
typedef _FreeTimedDart = void Function(Pointer<Float>, int, Pointer<Utf8>);
typedef _SetConditionC = Bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _SetConditionDart = bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _SetAlignmentC = Void Function(Pointer<Void>, Uint32, Uint32, Float);
typedef _SetAlignmentDart = void Function(Pointer<Void>, int, int, double);
typedef _LastErrorC = Pointer<Utf8> Function(Pointer<Void>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

class _Bindings {
  _Bindings(DynamicLibrary lib)
    : create = lib.lookupFunction<_NewC, _NewDart>('ptts_new'),
      speakTimed = lib.lookupFunction<_SpeakTimedC, _SpeakTimedDart>(
        'ptts_speak_timed',
      ),
      freeTimed = lib.lookupFunction<_FreeTimedC, _FreeTimedDart>(
        'ptts_free_timed',
      ),
      setCondition = lib.lookupFunction<_SetConditionC, _SetConditionDart>(
        'ptts_set_condition',
      ),
      setAlignment = lib.lookupFunction<_SetAlignmentC, _SetAlignmentDart>(
        'ptts_set_alignment',
      ),
      lastError = lib.lookupFunction<_LastErrorC, _LastErrorC>(
        'ptts_last_error',
      ),
      free = lib.lookupFunction<_FreeC, _FreeDart>('ptts_free');

  final _NewDart create;
  final _SpeakTimedDart speakTimed;
  final _FreeTimedDart freeTimed;
  final _SetConditionDart setCondition;
  final _SetAlignmentDart setAlignment;
  final _LastErrorC lastError;
  final _FreeDart free;

  /// The library for this platform, or the one at [path].
  static _Bindings open([String? path]) => _Bindings(
    DynamicLibrary.open(
      path ??
          (Platform.isWindows
              ? 'ptts_ffi.dll'
              : Platform.isMacOS
              ? 'libptts_ffi.dylib'
              : 'libptts_ffi.so'),
    ),
  );

  String error(Pointer<Void> handle) {
    final message = lastError(handle);
    return message == nullptr ? 'unknown error' : message.toDartString();
  }
}

class PhononEngine {
  PhononEngine._(this._libraryPath, this._handle);

  final String? _libraryPath;
  int _handle;

  /// Loads the checkpoint folder [dir] (config.json, tokenizer.json,
  /// model.q8.gguf, default-voice.safetensors). Expensive: runs on a
  /// background isolate. [libraryPath] overrides where libptts_ffi is found.
  static Future<PhononEngine> load(
    String dir, {
    String lang = 'en',
    String? libraryPath,
  }) async {
    final handle = await Isolate.run(() {
      final b = _Bindings.open(libraryPath);
      final cDir = dir.toNativeUtf8();
      final cLang = lang.toNativeUtf8();
      try {
        final h = b.create(cDir, 0, cLang);
        if (h == nullptr) throw StateError('ptts_new: ${b.error(nullptr)}');
        return h.address;
      } finally {
        calloc.free(cDir);
        calloc.free(cLang);
      }
    });
    return PhononEngine._(libraryPath, handle);
  }

  /// Sets one of the checkpoint's conditioners, e.g. `duration_delta` to
  /// `0.5` for a slower pace, from the next utterance on.
  void setCondition(String name, String value) {
    final b = _Bindings.open(_libraryPath);
    final h = Pointer<Void>.fromAddress(_live);
    final cName = name.toNativeUtf8();
    final cValue = value.toNativeUtf8();
    try {
      if (!b.setCondition(h, cName, cValue)) {
        throw StateError('ptts_set_condition: ${b.error(h)}');
      }
    } finally {
      calloc.free(cName);
      calloc.free(cValue);
    }
  }

  /// Times words with attention head ([layer], [head]), read [lookahead]
  /// ahead of the audio. The checkpoint's built-in head is otherwise used.
  void setAlignment(int layer, int head, Duration lookahead) {
    _Bindings.open(_libraryPath).setAlignment(
      Pointer<Void>.fromAddress(_live),
      layer,
      head,
      lookahead.inMicroseconds / 1e6,
    );
  }

  int get _live {
    if (_handle == 0) throw StateError('PhononEngine was disposed');
    return _handle;
  }

  /// Text -> audio and per-word timings. One call at a time: the handle is
  /// not safe to share between concurrent syntheses.
  Future<PhononSpeech> speakTimed(String text) {
    final handle = _live;
    final libraryPath = _libraryPath;
    return Isolate.run(() {
      final b = _Bindings.open(libraryPath);
      final h = Pointer<Void>.fromAddress(handle);
      final cText = text.toNativeUtf8();
      final pcm = calloc<Pointer<Float>>();
      final samples = calloc<Size>();
      final json = calloc<Pointer<Utf8>>();
      final timer = Stopwatch()..start();
      try {
        if (!b.speakTimed(h, cText, pcm, samples, json)) {
          throw StateError('ptts_speak_timed: ${b.error(h)}');
        }
        final elapsed = timer.elapsed;
        final waveform = Float32List.fromList(
          pcm.value.asTypedList(samples.value),
        );
        final words = (jsonDecode(json.value.toDartString()) as List)
            .map((w) => PhononWord.fromJson(w as Map<String, dynamic>))
            .toList();
        b.freeTimed(pcm.value, samples.value, json.value);
        return PhononSpeech(waveform: waveform, words: words, elapsed: elapsed);
      } finally {
        calloc.free(cText);
        calloc.free(pcm);
        calloc.free(samples);
        calloc.free(json);
      }
    });
  }

  void dispose() {
    if (_handle == 0) return;
    _Bindings.open(_libraryPath).free(Pointer<Void>.fromAddress(_handle));
    _handle = 0;
  }
}
