// sherpa-onnx's result JSON, as the rest of the pipeline is allowed to see it.
//
// The token-to-word gluing is the part worth pinning down: [mapWordTimings]
// throws away every clip when the timed-word count disagrees with the
// transcript's word count, so a punctuation token counted as its own word
// would cost a whole attempt its playback.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/pronunciation/asr_model_store.dart';
import 'package:lingo_node/pronunciation/asr_models.dart';
import 'package:lingo_node/pronunciation/sherpa_asr.dart';

const _length = Duration(seconds: 2);

void main() {
  group('transcriptFromSherpaJson', () {
    test('glues BPE pieces into timed words, punctuation included', () {
      final transcript = transcriptFromSherpaJson({
        'text': ' Hello, wonderful world.',
        'tokens': [' Hel', 'lo', ',', ' wonder', 'ful', ' world', '.'],
        'timestamps': [0.1, 0.2, 0.3, 0.5, 0.7, 1.0, 1.3],
      }, audioLength: _length);

      expect(transcript.text, 'Hello, wonderful world.');
      expect(transcript.words.map((w) => w.text), [
        'Hello,',
        'wonderful',
        'world.',
      ]);
      expect(transcript.words.first.start, const Duration(milliseconds: 100));
      expect(transcript.words[1].start, const Duration(milliseconds: 500));
      expect(transcript.words.last.end, lessThanOrEqualTo(_length));
      expect(transcript.words.every((w) => w.confidence == null), isTrue);
    });

    test('treats SentencePiece word markers like a leading space', () {
      final transcript = transcriptFromSherpaJson({
        'text': 'good morning',
        'tokens': ['▁good', '▁mor', 'ning'],
        'timestamps': [0.0, 0.4, 0.6],
      }, audioLength: _length);

      expect(transcript.words.map((w) => w.text), ['good', 'morning']);
    });

    test('a word does not run on across a pause', () {
      final transcript = transcriptFromSherpaJson({
        'text': ' yes no',
        'tokens': [' yes', ' no'],
        'timestamps': [0.0, 1.5],
      }, audioLength: _length);

      expect(transcript.words.first.end, const Duration(milliseconds: 600));
    });

    test('drops words that are only punctuation', () {
      final transcript = transcriptFromSherpaJson({
        'text': ' ok -',
        'tokens': [' ok', ' -'],
        'timestamps': [0.0, 0.5],
      }, audioLength: _length);

      expect(transcript.text, 'ok');
      expect(transcript.words, hasLength(1));
    });

    test('reads a confidence from log probabilities', () {
      final transcript = transcriptFromSherpaJson({
        'text': ' hi',
        'tokens': [' h', 'i'],
        'timestamps': [0.0, 0.1],
        'ys_log_probs': [0.0, -0.2],
      }, audioLength: _length);

      expect(transcript.words.single.confidence, closeTo(0.905, 0.001));
    });

    test('keeps text only when there are no timestamps (Whisper)', () {
      final transcript = transcriptFromSherpaJson({
        'text': ' [BLANK_AUDIO] I like tea.',
        'tokens': [' I', ' like', ' tea', '.'],
        'timestamps': <double>[],
      }, audioLength: _length);

      expect(transcript.text, 'I like tea.');
      expect(transcript.words, isEmpty);
    });

    test('an empty result is an empty transcript', () {
      final transcript = transcriptFromSherpaJson({
        'text': '',
      }, audioLength: _length);

      expect(transcript.text, isEmpty);
      expect(transcript.words, isEmpty);
    });
  });

  test('pcm16ToFloat32 scales little-endian samples', () {
    final pcm = Uint8List.fromList([0x00, 0x00, 0x00, 0x40, 0x00, 0x80]);
    expect(pcm16ToFloat32(pcm), [0.0, 0.5, -1.0]);
  });

  group('AsrModelStore', () {
    late Directory root;
    late AsrModelStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('asr_models_test');
      store = AsrModelStore(root: () async => root);
    });

    tearDown(() async {
      store.dispose();
      await root.delete(recursive: true);
    });

    Future<void> fill(AsrModel model, {int short = 0}) async {
      final dir = await store.dirOf(model);
      await dir.create(recursive: true);
      for (final file in model.files) {
        final f = File('${dir.path}/${file.name}');
        final raf = await f.open(mode: FileMode.write);
        await raf.truncate(file.bytes - short);
        await raf.close();
      }
    }

    test('a model counts as downloaded only with every byte present', () async {
      await fill(kWhisperTiny, short: 1);
      await fill(kParakeetV2);
      await store.refresh();

      expect(store.isDownloaded(kWhisperTiny), isFalse);
      expect(store.isDownloaded(kParakeetV2), isTrue);
      expect(store.isDownloaded(kWhisperSmall), isFalse);
    });

    test('delete removes the files', () async {
      await fill(kParakeetV2);
      await store.refresh();
      await store.delete(kParakeetV2);

      expect(store.isDownloaded(kParakeetV2), isFalse);
      expect(await (await store.dirOf(kParakeetV2)).exists(), isFalse);
    });
  });
}
