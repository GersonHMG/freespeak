// Makes sure a WAV file is what the recognizer expects: 16 kHz, mono, 16-bit
// PCM. Neither recognizer this app has used resamples for you, unlike the RN
// app's ASR path -- transformers.js decoded whatever WAV it was given
// internally -- so that decode step is reimplemented here.
//
// [PronunciationRecorder] already records at the right rate, so on that path
// this is a cheap header check and nothing more. It earns its keep on
// assets/debug/prod1.wav, which is 44.1 kHz -- the same file the Expo app's
// test-mispronounce.ts resampled with wavefile before scoring it -- and on any
// future audio source (a picked file, a device that quietly ignores the
// recorder's requested rate) that is not already conformant.
//
// [cutWavClip] reuses the same decoder for a second job: slicing a time range
// back out of a recording, which is how [UserAttemptPlayer] plays back
// exactly the word the learner said, not just the whole attempt.

import 'dart:io';
import 'dart:typed_data';

import '../tts/wav.dart';

/// WAVE format codes this decoder understands.
const int _formatPcm = 1;
const int _formatFloat = 3;

/// Sample rate and channel count the recognizer expects.
const int _targetSampleRate = 16000;

class _WavPcm {
  _WavPcm({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });

  /// Interleaved samples, normalized to [-1, 1].
  final Float32List samples;
  final int sampleRate;
  final int channels;
}

/// What the header says, and where the samples are -- everything a reader
/// needs before it decides how to interpret the `data` chunk's bytes.
class _WavLayout {
  _WavLayout({
    required this.formatCode,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  final int formatCode;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;
}

/// Walks [bytes]' RIFF chunks rather than assuming a fixed 44-byte header --
/// prod1.wav carries a LIST/INFO chunk before `data`, which a fixed-offset
/// reader misses entirely.
_WavLayout _parseLayout(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }

  int? formatCode, channels, sampleRate, bitsPerSample;
  int dataOffset = -1, dataLength = 0;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, offset, offset + 4);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;

    if (id == 'fmt ') {
      formatCode = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataLength = size;
    }

    // Chunks are word-aligned: an odd-sized chunk has a padding byte after it.
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  if (formatCode == null ||
      channels == null ||
      sampleRate == null ||
      bitsPerSample == null ||
      dataOffset < 0) {
    throw const FormatException('WAV missing fmt or data chunk');
  }

  return _WavLayout(
    formatCode: formatCode,
    channels: channels,
    sampleRate: sampleRate,
    bitsPerSample: bitsPerSample,
    dataOffset: dataOffset,
    // A truncated file (a crashed recording, a partial download) would
    // otherwise read past the buffer with a confusing RangeError.
    dataLength: dataLength.clamp(0, bytes.length - dataOffset),
  );
}

/// Decodes [bytes] to interleaved samples normalized to [-1, 1].
_WavPcm _decodeWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final layout = _parseLayout(bytes);
  final formatCode = layout.formatCode;
  final channels = layout.channels;
  final sampleRate = layout.sampleRate;
  final bitsPerSample = layout.bitsPerSample;
  final dataOffset = layout.dataOffset;
  final dataLength = layout.dataLength;

  final frameSamples = <double>[];
  final bytesPerSample = bitsPerSample ~/ 8;
  final frameCount = dataLength ~/ (bytesPerSample * channels);

  for (var f = 0; f < frameCount; f++) {
    for (var c = 0; c < channels; c++) {
      final at = dataOffset + (f * channels + c) * bytesPerSample;
      double sample;
      if (formatCode == _formatFloat && bitsPerSample == 32) {
        sample = data.getFloat32(at, Endian.little);
      } else if (formatCode == _formatPcm && bitsPerSample == 16) {
        sample = data.getInt16(at, Endian.little) / 0x8000;
      } else if (formatCode == _formatPcm && bitsPerSample == 8) {
        // 8-bit PCM is unsigned, centered on 128.
        sample = (bytes[at] - 128) / 128;
      } else if (formatCode == _formatPcm && bitsPerSample == 32) {
        sample = data.getInt32(at, Endian.little) / 0x80000000;
      } else {
        throw FormatException(
          'Unsupported WAV encoding: format $formatCode @ $bitsPerSample bits',
        );
      }
      frameSamples.add(sample);
    }
  }

  return _WavPcm(
    samples: Float32List.fromList(frameSamples),
    sampleRate: sampleRate,
    channels: channels,
  );
}

/// Averages interleaved channels down to one. Matches the RN test harness's
/// own mono downmix (`(left[i] + right[i]) / 2`).
Float32List _toMono(Float32List interleaved, int channels) {
  if (channels == 1) return interleaved;
  final frames = interleaved.length ~/ channels;
  final mono = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += interleaved[f * channels + c];
    }
    mono[f] = sum / channels;
  }
  return mono;
}

/// Linear resampling. Exact enough for the one thing it is used for here -- getting a debug fixture or a
/// stray recording onto the rate the model expects, not archival audio work.
Float32List _resample(Float32List samples, int from, int to) {
  if (from == to || samples.isEmpty) return samples;

  final outLength = (samples.length * to / from).round();
  final out = Float32List(outLength);
  final step = from / to;

  for (var i = 0; i < outLength; i++) {
    final srcPos = i * step;
    final i0 = srcPos.floor().clamp(0, samples.length - 1);
    final i1 = (i0 + 1).clamp(0, samples.length - 1);
    final t = srcPos - i0;
    out[i] = samples[i0] + (samples[i1] - samples[i0]) * t;
  }
  return out;
}

