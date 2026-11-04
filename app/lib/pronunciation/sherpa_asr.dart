// Speech recognition through sherpa-onnx (ONNX Runtime). This is the app's
// recognizer -- what [MispronounceDetector] is built with in [LoadingScreen],
// and so what every practice score comes from. Which model it runs is the
// learner's choice in Settings ([selectedAsrModel]); the weights come from
// [AsrModelStore], never from the APK.
//
// Decoding runs on a long-lived worker isolate. A recognizer's decode call is
// one synchronous FFI call that takes from a few hundred milliseconds
// (Whisper tiny) to seconds (Parakeet on an older phone), and on the UI
// isolate that is a frozen screen for exactly as long. The worker also owns
// the native recognizer for its whole life: sherpa-onnx's bindings are
// per-isolate, and a recognizer created in one isolate is only ever touched
// from that one.
//
// What each model can report differs, and the rest of the pipeline already
// copes with both:
//
//   * Parakeet (a NeMo TDT transducer) gives a start time per BPE token.
//     [transcriptFromSherpaJson] glues tokens back into words, so a word can
//     be tapped to hear it back, and reads `ys_log_probs` for a per-word
//     confidence when the native library reports it;
//   * Whisper gives text only -- its token timestamps need a decoder
//     exported with cross-attention outputs, which the published sherpa-onnx
//     models are not. [Transcript.words] is then empty, which
//     [mapWordTimings] and [clarityOf] already treat as "no timing" and "no
//     clarity", not as an error.
//
// Neither supports a closed vocabulary the way Vosk's grammar did, so
// [transcribe]'s `vocabulary` is ignored -- [Asr.transcribe] allows that.
// Both models are large enough that the isolated-word problem it worked
// around ("bear" for "beer") is much rarer than it was with Vosk's small
// model.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
// The raw result JSON carries fields (`ys_log_probs`, `durations`) that
// OfflineRecognizer.getResult drops on the way to its result class.
// ignore: implementation_imports
import 'package:sherpa_onnx/src/sherpa_onnx_bindings.dart';

import 'asr.dart';
import 'asr_model_store.dart';
import 'asr_models.dart';
import 'wav_pcm.dart';

class SherpaAsr implements Asr {
  SherpaAsr({required this.store, ValueListenable<AsrModel>? model})
    : _selected = model ?? selectedAsrModel {
    _selected.addListener(_onSelectionChanged);
    store.addListener(_onStoreChanged);
  }

  final AsrModelStore store;
  final ValueListenable<AsrModel> _selected;

  _Worker? _worker;
  AsrModel? _workerModel;
  Future<_Worker>? _loadFuture;

  bool get isReady => _worker != null && _workerModel == _selected.value;

  @override
  Future<void> ready() => _load();

  Future<_Worker> _load() {
    final model = _selected.value;
    final worker = _worker;
    if (worker != null && _workerModel == model) return Future.value(worker);
    return _loadFuture ??= _build(model).whenComplete(() => _loadFuture = null);
  }

  Future<_Worker> _build(AsrModel model) async {
    if (!store.isDownloaded(model)) throw AsrModelMissing(model.name);

    _closeWorker();
    final worker = await _Worker.start(
      _configFor(model, await store.pathsOf(model)),
    );
    // The learner may have switched again while this one was loading; the
    // next [_load] builds the right one.
    _worker = worker;
    _workerModel = model;
    return worker;
  }

