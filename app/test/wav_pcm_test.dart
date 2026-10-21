// ensureAsrWav is the fix for a real failure: the recognizer rejected
// assets/debug/prod1.wav outright ("wav must be 16 khz") because that fixture
// is 44.1 kHz with a LIST chunk before its data -- exactly the two things a
// fixed-offset WAV reader gets wrong. These tests build files with the same
// shape by hand, so the regression cannot come back unnoticed.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/pronunciation/wav_pcm.dart';

/// A canonical 16-bit PCM WAV: RIFF/WAVE, fmt, data, nothing else.
Uint8List _pcm16Wav({
  required List<int> samples,
  required int sampleRate,
  int channels = 1,
}) {
  final dataLength = samples.length * 2;
  final buffer = ByteData(44 + dataLength);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  buffer.setUint32(4, 36 + dataLength, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little); // PCM
  buffer.setUint16(22, channels, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * channels * 2, Endian.little);
  buffer.setUint16(32, channels * 2, Endian.little);
  buffer.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  buffer.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    buffer.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return buffer.buffer.asUint8List();
}

/// The same file, but with a LIST/INFO chunk inserted before `data` -- the
/// shape that broke a fixed-44-byte-header reader on prod1.wav.
Uint8List _pcm16WavWithListChunk({
  required List<int> samples,
  required int sampleRate,
  int channels = 1,
}) {
  final plain = _pcm16Wav(
    samples: samples,
    sampleRate: sampleRate,
    channels: channels,
  );
  final fmtChunkEnd = 36; // 12 (RIFF header) + 8 (chunk header) + 16 (fmt body)
  // Even-length body: the generator below does not add the RIFF pad byte an
  // odd-sized chunk would require, so this stays word-aligned without it.
  const listBody = 'INFOICMT';
  final listChunk = ByteData(8 + listBody.length);
  for (var i = 0; i < 4; i++) {
    listChunk.setUint8(i, 'LIST'.codeUnitAt(i));
  }
  listChunk.setUint32(4, listBody.length, Endian.little);
  for (var i = 0; i < listBody.length; i++) {
    listChunk.setUint8(8 + i, listBody.codeUnitAt(i));
  }

  final before = plain.sublist(0, fmtChunkEnd);
  final after = plain.sublist(fmtChunkEnd);
  final combined =
      Uint8List(before.length + listChunk.lengthInBytes + after.length)
        ..setRange(0, before.length, before)
        ..setRange(
          before.length,
          before.length + listChunk.lengthInBytes,
          listChunk.buffer.asUint8List(),
        )
        ..setRange(
          before.length + listChunk.lengthInBytes,
          before.length + listChunk.lengthInBytes + after.length,
          after,
        );

  // RIFF size must cover everything after the first 8 bytes.
  final data = ByteData.sublistView(combined);
  data.setUint32(4, combined.length - 8, Endian.little);
  return combined;
}

Future<String> _writeTemp(String name, Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('wav_pcm_test');
  final path = '${dir.path}${Platform.pathSeparator}$name';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

/// Reads a WAV's PCM16 samples back out by walking its chunks, the same way
/// the production decoder does. A fixed-offset reader would be wrong here on
/// purpose: `ensureAsrWav`'s fast path returns an already-conformant file
/// untouched, LIST chunk and all, rather than paying to re-encode it into the
/// canonical byte-44 layout -- a real WAV reader (the recognizer's included) has
/// no trouble with that, so this test reader should not assume otherwise.
List<int> _readSamples(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, offset, offset + 4);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'data') {
      return [
        for (var i = 0; i < size ~/ 2; i++)
          data.getInt16(body + i * 2, Endian.little),
      ];
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('no data chunk in $path');
}

