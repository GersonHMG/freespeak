// A bench for the pronunciation pipeline, and the Dart equivalent of the RN
// app's test-mispronounce.ts: a WAV and a reference sentence go in, the same
// per-word breakdown that script printed to a terminal comes out here.
//
// Uses the bundled assets/debug/prod1.wav -- the identical fixture that test
// script shipped with -- copied to a temp file once, since the recognizer reads
// from disk rather than from an asset handle.

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../pronunciation/category.dart';
import '../../pronunciation/mispronounce_detector.dart';
import '../../pronunciation/pronunciation_result.dart';

const String _sampleAsset = 'assets/debug/prod1.wav';

class PronunciationDebugScreen extends StatefulWidget {
  // Passed in rather than read from PronunciationScope: this screen is opened
  // as a pushed route, and the Navigator sits above the scope in the tree, so
  // an inherited lookup from here finds nothing -- same reasoning as
  // TtsDebugScreen taking its engine as a constructor argument.
  const PronunciationDebugScreen({super.key, required this.detector});

  final MispronounceDetector detector;

  @override
  State<PronunciationDebugScreen> createState() =>
      _PronunciationDebugScreenState();
}

class _PronunciationDebugScreenState extends State<PronunciationDebugScreen> {
  final TextEditingController _text = TextEditingController(
    text: 'Hi, this is a test',
  );
  final AudioPlayer _player = AudioPlayer();

  bool _busy = false;
  String? _error;
  String? _samplePath;
  PronunciationResult? _result;

  @override
  void dispose() {
    _text.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Copies the bundled fixture out of the asset bundle the first time it is
  /// needed. The recognizer transcribes a file path, not asset bytes.
  Future<String> _samplePathOnDisk() async {
    final cached = _samplePath;
    if (cached != null && File(cached).existsSync()) return cached;

    final data = await rootBundle.load(_sampleAsset);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/prod1.wav');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    _samplePath = file.path;
    return file.path;
  }

  Future<void> _playSample() => _run(() async {
    final path = await _samplePathOnDisk();
    await _player.play(DeviceFileSource(path));
  });

  Future<void> _score() => _run(() async {
    final reference = _text.text.trim();
    if (reference.isEmpty) {
      setState(() => _error = 'Enter the text the sample is saying.');
      return;
    }
    final path = await _samplePathOnDisk();
    // Loads the recognizer's weights on first call if they are not warm
    // already -- worth knowing about if this seems to hang on a fresh
    // install with no network, since that download is what it is doing.
    final result = await widget.detector.score(path, reference);
    if (!mounted) return;
    setState(() => _result = result);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Pronunciation debugger')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Sample: assets/debug/prod1.wav',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _playSample,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play sample'),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _text,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Reference text (what the sample is saying)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            FilledButton.icon(
              onPressed: _busy ? null : _score,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: const Text('Score sample against text'),
            ),
            const SizedBox(height: 16),

            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),

            if (result != null) ...[
              const SizedBox(height: 8),
              Text(
                'Heard: "${result.spokenText}"',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Overall: ${result.overall}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text('Per word', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final word in result.words)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_marker(word.category, word.wasSkipped)} '
                    '${word.word.padRight(14)} '
                    '${word.accuracy.round().toString().padLeft(3)}%  '
                    '[${word.referencePhonemes} vs ${word.spokenPhonemes}]'
                    '${word.wasSkipped ? '  (not spoken)' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Mispronounced', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              if (result.mispronounced.isEmpty)
                const Text('(none -- clean read)')
              else
                for (final word in result.mispronounced)
                  Text(
                    '${_marker(word.category, word.wasSkipped)} '
                    '${word.word} -- ${word.accuracy.round()}% '
                    '(${word.wasSkipped ? 'not spoken' : word.category.label})',
                  ),
            ],
          ],
        ),
      ),
    );
  }

  String _marker(PronunciationCategory category, bool wasSkipped) {
    if (wasSkipped) return '⬜';
    return switch (category) {
      PronunciationCategory.good => '🟩',
      PronunciationCategory.mediocre => '🟨',
      PronunciationCategory.bad => '🟥',
    };
  }
}
