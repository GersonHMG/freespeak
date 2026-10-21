// A bench for raw word timing, independent of scoring.
//
// PronunciationDebugScreen exercises MispronounceDetector.score, which folds
// transcription together with reference-word alignment -- useful for testing
// scoring, but it never shows the "word map" on its own: given some audio,
// exactly what did the recognizer hear, and exactly where does it think each
// word sits in the recording. This screen isolates that: a sentence, spoken
// either by the TTS voice or live into the mic, transcribed, and every
// recognized word made tappable to hear just that stretch of the recording,
// checking the reported boundaries by ear. A separate scrub bar covers the
// case those boundaries turn out to be wrong -- picking any other point to
// play from.
//
// The recognizer is the detector's own [VoskAsr], so what this screen shows
// is exactly what practice scoring works from.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../pronunciation/asr.dart';
import '../../pronunciation/mispronounce_detector.dart';
import '../../pronunciation/recorder.dart';
import '../../tts/phonon_tts.dart';

class WordMapDebugScreen extends StatefulWidget {
  // Passed in rather than read from a scope: this screen is opened as a
  // pushed route, and the Navigator sits above the scopes in the tree, same
  // reasoning as PronunciationDebugScreen and TtsDebugScreen.
  const WordMapDebugScreen({
    super.key,
    required this.detector,
    required this.tts,
  });

  final MispronounceDetector detector;
  final PhononTts tts;

  @override
  State<WordMapDebugScreen> createState() => _WordMapDebugScreenState();
}

/// Formats [d] as `m:ss.mmm` -- coarser than raw milliseconds for reading at
/// a glance, but still exact enough to line up with a word's boundary.
String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60);
  final millis = d.inMilliseconds.remainder(1000);
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

class _WordMapDebugScreenState extends State<WordMapDebugScreen> {
  final TextEditingController _text = TextEditingController(
    text: 'The quick brown fox jumps over the lazy dog',
  );
  final PronunciationRecorder _recorder = PronunciationRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _busy = false;
  bool _isRecording = false;
  String? _error;
  // What _busy is currently doing -- distinct from _error, and shown instead
  // of it, so a slow step doesn't look like a stuck screen.
  String? _status;
  String? _audioPath;
  Transcript? _transcript;

  // Scrub state for playing the loaded recording from an arbitrary point,
  // including one seeded by tapping a word below -- this is what lets a
  // recognizer-reported boundary be checked by ear rather than trusted.
  Duration? _duration;
  int _scrubMs = 0;
  bool _isDraggingSlider = false;
  bool _isPlaying = false;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _segmentStopTimer;