void main() {
  group('ensureAsrWav', () {
    test('leaves an already-conformant file untouched', () async {
      final bytes = _pcm16Wav(samples: [0, 100, -100, 200], sampleRate: 16000);
      final path = await _writeTemp('conformant.wav', bytes);

      final result = await ensureAsrWav(path);

      expect(result, path); // returned as-is, not rewritten to a new file
    });

    test('the fast path trusts format fields over chunk layout', () async {
      // Mono, 16 kHz, 16-bit -- already conformant by the fields the fast
      // path checks -- but with a LIST chunk ahead of data, so this is not
      // laid out at the canonical fixed offsets. It should still be returned
      // untouched: a real WAV reader (the recognizer's included) walks chunks
      // and has no trouble with this, so paying to re-encode it would be
      // wasted work, not a correctness fix.
      final bytes = _pcm16WavWithListChunk(
        samples: [1000, -1000, 2000, -2000],
        sampleRate: 16000,
      );
      final path = await _writeTemp('conformant_with_list.wav', bytes);

      final outPath = await ensureAsrWav(path);

      expect(outPath, path);
      expect(_readSamples(outPath), [1000, -1000, 2000, -2000]);
    });

    test('resamples a 44.1 kHz fixture to 16 kHz mono', () async {
      // 4410 samples of silence at 44.1 kHz is 0.1s; at 16 kHz that is 1600.
      final bytes = _pcm16Wav(
        samples: List<int>.filled(4410, 0),
        sampleRate: 44100,
      );
      final path = await _writeTemp('44k.wav', bytes);

      final outPath = await ensureAsrWav(path);

      expect(outPath, isNot(path));
      final header = File(outPath).readAsBytesSync();
      final data = ByteData.sublistView(header);
      expect(data.getUint32(24, Endian.little), 16000); // sample rate
      expect(data.getUint16(22, Endian.little), 1); // mono
      expect(data.getUint16(34, Endian.little), 16); // bits per sample

      final outSamples = _readSamples(outPath);
      // Allow the rounding a resample naturally introduces at this ratio.
      expect(outSamples.length, closeTo(1600, 2));
    });

    test('decodes past a LIST chunk instead of reading it as audio', () async {
      // Stereo forces the slow (decode) path even though the rate is already
      // 16 kHz -- a mono, already-conformant file with a LIST chunk would take
      // the fast path and be returned untouched instead, which would prove
      // nothing about the decoder's own chunk-walking. This is the exact
      // shape of the original failure on prod1.wav: a fixed-offset reader
      // that assumes `data` starts at byte 44 would decode the LIST chunk's
      // own bytes as if they were samples.
      final bytes = _pcm16WavWithListChunk(
        samples: [1000, 3000, -1000, -3000], // L/R, L/R
        sampleRate: 16000,
        channels: 2,
      );
      final path = await _writeTemp('with_list.wav', bytes);

      final outPath = await ensureAsrWav(path);

      expect(_readSamples(outPath), [2000, -2000]); // downmixed L/R
    });

    test('downmixes stereo to mono by averaging channels', () async {
      // Left/right pairs: (1000, 3000), (-1000, -3000) -> mono 2000, -2000.
      final bytes = _pcm16Wav(
        samples: [1000, 3000, -1000, -3000],
        sampleRate: 16000,
        channels: 2,
      );
      final path = await _writeTemp('stereo.wav', bytes);

      final outPath = await ensureAsrWav(path);

      expect(_readSamples(outPath), [2000, -2000]);
    });
  });

  group('cutWavClip', () {
    // A 1000 Hz "recording" so 1 ms == 1 sample and the arithmetic in these
    // tests reads directly off the millisecond numbers, rather than requiring
    // every assertion to multiply by 16. cutWavClip reads the rate out of the
    // file itself, so nothing about the function under test is rate-specific.
    Uint8List recording() =>
        _pcm16Wav(samples: List<int>.generate(100, (i) => i), sampleRate: 1000);

    test('cuts the requested range plus padding on each side', () async {
      final path = await _writeTemp('recording.wav', recording());
      final outPath =
          '${File(path).parent.path}${Platform.pathSeparator}clip.wav';

      final result = await cutWavClip(
        sourcePath: path,
        start: const Duration(milliseconds: 50),
        end: const Duration(milliseconds: 60),
        outPath: outPath,
        padding: const Duration(milliseconds: 5),
      );

      expect(result, outPath);
      // [50-5, 60+5) = samples 45..64.
      expect(_readSamples(outPath), List<int>.generate(20, (i) => 45 + i));
    });

    test('clamps padding at the start of the recording', () async {
      final path = await _writeTemp('recording.wav', recording());
      final outPath =
          '${File(path).parent.path}${Platform.pathSeparator}clip.wav';

      await cutWavClip(
        sourcePath: path,
        start: const Duration(milliseconds: 3),
        end: const Duration(milliseconds: 10),
        outPath: outPath,
        padding: const Duration(milliseconds: 5),
      );

      // Padding would reach to -2ms; clamped to 0 rather than throwing or
      // wrapping, since a word near the very start of a recording is not an
      // edge case worth failing on.
      expect(_readSamples(outPath), List<int>.generate(15, (i) => i));
    });

    test('clamps padding at the end of the recording', () async {
      final path = await _writeTemp('recording.wav', recording());
      final outPath =
          '${File(path).parent.path}${Platform.pathSeparator}clip.wav';

      await cutWavClip(
        sourcePath: path,
        start: const Duration(milliseconds: 90),
        end: const Duration(milliseconds: 97),
        outPath: outPath,
        padding: const Duration(milliseconds: 5),
      );

      // Padding would reach to 102ms, past the 100-sample recording.
      expect(_readSamples(outPath), List<int>.generate(15, (i) => 85 + i));
    });
  });
}
