import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:lingo_node/tts/wav.dart';

void main() {
  group('encodeWav', () {
    test('writes a 24 kHz mono 16-bit header and PCM body', () {
      final samples = Float32List.fromList([0, 1, -1, 0.5]);
      final wav = encodeWav(samples, 24000);

      expect(wav.length, 44 + samples.length * 2);

      final view = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(view.getUint16(22, Endian.little), 1); // mono
      expect(view.getUint32(24, Endian.little), 24000); // sample rate
      expect(view.getUint16(34, Endian.little), 16); // bits per sample

      expect(view.getInt16(44, Endian.little), 0);
      expect(view.getInt16(46, Endian.little), 0x7fff); // +1.0 full scale
      expect(view.getInt16(48, Endian.little), -0x8000); // -1.0 full scale
    });
  });
}
