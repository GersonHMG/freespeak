// Pronunciation against a spoken reference instead of a dictionary one.
//
// Everywhere else the reference is text: the phrase is phonemized, and the
// recognizer's output for the learner is aligned against those dictionary
// phonemes. That compares two different things -- what a lexicon says and
// what a model hears -- so every habit of the model (a vowel it always
// hears lax, a consonant it always drops) is charged to the learner.
//
// This screen makes the reference the same kind of thing as the attempt.
// Phonon speaks the phrase; the recognizer listens to that audio; what it
// heard becomes the reference. The learner's recording goes through the same
// recognizer, and the two are aligned with the app's usual phrase-wide
// alignment:
//
//   reference  = recognizer(TTS audio)
//   attempt    = recognizer(recording)
//   accuracy   = (phonemes - mismatches) / phonemes, per word and overall
//
// The recognizer's systematic errors now land on both sides and cancel. The
// card also shows the two numbers this is meant to be read against: how well
// the recognizer's hearing of the TTS agrees with the dictionary, and the
// app's ordinary text-reference score for the same attempt.
//
// Vosk hears words, so its reference is the text it transcribes from the
// TTS. The attempt is then scored with the app's ordinary Vosk path, with
// that transcript standing in for the phrase: the dictionary phonemes of the
// words Vosk heard in the TTS against those of the words it heard from you.
//
// Phonon's library is built for arm64 phones (ARMv8.2) and the x86_64 emulator.

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../pronunciation/category.dart';
import '../../pronunciation/mispronounce_detector.dart';
import '../../pronunciation/recorder.dart';
import '../../pronunciation/wav_pcm.dart';
import '../../tts/phonon_tts.dart';

const String _sampleAsset = 'assets/debug/prod1.wav';

class TtsReferenceScreen extends StatefulWidget {
  // Passed in rather than read from the scopes: the pushed route sits above
  // them.
  const TtsReferenceScreen({
    super.key,
    required this.detector,
    required this.tts,
  });

  final MispronounceDetector detector;
  final PhononTts tts;

  @override
  State<TtsReferenceScreen> createState() => _TtsReferenceScreenState();
}

/// The synthesized reference, shared by every model.
class _Reference {
  const _Reference({
    required this.text,
    required this.speech,
    required this.asrPath,
  });

  final String text;
  final Speech speech;

  /// [speech]'s audio at 16 kHz mono -- what the models read.
  final String asrPath;
}

/// One reference word's line on a card.
class _WordRow {
  const _WordRow({
    required this.word,
    required this.accuracy,
    required this.reference,
    required this.spoken,
    required this.skipped,
    required this.scored,
  });

  final String word;
  final double accuracy;
  final String reference;
  final String spoken;
  final bool skipped;

  /// False for a word with no reference phonemes, which the score ignores.
  final bool scored;
}

/// One model's view of the reference and of the attempt.
abstract class _ModelRun {
  _ModelRun(this.name, this.kind);

  final String name;
  final String kind;

  bool running = false;
  String? error;

  // --- The reference, as this model heard it.
  Duration? referenceElapsed;

  /// What the model heard in the TTS, for display.
  String? referenceHeard;

  /// The model's hearing of the TTS scored against the dictionary: how far
  /// the model and the phonemizer agree before any learner is involved.
  int? ttsVsDictionary;

  // --- The attempt.
  Duration? attemptElapsed;
  String? attemptHeard;
  int? overall;

  /// The same attempt scored the usual way, against the text.
  int? textReferenceScore;
  List<_WordRow> rows = const [];

  /// Whether [hearReference] succeeded, so an attempt can be scored.
  bool get hasReference;

  Future<void> hearReference(_Reference reference, MispronounceDetector det);

  Future<void> hearAttempt(
    String path,
    _Reference reference,
    MispronounceDetector det,
  );

  void clearAttempt() {
    attemptElapsed = null;
    attemptHeard = null;
    overall = null;
    textReferenceScore = null;
    rows = const [];
  }

  void clearAll() {
    error = null;
    referenceElapsed = null;
    referenceHeard = null;
    ttsVsDictionary = null;
    clearReference();
    clearAttempt();
  }

  void clearReference();
}

/// Vosk: the reference is the text it transcribes from the TTS.
class _VoskModelRun extends _ModelRun {
  _VoskModelRun() : super('Vosk', 'words');

  String? _referenceText;

  @override
  bool get hasReference => _referenceText != null;

  @override
  void clearReference() => _referenceText = null;