  static sherpa.OfflineRecognizerConfig _configFor(
    AsrModel model,
    List<String> paths,
  ) {
    final threads = math.min(4, math.max(1, Platform.numberOfProcessors ~/ 2));
    switch (model.kind) {
      case AsrModelKind.whisper:
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: paths[0],
              decoder: paths[1],
              language: 'en',
              task: 'transcribe',
            ),
            tokens: paths[2],
            numThreads: threads,
            debug: false,
          ),
        );
      case AsrModelKind.nemoTransducer:
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            transducer: sherpa.OfflineTransducerModelConfig(
              encoder: paths[0],
              decoder: paths[1],
              joiner: paths[2],
            ),
            tokens: paths[3],
            modelType: 'nemo_transducer',
            numThreads: threads,
            debug: false,
          ),
        );
    }
  }

  /// A new pick, or the picked model finishing its download, warms the
  /// recognizer up straight away -- the same reason [LoadingScreen] does it
  /// at startup: the first attempt should not be the one that pays for it.
  void _onSelectionChanged() => _warmUp();

  void _onStoreChanged() {
    final model = _selected.value;
    if (_workerModel == model && !store.isDownloaded(model)) {
      // Its files were just deleted out from under it.
      _closeWorker();
    } else if (_worker == null || _workerModel != model) {
      _warmUp();
    }
  }

  void _warmUp() {
    if (!store.isDownloaded(_selected.value) || _loadFuture != null) return;
    unawaited(
      _load().then<void>((_) {}).catchError((Object err) {
        debugPrint('[SherpaAsr] loading ${_selected.value.name} failed: $err');
      }),
    );
  }

  @override
  Future<Transcript> transcribe(
    String wavPath, {
    List<String>? vocabulary,
  }) async {
    final worker = await _load();
    // The recognizer is fed 16 kHz mono floats; [ensureAsrWav] is what gets
    // the 44.1 kHz debug fixture (and anything else) there.
    final conformantPath = await ensureAsrWav(wavPath);
    final samples = pcm16ToFloat32(await readPcm16Bytes(conformantPath));
    final length = Duration(
      microseconds: samples.length * 1000000 ~/ kAsrSampleRate,
    );

    // Whisper does not hear silence as nothing: given a near-silent clip it
    // tends to invent "Thank you." or "you", which would then be scored as
    // an attempt. Below this peak there is no speech to find anyway.
    if (_peak(samples) < _silencePeak) return const Transcript(text: '');

    final json = await worker.decode(samples);
    final transcript = transcriptFromSherpaJson(
      jsonDecode(json) as Map<String, dynamic>,
      audioLength: length,
    );
    if (kDebugMode) {
      debugPrint(
        '[SherpaAsr] ${_workerModel?.name} heard: "${transcript.text}" '
        '(${transcript.words.length} timed words)',
      );
    }
    return transcript;
  }

  static const double _silencePeak = 0.01;

  static double _peak(Float32List samples) {
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    return peak;
  }

  void _closeWorker() {
    _worker?.close();
    _worker = null;
    _workerModel = null;
  }

  @override
  Future<void> dispose() async {
    _selected.removeListener(_onSelectionChanged);
    store.removeListener(_onStoreChanged);
    _closeWorker();
  }
}

/// Little-endian PCM16 bytes as floats in [-1, 1), the format sherpa-onnx
/// takes. Read through [ByteData] because the bytes come from a sublist of a
/// file and need not be 2-byte aligned for an [Int16List] view.
Float32List pcm16ToFloat32(Uint8List pcm) {
  final data = ByteData.sublistView(pcm);
  final out = Float32List(pcm.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// One sherpa-onnx offline result, as the rest of the pipeline is allowed to
/// see it.
///
/// Shape (fields beyond `text` may be empty or absent depending on the
/// model):
/// ```json
/// {"text": " Hello, world.", "tokens": [" Hello", ",", " world", "."],
///  "timestamps": [0.32, 0.56, 0.64, 0.96], "ys_log_probs": [...]}
/// ```
///
/// A token that starts with a space (or SentencePiece's "▁") starts a word;
/// anything else is glued onto the word before it. Words that are only
/// punctuation are dropped, and [Transcript.text] is rebuilt from the words
/// that remain, so the two agree on the word count [mapWordTimings] checks.
///
/// Without one timestamp per token (Whisper) only the text is kept, with
/// bracketed non-speech markers such as "[BLANK_AUDIO]" removed.
@visibleForTesting
Transcript transcriptFromSherpaJson(
  Map<String, dynamic> json, {
  required Duration audioLength,
}) {
  final rawText = (json['text'] as String? ?? '');
  final tokens = _listOf<String>(json['tokens']);
  final times = _listOf<num>(json['timestamps']);

  if (tokens.isEmpty || times.length != tokens.length) {
    return Transcript(text: _cleanText(rawText));
  }

  final durations = _listOf<num>(json['durations']);
  final logProbs = _listOf<num>(json['ys_log_probs']);
  final hasDurations = durations.length == tokens.length;
  final hasProbs = logProbs.length == tokens.length;
  final audioEnd = audioLength.inMicroseconds / 1e6;

  double tokenEnd(int i) {
    final start = times[i].toDouble();
    if (hasDurations && durations[i] > 0) {
      return start + durations[i].toDouble();
    }
    // No duration: run to the next token, but not across a pause -- a word
    // before a breath would otherwise swallow the silence after it.
    final next = i + 1 < times.length ? times[i + 1].toDouble() : audioEnd;
    return math.min(next, start + _maxTokenSeconds);
  }

  final words = <_WordBuilder>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i].replaceAll('▁', ' ');
    final piece = token.trim();
    if (piece.isEmpty) continue;
    if (words.isEmpty || token.startsWith(' ')) {
      words.add(_WordBuilder(times[i].toDouble()));
    }
    words.last
      ..text.write(piece)
      ..end = tokenEnd(i);
    if (hasProbs) words.last.logProbs.add(logProbs[i].toDouble());
  }

  final timed = [
    for (final word in words)
      if (_hasSpeech.hasMatch(word.text.toString())) word.build(audioEnd),
  ];
  return Transcript(text: timed.map((w) => w.text).join(' '), words: timed);
}

