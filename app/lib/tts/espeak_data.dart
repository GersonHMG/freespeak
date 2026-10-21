// Gets eSpeak-NG's data files onto the filesystem, where the native library
// can read them.
//
// eSpeak-NG will not phonemize anything without `phontab`, `phonindex` and
// `phondata` in a real directory — it opens them by path, so a Flutter asset
// is not good enough. The `espeak_ng` package ships the whole set as a zip
// and declares it as a package asset, so the bytes arrive through rootBundle
// and are unpacked here, once.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The zip as `espeak_ng` declares it. ~9 MB, holding every language eSpeak
/// supports; only `en_dict` and the phon* tables are ever read, so this is the
/// obvious thing to trim when APK size matters.
const String _espeakDataAsset = 'packages/espeak_ng/assets/espeak_ng_data.zip';

Future<String>? _ensured;

/// Extracts the data once and returns the directory that *contains*
/// `espeak-ng-data` — which is the shape eSpeak's initializer wants.
///
/// Idempotent and retry-safe: a run that already extracted is a single
/// `existsSync` check, and a failure clears the memo so the next call retries.
Future<String> ensureEspeakData() {
  return _ensured ??= _extract().catchError((Object err) {
    _ensured = null;
    throw err;
  });
}

Future<String> _extract() async {
  final support = await getApplicationSupportDirectory();
  final base = p.join(support.path, 'espeak');
  final phontab = File(p.join(base, 'espeak-ng-data', 'phontab'));
  if (phontab.existsSync()) return base;

  final data = await rootBundle.load(_espeakDataAsset);
  final archive = ZipDecoder().decodeBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );

  // Entry names already carry the `espeak-ng-data/` prefix, so they are
  // joined onto the base directory as-is.
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/').trim();
    if (name.isEmpty) continue;
    final path = p.join(base, name);
    if (entry.isFile) {
      final out = File(path);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(entry.readBytes() ?? const <int>[]);
    } else {
      Directory(path).createSync(recursive: true);
    }
  }

  if (!phontab.existsSync()) {
    throw StateError(
      'espeak-ng-data extracted to $base but phontab is missing — '
      'the bundled zip is not the layout eSpeak expects.',
    );
  }
  if (kDebugMode) debugPrint('[espeak] data ready at $base');
  return base;
}