  @override
  Future<void> hearReference(
    _Reference reference,
    MispronounceDetector det,
  ) async {
    await det.ready();
    final timer = Stopwatch()..start();
    final (_, transcript) = await det.transcribe(reference.asrPath);
    referenceElapsed = timer.elapsed;
    referenceHeard = [
      '"${transcript.text}"',
      for (final w in transcript.words)
        '${w.text} ${w.start.inMilliseconds}-${w.end.inMilliseconds}',
    ].join('  ');
    ttsVsDictionary = (await det.scoreTranscript(
      transcript,
      reference.text,
    )).overall;
    if (transcript.text.trim().isEmpty) {
      throw StateError('Vosk heard no words in the TTS.');
    }
    _referenceText = transcript.text;
  }

  @override
  Future<void> hearAttempt(
    String path,
    _Reference reference,
    MispronounceDetector det,
  ) async {
    final timer = Stopwatch()..start();
    final (recordingPath, transcript) = await det.transcribe(path);
    attemptElapsed = timer.elapsed;
    attemptHeard = '"${transcript.text}"';
    final result = await det.scoreTranscript(
      transcript,
      _referenceText!,
      recordingPath: recordingPath,
    );
    overall = result.overall;
    rows = [
      for (final w in result.words)
        _WordRow(
          word: w.word,
          accuracy: w.accuracy,
          reference: w.referencePhonemes,
          spoken: w.spokenPhonemes,
          skipped: w.wasSkipped,
          scored: w.referencePhonemes.isNotEmpty,
        ),
    ];
    textReferenceScore = (await det.scoreTranscript(
      transcript,
      reference.text,
      recordingPath: recordingPath,
    )).overall;
  }
}

class _TtsReferenceScreenState extends State<TtsReferenceScreen> {
  final TextEditingController _text = TextEditingController(
    text: 'Hi, this is a test',
  );
  final PronunciationRecorder _recorder = PronunciationRecorder();
  final AudioPlayer _player = AudioPlayer();

  late final List<_ModelRun> _models = [_VoskModelRun()];

  bool _busy = false;
  bool _isRecording = false;
  String? _error;
  String? _status;

  _Reference? _reference;
  Duration? _synthesisElapsed;

  /// A recording made on this screen; null means the bundled sample.
  String? _recordingPath;
  String? _samplePath;

