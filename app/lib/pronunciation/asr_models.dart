// The speech-recognition models the learner can pick from in Settings, and
// which one is picked.
//
// None of them ships in the APK -- the smallest is ~100 MB and the largest
// ~660 MB, against a recognizer that used to cost 40 MB. They are downloaded
// on request by [AsrModelStore] from the sherpa-onnx exports on Hugging Face,
// int8-quantized: on a phone CPU that is the difference between scoring an
// attempt in a second and scoring it in several, for a negligible loss in
// accuracy.
//
// The English-only Whisper checkpoints (tiny.en, small.en), not the
// multilingual ones: the app only ever hears English, and the .en models are
// measurably better at it for the same size.

import 'package:flutter/foundation.dart';

import '../decks/deck_store.dart';

/// How sherpa-onnx has to be configured to run a model.
enum AsrModelKind { whisper, nemoTransducer }

/// One file of a model, and where it is downloaded from.
class AsrModelFile {
  const AsrModelFile(this.name, this.bytes);

  final String name;

  /// The exact size, used both for the progress bar and to tell a finished
  /// download from a truncated one.
  final int bytes;
}

class AsrModel {
  const AsrModel({
    required this.id,
    required this.name,
    required this.summary,
    required this.kind,
    required this.repo,
    required this.files,
    required this.license,
  });

  /// Stable key: the saved setting and the directory name on disk.
  final String id;
  final String name;

  /// One line for Settings: what picking it trades.
  final String summary;
  final AsrModelKind kind;

  /// The Hugging Face repository the files are in.
  final String repo;

  /// Whisper: encoder, decoder, tokens. Transducer: encoder, decoder,
  /// joiner, tokens. [SherpaAsr] relies on that order.
  final List<AsrModelFile> files;
  final String license;

  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  Uri urlOf(AsrModelFile file) =>
      Uri.https('huggingface.co', '/$repo/resolve/main/${file.name}');

  /// Whether this model reports where each word sits and how sure it is of
  /// it. Whisper does neither through sherpa-onnx (its timestamps need a
  /// specially exported decoder), so with it a word cannot be tapped to hear
  /// it back and a Recall answer gets no clarity score.
  bool get hasWordTiming => kind == AsrModelKind.nemoTransducer;
}

const AsrModel kWhisperTiny = AsrModel(
  id: 'whisper-tiny-en',
  name: 'Whisper tiny',
  summary: 'Smallest and fastest. Good for clear speech.',
  kind: AsrModelKind.whisper,
  repo: 'csukuangfj/sherpa-onnx-whisper-tiny.en',
  files: [
    AsrModelFile('tiny.en-encoder.int8.onnx', 12937772),
    AsrModelFile('tiny.en-decoder.int8.onnx', 89853865),
    AsrModelFile('tiny.en-tokens.txt', 835554),
  ],
  license: 'MIT',
);

const AsrModel kWhisperSmall = AsrModel(
  id: 'whisper-small-en',
  name: 'Whisper small',
  summary: 'More accurate than tiny, slower on older phones.',
  kind: AsrModelKind.whisper,
  repo: 'csukuangfj/sherpa-onnx-whisper-small.en',
  files: [
    AsrModelFile('small.en-encoder.int8.onnx', 112442483),
    AsrModelFile('small.en-decoder.int8.onnx', 262223042),
    AsrModelFile('small.en-tokens.txt', 835554),
  ],
  license: 'MIT',
);

const AsrModel kParakeetV2 = AsrModel(
  id: 'parakeet-tdt-0.6b-v2',
  name: 'NVIDIA Parakeet v2',
  summary: 'Most accurate, with word timing and clarity scores.',
  kind: AsrModelKind.nemoTransducer,
  repo: 'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8',
  files: [
    AsrModelFile('encoder.int8.onnx', 652184296),
    AsrModelFile('decoder.int8.onnx', 7257753),
    AsrModelFile('joiner.int8.onnx', 1739080),
    AsrModelFile('tokens.txt', 9384),
  ],
  license: 'CC BY 4.0',
);

/// Every model Settings offers, in the order it lists them.
const List<AsrModel> kAsrModels = [kWhisperTiny, kWhisperSmall, kParakeetV2];

AsrModel asrModelById(String? id) =>
    kAsrModels.firstWhere((m) => m.id == id, orElse: () => kWhisperTiny);

const String _asrModelKey = 'asr_model';

/// The model scoring uses. Whisper tiny until the learner picks another --
/// the cheapest download for a first run.
final ValueNotifier<AsrModel> selectedAsrModel = ValueNotifier(kWhisperTiny);

/// Reads the saved choice; none saved keeps the default.
Future<void> loadAsrModelSetting(DeckStore store) async {
  selectedAsrModel.value = asrModelById(await store.setting(_asrModelKey));
}

/// Switches the recognizer at once and remembers it.
Future<void> saveAsrModel(DeckStore store, AsrModel model) async {
  selectedAsrModel.value = model;
  await store.setSetting(_asrModelKey, model.id);
}
