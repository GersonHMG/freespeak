// Plays back the learner's own recording — the whole attempt, or (via
// cutting) just one word of it.
//
// The counterpart to [PhrasePlayer], which plays the reference (synthesized)
// audio. This exists because "hear yourself" needs its own [AudioPlayer] and
// its own idea of "is something playing" -- sharing PhrasePlayer's would mean
// the reference and the learner's attempt could talk over each other, and
// stopping one to start the other would read as a bug rather than the two
// being deliberately independent.
//
// [playWhole] needs nothing but the recording path -- it plays the file
// exactly as recorded, no decoding or cutting. [playWord] is the one that
// does the work: clips are cut on first tap and kept only for the attempt
// they came from -- [attach] clears the cache whenever a new
// [PronunciationResult] replaces the old one, since a stale clip would be
// audio from a different recording entirely. They live in the OS temp
// directory alongside the recording itself and are never explicitly deleted
// -- same lifetime as [PronunciationRecorder] gives `attempt.wav`.
//
// [position]/[duration] and [togglePlayback] exist for the scrub bar on the
// feedback screen: scrubbing needs a live position, and its play/pause button
// needs pausing and resuming the whole recording, not just restarting it from
// the top every tap. [_wholeLoaded] is what tells [togglePlayback] which of
// those three it's doing -- it is deliberately narrower than "something is
// loaded", since a per-word clip played via [playWord] is loaded in the same
// sense but is not the whole recording [togglePlayback] resumes.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'pronunciation_result.dart';
import 'wav_pcm.dart';

class UserAttemptPlayer extends ChangeNotifier {
  UserAttemptPlayer() {
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      _safeNotify();
    });
    _player.onPositionChanged.listen((position) {
      _position = position;
      _safeNotify();
    });
    _player.onDurationChanged.listen((duration) {
      _duration = duration;
      _safeNotify();
    });
  }

  final AudioPlayer _player = AudioPlayer();

  PronunciationResult? _result;
  final Map<int, String> _clips = <int, String>{};

  bool _isPlaying = false;
  bool _disposed = false;

  // Whether the source currently loaded into [_player] is the whole
  // recording, as opposed to a word clip or nothing -- see file header.
  bool _wholeLoaded = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;

  /// Whether there is a recording [togglePlayback]/[playWhole] can play --
  /// what a scrub bar should check before showing itself at all.
  bool get hasAttempt => _result?.recordingPath != null;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Points this player at the attempt to play clips from. Call with `null`
  /// when there is no scored attempt yet (a fresh phrase, a skip) -- clips
  /// from a previous recording must not survive to be played over a new one.
  void attach(PronunciationResult? result) {
    _result = result;
    _clips.clear();
    _wholeLoaded = false;
    _position = Duration.zero;
    _duration = Duration.zero;
  }

  /// Plays what the learner said for word [wordOrdinal] of the current
  /// attempt. Returns false, and plays nothing, when there is no clip for
  /// it -- the word was skipped, there is no attempt yet, or the recognizer's
  /// word timing could not be trusted for this recording (see
  /// [ScoredWord.hasSpokenClip]). The caller is expected to tell the learner
  /// why, since silence alone reads as a bug rather than "you didn't say
  /// that."
  Future<bool> playWord(int wordOrdinal) async {
    final result = _result;
    final recordingPath = result?.recordingPath;
    if (result == null || recordingPath == null) return false;
    if (wordOrdinal < 0 || wordOrdinal >= result.words.length) return false;

    final word = result.words[wordOrdinal];
    if (!word.hasSpokenClip) return false;

    try {
      final path = await _clipFor(wordOrdinal, word, recordingPath);
      await _player.stop();
      // A clip, not the whole recording -- see file header.
      _wholeLoaded = false;
      _isPlaying = true;
      _safeNotify();
      await _player.play(DeviceFileSource(path));
      return true;
    } catch (err) {
      debugPrint('[UserAttemptPlayer] playback failed: $err');
      _isPlaying = false;
      _safeNotify();
      return false;
    }
  }

  /// Plays the whole recording from the top, unedited — every word the
  /// learner said, in the order and timing they said it, not the per-word
  /// cuts [playWord] makes. Returns false when there is nothing to play (no
  /// attempt yet).
  Future<bool> playWhole() async {
    final recordingPath = _result?.recordingPath;
    if (recordingPath == null) return false;

    try {
      await _player.stop();
      _wholeLoaded = true;
      _isPlaying = true;
      _position = Duration.zero;
      _safeNotify();
      await _player.play(DeviceFileSource(recordingPath));
      return true;
    } catch (err) {
      debugPrint('[UserAttemptPlayer] whole-recording playback failed: $err');
      _isPlaying = false;
      _safeNotify();
      return false;
    }
  }

  /// The scrub bar's single button: pauses if playing, resumes if paused
  /// mid-way through the whole recording, and otherwise starts it from the
  /// top via [playWhole]. Returns false only in that last case, and only when
  /// there is nothing to play at all -- pause and resume cannot fail this way.
  Future<bool> togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
      _isPlaying = false;
      _safeNotify();
      return true;
    }
    if (_wholeLoaded) {
      await _player.resume();
      _isPlaying = true;
      _safeNotify();
      return true;
    }
    return playWhole();
  }

  /// Jumps the whole recording to [position]. No-op when nothing is loaded --
  /// there is nothing meaningful to seek within a stopped player, and calling
  /// it anyway risks starting playback the caller didn't ask for.
  Future<void> seek(Duration position) async {
    if (!_wholeLoaded) return;
    await _player.seek(position);
    _position = position;
    _safeNotify();
  }

  Future<String> _clipFor(
    int wordOrdinal,
    ScoredWord word,
    String recordingPath,
  ) async {
    final cached = _clips[wordOrdinal];
    if (cached != null) return cached;

    final directory = await getTemporaryDirectory();
    final path = await cutWavClip(
      sourcePath: recordingPath,
      start: word.spokenStart!,
      end: word.spokenEnd!,
      outPath: '${directory.path}/attempt_word_$wordOrdinal.wav',
    );
    _clips[wordOrdinal] = path;
    return path;
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    super.dispose();
  }
}
