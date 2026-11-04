// Downloads, keeps and deletes the speech-recognition models in
// asr_models.dart, under the app's support directory:
//
//   <support>/asr_models/<model id>/<file name>
//
// A file is downloaded to `<name>.part` and renamed only once it has every
// byte [AsrModelFile.bytes] says it should, so a file under its real name is
// always a complete one and "downloaded" is just "every file exists". An
// interrupted download leaves its `.part` behind and the next attempt resumes
// from it with a Range request -- worth it when one file is 650 MB on a phone
// connection.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'asr_models.dart';

/// Thrown by a download the learner cancelled.
class AsrDownloadCancelled implements Exception {
  const AsrDownloadCancelled();

  @override
  String toString() => 'Download cancelled';
}

class AsrModelStore extends ChangeNotifier {
  AsrModelStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  /// Ids of the models whose files are all on disk. Filled by [refresh].
  final Set<String> _downloaded = {};

  /// Download progress, 0-1, by model id, for the downloads in flight.
  final Map<String, double> _progress = {};
  final Set<String> _cancelled = {};

  bool isDownloaded(AsrModel model) => _downloaded.contains(model.id);

  bool isDownloading(AsrModel model) => _progress.containsKey(model.id);

  /// 0-1 while [model] is downloading, null otherwise.
  double? progressOf(AsrModel model) => _progress[model.id];

  Future<Directory> dirOf(AsrModel model) async =>
      Directory(p.join((await _root()).path, 'asr_models', model.id));

  /// Absolute paths of [model]'s files, in [AsrModel.files] order.
  Future<List<String>> pathsOf(AsrModel model) async {
    final dir = await dirOf(model);
    return [for (final file in model.files) p.join(dir.path, file.name)];
  }

  /// Re-reads which models are on disk. Call once at startup.
  Future<void> refresh() async {
    for (final model in kAsrModels) {
      if (await _isComplete(model)) {
        _downloaded.add(model.id);
      } else {
        _downloaded.remove(model.id);
      }
    }
    notifyListeners();
  }

  Future<bool> _isComplete(AsrModel model) async {
    final dir = await dirOf(model);
    for (final file in model.files) {
      final f = File(p.join(dir.path, file.name));
      if (!await f.exists() || await f.length() != file.bytes) return false;
    }
    return true;
  }

  /// Downloads every missing file of [model]. A second call while one is
  /// already running is a no-op. Throws [AsrDownloadCancelled] after
  /// [cancel], and network or disk errors as they come.
  Future<void> download(AsrModel model) async {
    if (isDownloading(model) || isDownloaded(model)) return;
    _cancelled.remove(model.id);
    _progress[model.id] = 0;
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final dir = await dirOf(model);
      await dir.create(recursive: true);

      var doneBytes = 0;
      for (final file in model.files) {
        final target = File(p.join(dir.path, file.name));
        if (await target.exists() && await target.length() == file.bytes) {
          doneBytes += file.bytes;
          continue;
        }
        await _downloadFile(client, model, file, target, (fileBytes) {
          _progress[model.id] = (doneBytes + fileBytes) / model.totalBytes;
          notifyListeners();
        });
        doneBytes += file.bytes;
      }
      _downloaded.add(model.id);
    } finally {
      client.close(force: true);
      _progress.remove(model.id);
      _cancelled.remove(model.id);
      notifyListeners();
    }
  }

  Future<void> _downloadFile(
    HttpClient client,
    AsrModel model,
    AsrModelFile file,
    File target,
    void Function(int bytesSoFar) onProgress,
  ) async {
    final part = File('${target.path}.part');
    var have = await part.exists() ? await part.length() : 0;
    if (have > file.bytes) {
      await part.delete();
      have = 0;
    }

    final request = await client.getUrl(model.urlOf(file));
    if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    final response = await request.close();

    final resumed = response.statusCode == HttpStatus.partialContent;
    if (!resumed && response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'HTTP ${response.statusCode} for ${file.name}',
        uri: model.urlOf(file),
      );
    }
    // A server that ignored the Range header sends the whole file again.
    if (!resumed) have = 0;

    final sink = part.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var written = have;
    var lastReported = 0;
    try {
      await for (final chunk in response) {
        if (_cancelled.contains(model.id)) throw const AsrDownloadCancelled();
        sink.add(chunk);
        written += chunk.length;
        // Every 512 KB is smooth enough for a progress bar without
        // rebuilding Settings thousands of times per file.
        if (written - lastReported >= 512 * 1024) {
          lastReported = written;
          onProgress(written);
        }
      }
    } finally {
      await sink.close();
    }

    if (written != file.bytes) {
      // Over-long means the .part was not what we thought; start it over.
      if (written > file.bytes) await part.delete();
      throw HttpException(
        '${file.name}: got $written of ${file.bytes} bytes',
        uri: model.urlOf(file),
      );
    }
    await part.rename(target.path);
    onProgress(written);
  }

  /// Stops [model]'s download at the next chunk. What has arrived so far is
  /// kept, and a later [download] resumes from it.
  void cancel(AsrModel model) {
    if (isDownloading(model)) _cancelled.add(model.id);
  }

  /// Removes [model]'s files, finished or partial.
  Future<void> delete(AsrModel model) async {
    cancel(model);
    final dir = await dirOf(model);
    if (await dir.exists()) await dir.delete(recursive: true);
    _downloaded.remove(model.id);
    notifyListeners();
  }
}