  @override
  void dispose() {
    _text.dispose();
    _recorder.dispose();
    _player.dispose();
    // Vosk belongs to the app's detector and outlives this screen.
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
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  // --- Reference.

  /// The reference for the current text, synthesized and heard by every
  /// model; reused until the text changes.
  Future<_Reference> _ensureReference() async {
    final text = _text.text.trim();
    if (text.isEmpty) throw StateError('Enter the text to practise.');
    final cached = _reference;
    if (cached != null && cached.text == text) return cached;

    for (final model in _models) {
      model.clearAll();
    }
    setState(() => _reference = null);

    _setStatus('Synthesizing...');
    final timer = Stopwatch()..start();
    final speech = await widget.tts.speakTimed(text);
    _synthesisElapsed = timer.elapsed;
    final reference = _Reference(
      text: text,
      speech: speech,
      asrPath: await ensureAsrWav(speech.path),
    );

    for (final model in _models) {
      _setStatus('${model.name}: listening to the reference...');
      await _guarded(
        model,
        () => model.hearReference(reference, widget.detector),
      );
    }

    if (mounted) setState(() => _reference = reference);
    return reference;
  }

  Future<void> _generate() => _run(() async {
    final reference = await _ensureReference();
    await _player.play(DeviceFileSource(reference.speech.path));
  });

  Future<void> _playReference() => _run(() async {
    final reference = _reference;
    if (reference != null) {
      await _player.play(DeviceFileSource(reference.speech.path));
    }
  });

  // --- Attempt.

  Future<String> _samplePathOnDisk() async {
    final cached = _samplePath;
    if (cached != null && File(cached).existsSync()) return cached;
    final data = await rootBundle.load(_sampleAsset);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/prod1.wav');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return _samplePath = file.path;
  }

  Future<String> _attemptPath() async =>
      _recordingPath ?? await _samplePathOnDisk();

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        if (path == null) _error = 'Recording too short -- try again.';
      });
      if (path != null) {
        _recordingPath = path;
        await _compare();
      }
      return;
    }
    final started = await _recorder.start(slot: 'tts-reference');
    if (!mounted) return;
    setState(() {
      _isRecording = started;
      _error = started ? null : 'Microphone permission refused.';
    });
  }

  Future<void> _playAttempt() => _run(() async {
    await _player.play(DeviceFileSource(await _attemptPath()));
  });

  Future<void> _compare() => _run(() async {
    final reference = await _ensureReference();
    final attempt = await ensureAsrWav(await _attemptPath());

    for (final model in _models) {
      model.clearAttempt();
      if (!model.hasReference) continue; // its reference failed
      _setStatus('${model.name}: listening to you...');
      await _guarded(
        model,
        () => model.hearAttempt(attempt, reference, widget.detector),
      );
    }
  });

  /// Runs one model's step, keeping its failure on its own card rather than
  /// aborting the others.
  Future<void> _guarded(_ModelRun model, Future<void> Function() body) async {
    setState(() {
      model
        ..running = true
        ..error = null;
    });
    try {
      await body();
    } catch (err) {
      model.error = '$err';
    } finally {
      model.running = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = _reference;
    final idle = !_busy && !_isRecording;

    return Scaffold(
      appBar: AppBar(title: const Text('TTS reference')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _text,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Text to practise',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Reference (Phonon)', style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: idle ? _generate : null,
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: const Text('Generate'),
                ),
                TextButton.icon(
                  onPressed: idle && reference != null ? _playReference : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ],
            ),
            if (reference != null)
              Text(
                [
                      for (final w in reference.speech.words)
                        '${w.text} ${w.start.inMilliseconds}-'
                            '${w.end.inMilliseconds}',
                    ].join(' · ') +
                    (_synthesisElapsed == null
                        ? ''
                        : '  (synth ${_synthesisElapsed!.inMilliseconds} ms)'),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              _recordingPath == null
                  ? 'Attempt: sample $_sampleAsset'
                  : 'Attempt: your recording',
              style: theme.textTheme.labelLarge,
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic_none),
                  label: Text(_isRecording ? 'Stop' : 'Record'),
                ),
                TextButton.icon(
                  onPressed: idle ? _playAttempt : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
                if (_recordingPath != null)
                  TextButton.icon(
                    onPressed: idle
                        ? () => setState(() {
                            _recordingPath = null;
                            for (final model in _models) {
                              model.clearAttempt();
                            }
                          })
                        : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('Use sample'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: idle ? _compare : null,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.compare_arrows),
              label: const Text('Compare against TTS'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(_status!, style: theme.textTheme.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(_error!),
            ],
            if (reference != null)
              for (final model in _models) ...[
                const SizedBox(height: 12),
                _ModelCard(model),
              ],
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard(this.model);

  final _ModelRun model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final timing = [
      if (model.referenceElapsed != null)
        'reference ${model.referenceElapsed!.inMilliseconds} ms',
      if (model.attemptElapsed != null)
        'attempt ${model.attemptElapsed!.inMilliseconds} ms',
    ].join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${model.name} (${model.kind})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (model.running)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (model.overall != null)
                  Text(
                    '${model.overall}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            if (timing.isNotEmpty)
              Text(timing, style: theme.textTheme.labelSmall),
            if (model.error != null) ...[
              const SizedBox(height: 8),
              _ErrorCard(model.error!),
            ],
            if (model.referenceHeard != null) ...[
              const SizedBox(height: 8),
              Text('TTS heard as:', style: theme.textTheme.labelMedium),
              Text(model.referenceHeard!, style: mono),
              if (model.ttsVsDictionary != null)
                Text(
                  'TTS vs dictionary: ${model.ttsVsDictionary}%',
                  style: mono,
                ),
            ],
            if (model.attemptHeard != null) ...[
              const SizedBox(height: 8),
              Text('You:', style: theme.textTheme.labelMedium),
              Text(model.attemptHeard!, style: mono),
              if (model.overall != null)
                Text('vs TTS reference: ${model.overall}%', style: mono),
              if (model.textReferenceScore != null)
                Text(
                  'vs text reference: ${model.textReferenceScore}%',
                  style: mono,
                ),
            ],
            if (model.rows.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final row in model.rows) _wordLine(row, mono),
            ],
          ],
        ),
      ),
    );
  }

  Widget _wordLine(_WordRow row, TextStyle? style) {
    final marker = !row.scored
        ? '  '
        : row.skipped
        ? '⬜'
        : switch (categoryForAccuracy(row.accuracy)) {
            PronunciationCategory.good => '🟩',
            PronunciationCategory.mediocre => '🟨',
            PronunciationCategory.bad => '🟥',
          };
    return Text(
      '$marker ${row.word.padRight(12)} '
      '${row.accuracy.round().toString().padLeft(3)}%  '
      '[${row.reference} vs ${row.spoken}]',
      style: style,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}
