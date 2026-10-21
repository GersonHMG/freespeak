// Capturing the learner's attempt.

// It records directly to what the recognizer expects — 16 kHz, 16-bit, mono WAV
// — which is why nothing here decodes or resamples anything. Recording at the
// wrong rate and fixing it afterwards would mean writing a resampler.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'asr.dart' show kAsrSampleRate;

/// Records one attempt at a phrase.
class PronunciationRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Whether the microphone is available and permitted.
  ///
  /// Asking triggers the OS permission prompt the first time, so call it when
  /// the learner has just tapped record and the reason is obvious.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts recording. Returns false if permission was refused.
  ///
  /// [slot] names which file this attempt overwrites -- pass the same value
  /// (e.g. a phrase's index in the session) across attempts at the same
  /// phrase to keep reusing one file per phrase, and a fresh one only when
  /// the caller actually means a different recording. Without it every
  /// attempt shared a single `attempt.wav`, so recording a later phrase
  /// silently destroyed an earlier phrase's audio -- fine when attempts were
  /// never revisited, not once going back to a previous phrase needs to
  /// replay what was said there.
  Future<bool> start({Object? slot}) async {
    if (_isRecording) return true;
    if (!await hasPermission()) {
      debugPrint('[PronunciationRecorder] microphone permission refused');
      return false;
    }

    final directory = await getTemporaryDirectory();
    final suffix = slot == null ? '' : '_$slot';
    final path = '${directory.path}/attempt$suffix.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: kAsrSampleRate,
        numChannels: 1,
      ),
      path: path,
    );
    _path = path;
    _isRecording = true;
    return true;
  }

  /// Stops recording and returns the WAV path, or null if there is nothing
  /// usable — no recording in progress, or a file too short to hold speech.
  Future<String?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;

    final path = await _recorder.stop() ?? _path;
    _path = null;
    if (path == null) return null;

    final file = File(path);
    if (!file.existsSync()) return null;

    // A 44-byte WAV is a header and no audio: the tap landed twice, or the
    // recorder never got going. Nothing useful can be transcribed from it.
    // 44-byte header plus half a second of 16-bit samples.
    const minimumBytes = 44 + kAsrSampleRate;
    if (file.lengthSync() <= minimumBytes) {
      debugPrint('[PronunciationRecorder] recording too short to score');
      return null;
    }
    return path;
  }

  /// Abandons the current recording without returning it.
  Future<void> cancel() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _recorder.cancel();
    _path = null;
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