  @override
  void initState() {
    super.initState();
    // Mirrors playback position onto the scrub slider so it sweeps past the
    // point in question -- the whole reason to scrub is seeing whether the
    // sound actually starts where a timestamp claims it does. Suppressed
    // while the user is dragging so the stream doesn't fight their thumb.
    _positionSub = _player.onPositionChanged.listen((position) {
      if (_isDraggingSlider || !mounted) return;
      setState(() => _scrubMs = position.inMilliseconds);
    });
    // Drives the merged play/stop button's icon and label.
    _playerStateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _recorder.dispose();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _segmentStopTimer?.cancel();
    // The detector's Vosk engine belongs to the app and outlives this
    // screen, so it is not disposed here.
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
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _speakWithTts() => _run(() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Enter a sentence first.');
      return;
    }
    final path = await widget.tts.speak(text);
    await _loadAudio(path);
  });

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path == null) {
        setState(() => _error = 'That was too short to transcribe.');
        return;
      }
      await _run(() => _loadAudio(path));
      return;
    }

    final started = await _recorder.start();
    if (!mounted) return;
    if (!started) {
      setState(() => _error = 'Microphone permission is needed to record.');
      return;
    }
    setState(() {
      _isRecording = true;
      _error = null;
      _audioPath = null;
      _transcript = null;
      _duration = null;
      _scrubMs = 0;
    });
  }

  /// Transcribes [path] and stores the result -- the exact file the
  /// recognizer decoded (see [MispronounceDetector.transcribe]), not
  /// necessarily [path] itself, since that is what the scrub bar plays back
  /// and what word timestamps are relative to.
  Future<void> _loadAudio(String path) async {
    setState(() {
      _transcript = null;
      _duration = null;
      _scrubMs = 0;
      _status = 'Transcribing with Vosk...';
    });
    final (recordingPath, transcript) = await widget.detector.transcribe(path);
    if (!mounted) return;

    // Loads the full recording as the player's source (without starting
    // playback) purely to read its length for the scrub slider's range.
    await _player.setSourceDeviceFile(recordingPath);
    final duration = await _player.getDuration();

    if (!mounted) return;
    setState(() {
      _audioPath = recordingPath;
      _transcript = transcript;
      _duration = duration;
    });
  }

  /// Plays the loaded recording starting at [_scrubMs] -- an arbitrary point
  /// the developer picked, not necessarily a word boundary. This is how a
  /// suspicious timestamp gets checked: scrub to just before it and listen
  /// for exactly where the sound starts.
  Future<void> _playFromScrub() async {
    final audioPath = _audioPath;
    if (audioPath == null) return;
    // Otherwise a still-pending auto-stop from a previous word tap would cut
    // this playback off too, at whatever point that word's span ended.
    _segmentStopTimer?.cancel();
    try {
      await _player.stop();
      await _player.play(
        DeviceFileSource(audioPath),
        position: Duration(milliseconds: _scrubMs),
      );
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    }
  }

  Future<void> _stopPlayback() {
    _segmentStopTimer?.cancel();
    return _player.stop();
  }

  /// Plays just [word]'s reported span -- start to end -- so a boundary can
  /// be checked by ear without also seeding and hunting through the scrub
  /// bar. Implemented as play-then-auto-stop against the already-loaded full
  /// recording, rather than cutting a clip file, since nothing here needs a
  /// clip to persist past this one playback.
  Future<void> _playWordSegment(TimedWord word) async {
    final audioPath = _audioPath;
    if (audioPath == null) return;
    _segmentStopTimer?.cancel();
    setState(() => _scrubMs = word.start.inMilliseconds);
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(audioPath), position: word.start);

      // A degenerate or missing end timestamp would otherwise stop playback
      // immediately -- audible silence isn't useful for checking a boundary,
      // so a short floor is used instead, same reasoning as
      // kMinWordClipDuration in wav_pcm.dart.
      final span = word.end - word.start;
      final segmentDuration = span > Duration.zero
          ? span
          : const Duration(milliseconds: 150);
      _segmentStopTimer = Timer(segmentDuration, () {
        if (mounted) _player.stop();
      });
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    }
  }

  void _nudgeScrub(int deltaMs) {
    final duration = _duration;
    if (duration == null) return;
    setState(() {
      _scrubMs = (_scrubMs + deltaMs).clamp(0, duration.inMilliseconds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transcript = _transcript;

    return Scaffold(
      appBar: AppBar(title: const Text('Word map debugger')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _text,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: 'Sentence',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || _isRecording ? null : _speakWithTts,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Speak (TTS)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _toggleRecording,
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label: Text(_isRecording ? 'Stop' : 'Record'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status ?? 'Working...',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),

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

            if (transcript != null) ...[
              const SizedBox(height: 8),
              Text(
                'Vosk heard: "${transcript.text}"',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _ScrubBar(
                positionMs: _scrubMs,
                duration: _duration,
                onChanged: (ms) => setState(() => _scrubMs = ms),
                onDragStart: () => _isDraggingSlider = true,
                onDragEnd: () => _isDraggingSlider = false,
                onNudge: _nudgeScrub,
                isPlaying: _isPlaying,
                onPlayPause: _isPlaying
                    ? _stopPlayback
                    : (_duration == null ? null : _playFromScrub),
              ),
              const SizedBox(height: 16),
              Text(
                'Words (tap to hear that word)',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              if (transcript.words.isEmpty)
                const Text(
                  '(no word timings -- nothing heard, or the recognizer '
                  "could not produce per-word timestamps for this audio)",
                )
              else
                for (var i = 0; i < transcript.words.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: OutlinedButton(
                      onPressed: () => _playWordSegment(transcript.words[i]),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(
                        '"${transcript.words[i].text}"  '
                        '[${transcript.words[i].start.inMilliseconds}-'
                        '${transcript.words[i].end.inMilliseconds}ms]',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Scrubs to and plays from an arbitrary point in the loaded recording --
/// independent of any word boundary, so a suspicious timestamp can be
/// checked by ear rather than trusted.
class _ScrubBar extends StatelessWidget {
  const _ScrubBar({
    required this.positionMs,
    required this.duration,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onNudge,
    required this.isPlaying,
    required this.onPlayPause,
  });

  final int positionMs;
  final Duration? duration;
  final ValueChanged<int> onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<int> onNudge;
  final bool isPlaying;
  final VoidCallback? onPlayPause;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxMs = duration?.inMilliseconds ?? 0;
    final clampedMs = positionMs.clamp(0, maxMs == 0 ? 0 : maxMs);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Play from...', style: theme.textTheme.labelLarge),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: clampedMs.toDouble(),
                    max: maxMs == 0 ? 1 : maxMs.toDouble(),
                    onChangeStart: (_) => onDragStart(),
                    onChangeEnd: (_) => onDragEnd(),
                    onChanged: duration == null
                        ? null
                        : (value) => onChanged(value.round()),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    _formatDuration(Duration(milliseconds: clampedMs)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '-50ms',
                      onPressed: duration == null ? null : () => onNudge(-50),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: '+50ms',
                      onPressed: duration == null ? null : () => onNudge(50),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: onPlayPause,
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(isPlaying ? 'Stop' : 'Play from here'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
