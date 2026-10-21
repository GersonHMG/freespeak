// Encodes mono float32 PCM samples as a 16-bit WAV file.
//
// Ported from the React Native app's audio-utils.ts.

import 'dart:typed_data';

Uint8List encodeWav(Float32List samples, int sampleRate) {
  final buffer = ByteData(44 + samples.length * 2);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  buffer.setUint32(4, 36 + samples.length * 2, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little);
  buffer.setUint16(22, 1, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little);
  buffer.setUint16(32, 2, Endian.little);
  buffer.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  buffer.setUint32(40, samples.length * 2, Endian.little);

  var offset = 44;
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i].clamp(-1.0, 1.0);
    buffer.setInt16(
      offset,
      (s < 0 ? s * 0x8000 : s * 0x7fff).round(),
      Endian.little,
    );
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}