/// Returns a path to a WAV file at 16 kHz mono 16-bit PCM, suitable for
/// [Asr.transcribe]. If [path] already satisfies that -- true for anything
/// [PronunciationRecorder] produced -- it is returned unchanged; only a file
/// that actually needs converting pays for the decode.
Future<String> ensureAsrWav(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();

  if (_isAlreadyConformant(bytes)) return path;

  final decoded = _decodeWav(bytes);
  final mono = _toMono(decoded.samples, decoded.channels);
  final resampled = _resample(mono, decoded.sampleRate, _targetSampleRate);

  final outPath = '${path.substring(0, path.length - 4)}.16k.wav';
  await File(outPath)
      .writeAsBytes(encodeWav(resampled, _targetSampleRate), flush: true);
  return outPath;
}

/// Returns the raw bytes of [path]'s `data` chunk -- 16-bit PCM samples with
/// no header -- for a recognizer that wants samples rather than a file.
///
/// [VoskAsr] is the caller: `acceptWaveformBytes` takes headerless PCM16, and
/// handing it a whole WAV would feed the RIFF header in as audio. Stripping a
/// fixed 44 bytes would be wrong for the same reason [_parseLayout] exists --
/// prod1.wav's LIST chunk sits between the header and the samples.
///
/// Throws unless the file is already 16-bit PCM mono: [ensureAsrWav]
/// guarantees that, so anything else reaching here is a caller that skipped
/// it, and silently reinterpreting stereo or float samples as mono PCM16
/// would hand the recognizer noise rather than an error.
Future<Uint8List> readPcm16Bytes(String path) async {
  final bytes = await File(path).readAsBytes();
  final layout = _parseLayout(bytes);

  if (layout.formatCode != _formatPcm ||
      layout.bitsPerSample != 16 ||
      layout.channels != 1) {
    throw FormatException(
      'Expected 16-bit PCM mono, got format ${layout.formatCode} @ '
      '${layout.bitsPerSample} bits, ${layout.channels} channel(s)',
    );
  }

  // Rounded down to a whole number of samples: a `data` chunk with an odd
  // length is truncated, and handing a recognizer half a sample would shift
  // every sample after it by a byte.
  final sampleBytes = layout.dataLength - (layout.dataLength.isOdd ? 1 : 0);

  return Uint8List.sublistView(
    bytes,
    layout.dataOffset,
    layout.dataOffset + sampleBytes,
  );
}

/// Word segments this short or shorter are treated as missing an end
/// timestamp rather than trusted -- a recognizer can report a word's end at
/// or before its start, which would otherwise cut a silent
/// clip. See [cutWavClip].
const Duration kMinWordClipDuration = Duration(milliseconds: 0);

/// Cuts [start, end) out of the WAV at [sourcePath] -- 16 kHz mono 16-bit PCM,
/// the format [ensureAsrWav] guarantees -- padded by [padding] on each
/// side and clamped to the file's bounds, and writes the result to [outPath].
///
/// This is what makes tapping a word a second time play back the slice of the
/// recording where the learner actually said it: [start]/[end] come from
/// the recognizer's word timestamps by way of [MispronounceDetector]'s DTW
/// alignment (`ScoredWord.spokenStart`/`spokenEnd`), and everything here does
/// is turn a time range into bytes -- without padding a clip sounds clipped,
/// the consonant at either edge cut off mid-sound. [PhononTts.wordClip], the
/// equivalent cut for synthesized reference audio, pads by a different
/// amount -- that clip comes from clean TTS output with none of a phone
/// mic's onset noise to buffer against.
///
/// [end] at or before [start] is treated the same as a missing end
/// timestamp: [kMinWordClipDuration] out from [start] is used instead, so a
/// degenerate segment still cuts something audible rather than silence.
Future<String> cutWavClip({
  required String sourcePath,
  required Duration start,
  required Duration end,
  required String outPath,
  Duration padding = const Duration(milliseconds: 0),
}) async {
  final bytes = await File(sourcePath).readAsBytes();
  final decoded = _decodeWav(bytes);
  final mono = _toMono(decoded.samples, decoded.channels);

  final effectiveEnd = end > start ? end : start + kMinWordClipDuration;

  int sampleAt(Duration d) => (d.inMicroseconds / 1e6 * decoded.sampleRate)
      .round()
      .clamp(0, mono.length);

  final from = sampleAt(start - padding);
  final to = sampleAt(effectiveEnd + padding);
  final clip = to > from
      ? Float32List.sublistView(mono, from, to)
      : Float32List(0);

  await File(outPath)
      .writeAsBytes(encodeWav(clip, decoded.sampleRate), flush: true);
  return outPath;
}

/// Cheap header check for the common case -- a recording already at the
/// target format -- so it can skip the decode/resample/re-encode round trip
/// entirely rather than doing it on every attempt.
bool _isAlreadyConformant(Uint8List bytes) {
  if (bytes.length < 44) return false;
  final data = ByteData.sublistView(bytes);
  if (String.fromCharCodes(bytes, 0, 4) != 'RIFF') return false;
  if (String.fromCharCodes(bytes, 8, 12) != 'WAVE') return false;
  if (String.fromCharCodes(bytes, 12, 16) != 'fmt ') {
    // A LIST or other chunk before fmt means this is not the canonical
    // fixed-offset layout the fast path assumes -- decode it properly.
    return false;
  }
  final formatCode = data.getUint16(20, Endian.little);
  final channels = data.getUint16(22, Endian.little);
  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  return formatCode == _formatPcm &&
      channels == 1 &&
      sampleRate == _targetSampleRate &&
      bitsPerSample == 16;
}
