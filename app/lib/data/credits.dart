// The open-source work the app is built on, and the licence each comes
// under. AboutScreen lists [kCredits]; [registerCreditLicenses] puts their
// licence texts on Flutter's licence page next to the Dart packages', which
// Flutter collects by itself.
//
// Apache-2.0 and CC BY require this attribution inside the distributed app,
// not only in the repository.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One credited project.
class Credit {
  const Credit({
    required this.name,
    required this.by,
    required this.use,
    required this.license,
    required this.licenseAsset,
    this.url,
  });

  final String name;

  /// Who made it; empty when the name says it.
  final String by;

  /// What the app uses it for.
  final String use;

  /// The licence's short name.
  final String license;

  /// The licence text, bundled under assets/.
  final String licenseAsset;

  final String? url;
}

const List<Credit> kCredits = [
  Credit(
    name: 'Phonon',
    by: 'Gradium',
    use: 'The voice that reads sentences aloud',
    license: 'Apache-2.0',
    licenseAsset: 'assets/licenses/Apache-2.0.txt',
    url: 'https://gradium.ai/phonon',
  ),
  Credit(
    name: 'sherpa-onnx',
    by: 'Next-gen Kaldi',
    use: 'Offline speech recognition',
    license: 'Apache-2.0',
    licenseAsset: 'assets/licenses/Apache-2.0.txt',
    url: 'https://github.com/k2-fsa/sherpa-onnx',
  ),
  Credit(
    name: 'Whisper',
    by: 'OpenAI',
    use: 'The Whisper tiny and small speech models',
    license: 'MIT',
    licenseAsset: 'assets/licenses/MIT-whisper.txt',
    url: 'https://github.com/openai/whisper',
  ),
  Credit(
    name: 'Parakeet TDT 0.6B v2',
    by: 'NVIDIA',
    use: 'The Parakeet speech model',
    license: 'CC BY 4.0',
    licenseAsset: 'assets/licenses/CC-BY-4.0.txt',
    url: 'https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2',
  ),
  Credit(
    name: 'eSpeak NG',
    by: '',
    use: 'Turning text into phonemes',
    license: 'GPL-3.0',
    licenseAsset: 'assets/licenses/GPL-3.0.txt',
    url: 'https://github.com/espeak-ng/espeak-ng',
  ),
  Credit(
    name: 'flutter_kokoro_tts',
    by: 'Pius Ikeoffiah',
    use: 'The start of the eSpeak NG binding',
    license: 'MIT',
    licenseAsset: 'assets/licenses/MIT-flutter_kokoro_tts.txt',
    url: 'https://github.com/ikeoffiah/kokoro_tts',
  ),
  Credit(
    name: 'Tatoeba',
    by: '',
    use: 'Example sentences',
    license: 'CC BY 2.0 FR',
    licenseAsset: 'assets/licenses/CC-BY-2.0-FR-tatoeba.txt',
    url: 'https://tatoeba.org',
  ),
  Credit(
    name: 'Manrope',
    by: 'The Manrope Project Authors',
    use: 'The typeface',
    license: 'SIL Open Font License 1.1',
    licenseAsset: 'assets/fonts/OFL.txt',
    url: 'https://github.com/googlefonts/manrope',
  ),
];

/// Adds every credit's licence to [LicenseRegistry]. Call once, before
/// runApp. The texts are read only when the licence page asks for them.
void registerCreditLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final credit in kCredits) {
      final text = await rootBundle.loadString(credit.licenseAsset);
      yield LicenseEntryWithLineBreaks([credit.name], text);
    }
  });
}