const double _maxTokenSeconds = 0.6;

final RegExp _hasSpeech = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _nonSpeechMarker = RegExp(r'\[[^\]]*\]|\([^)]*\)');

String _cleanText(String text) => text
    .replaceAll(_nonSpeechMarker, ' ')
    .split(RegExp(r'\s+'))
    .where(_hasSpeech.hasMatch)
    .join(' ');

List<T> _listOf<T>(Object? value) =>
    value is List ? value.whereType<T>().toList() : <T>[];

class _WordBuilder {
  _WordBuilder(this.start) : end = start;

  final double start;
  double end;
  final StringBuffer text = StringBuffer();
  final List<double> logProbs = [];

  TimedWord build(double audioEnd) {
    Duration at(double seconds) =>
        Duration(microseconds: (seconds.clamp(0.0, audioEnd) * 1e6).round());
    return TimedWord(
      text: text.toString(),
      start: at(start),
      end: at(end),
      // The geometric mean of the tokens' probabilities: one shaky piece of
      // a long word pulls it down, but less than taking the minimum would.
      confidence: logProbs.isEmpty
          ? null
          : math.exp(logProbs.reduce((a, b) => a + b) / logProbs.length),
    );
  }
}

/// The isolate that owns the native recognizer. One request at a time is
/// all the app ever sends, but replies are matched by id anyway so a late
/// answer can never be taken for the next one's.
class _Worker {
  _Worker._(this._inbox, this._toWorker);

  final ReceivePort _inbox;
  final SendPort _toWorker;
  final Map<int, Completer<String>> _pending = {};
  int _nextId = 0;

  static Future<_Worker> start(sherpa.OfflineRecognizerConfig config) async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, (
      inbox.sendPort,
      config,
    ), debugName: 'asr');
    final ready = Completer<SendPort>();
    late final _Worker worker;
    inbox.listen((Object? message) {
      if (!ready.isCompleted) {
        if (message is SendPort) {
          ready.complete(message);
        } else {
          ready.completeError(Exception('$message'));
        }
        return;
      }
      if (message case (final int id, final Object? reply)) {
        final pending = worker._pending.remove(id);
        if (reply is String) {
          pending?.complete(reply);
        } else {
          pending?.completeError(Exception('$reply'));
        }
      }
    });

    try {
      worker = _Worker._(inbox, await ready.future);
    } catch (_) {
      inbox.close();
      isolate.kill();
      rethrow;
    }
    return worker;
  }

  /// The raw result JSON for [samples].
  Future<String> decode(Float32List samples) {
    final id = _nextId++;
    final reply = Completer<String>();
    _pending[id] = reply;
    _toWorker.send((
      id,
      TransferableTypedData.fromList([samples.buffer.asUint8List()]),
    ));
    return reply.future;
  }

  void close() {
    // Asked to stop rather than killed, so it frees the native recognizer
    // (hundreds of MB for Parakeet) on its way out.
    _toWorker.send(null);
    for (final pending in _pending.values) {
      pending.completeError(StateError('Recognizer closed'));
    }
    _pending.clear();
    _inbox.close();
  }

  static void _workerMain((SendPort, sherpa.OfflineRecognizerConfig) args) {
    final (reply, config) = args;
    final sherpa.OfflineRecognizer recognizer;
    try {
      sherpa.initBindings();
      recognizer = sherpa.OfflineRecognizer(config);
    } catch (err) {
      reply.send('Could not load the recognizer: $err');
      return;
    }

    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    inbox.listen((Object? message) {
      if (message case (final int id, final TransferableTypedData audio)) {
        final samples = audio.materialize().asFloat32List();
        final stream = recognizer.createStream();
        try {
          stream.acceptWaveform(samples: samples, sampleRate: kAsrSampleRate);
          recognizer.decode(stream);
          reply.send((id, _resultJson(stream)));
        } catch (err) {
          reply.send((id, StateError('$err')));
        } finally {
          stream.free();
        }
      } else {
        recognizer.free();
        inbox.close();
      }
    });
  }

  static String _resultJson(sherpa.OfflineStream stream) {
    final json = SherpaOnnxBindings.getOfflineStreamResultAsJson!(stream.ptr);
    try {
      return json.toDartString();
    } finally {
      SherpaOnnxBindings.destroyOfflineStreamResultJson!(json);
    }
  }
}
