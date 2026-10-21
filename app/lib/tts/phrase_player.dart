// Owns playback for one screen: the phrase (at normal speed or slowed), the
// word being spoken, and single-word replay on tap.
//
// It exists because the highlight and the tap-to-hear need the same audio and
// the same AudioPlayer. Two players would talk over each other, and the word
// timings belong with the audio they describe.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'phonon_tts.dart';

class PhrasePlayer extends ChangeNotifier {
  PhrasePlayer(this._tts) {
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _isPlayingSlow = false;
      _spokenWord = -1;
      _endSyllables();
      _safeNotify();
    });

    // Position updates arrive every ~200ms, so the highlight is accurate to
    // about that — enough to follow along, not sample-accurate.
    _player.onPositionChanged.listen((position) {
      if (!_isPlaying && !_isPlayingSlow) return;
      final words = _activeWords;
      final index = words.indexWhere(
        (w) => position >= w.start && position < w.end,
      );
      if (index == _spokenWord) return;
      _spokenWord = index;
      _safeNotify();
    });
  }

  final PhononTts _tts;
  final AudioPlayer _player = AudioPlayer();

  Speech? _speech;
  String? _phrase;
  bool _isGenerating = false;
  bool _isPlaying = false;
  int _spokenWord = -1;
  bool _disposed = false;

  /// The word timings of whichever audio is playing -- the phrase's own, or
  /// the slowed copy's, which are the same words stretched out.
  List<WordTiming> _activeWords = const [];

  bool _isPlayingSlow = false;
  bool _isPreparingSlow = false;

  SyllableAudio? _syllables;
  String? _syllablesText;
  bool _isPlayingSyllables = false;
  bool _isPreparingSyllables = false;
  int _spokenSyllable = -1;

  /// Drives the syllable highlight. The player's own position events come
  /// every ~200ms, which is most of a syllable; the timeline is known exactly,
  /// so a clock started with playback follows it closely enough.
  Timer? _syllableTicker;

  /// Bumped by every [play], [stop] and [reset], so a play still waiting on
  /// synthesis can tell it has been superseded.
  int _request = 0;

  bool get isGenerating => _isGenerating;
  bool get isPlaying => _isPlaying;

  /// Index of the word being spoken, or -1. Indexes the phrase's words in
  /// order, so it lines up with a whitespace split of the same text.
  int get spokenWord => _spokenWord;

  /// Whether the current phrase is ready to replay without synthesizing.
  bool get isReady => _speech != null;

  /// Whether the phrase is playing slowed (see [toggleSlow]).
  bool get isPlayingSlow => _isPlayingSlow;

  /// Whether a tap on the slow button is waiting for the slowed audio.
  bool get isPreparingSlow => _isPreparingSlow;

  /// The first word of the phrase taken apart into syllables, once
  /// [prepareSyllables] has built it.
  SyllableAudio? get syllables => _syllables;

  /// Whether the slowed syllable sequence (or one tapped syllable) is playing.
  bool get isPlayingSyllables => _isPlayingSyllables;

  /// Whether a tap on the syllables button is waiting for them to be built.
  bool get isPreparingSyllables => _isPreparingSyllables;

  /// Index of the syllable being spoken, or -1.
  int get spokenSyllable => _spokenSyllable;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Plays [text], or stops if [text] itself is already playing. Synthesis is
  /// cached by [PhononTts], so replaying a phrase is immediate.
  ///
  /// Another phrase playing is cut off, not stopped instead: the Recall
  /// card's back has a hear button per reference on this one player, and a
  /// tap on the second while the first sounded used to just silence both.
  Future<void> toggle(String text) async {
    if (text.trim().isEmpty) return;

    if ((_isPlaying || _isGenerating) && _phrase == text) {
      await stop();
      return;
    }

    await play(text);
  }

  /// Plays [text] from the start, cutting off whatever was already playing.
  /// Unlike [toggle], never stops instead -- for playing a phrase the moment
  /// it appears, where a stale "is playing" from the last phrase must not
  /// turn the new one into silence.
  Future<void> play(String text) async {
    if (text.trim().isEmpty) return;
    if (_isPlaying || _isPlayingSlow || _isPlayingSyllables) {
      await _player.stop();
    }
    _endSyllables();
    _endSlow();

    // Only the first play of a phrase shows the generating state; afterwards
    // the cache returns before the UI could usefully report anything.
    _isGenerating = _speech == null || _phrase != text;
    _phrase = text;
    _safeNotify();

    final request = ++_request;
    try {
      final speech = await _tts.speakTimed(text);
      // A phrase still generating in the background can take seconds to
      // arrive; if the learner stopped it, moved on, or started recording in
      // the meantime, it must not start talking over whatever came next.
      if (_disposed || request != _request) return;
      _speech = speech;
      _activeWords = speech.words;
      _isGenerating = false;
      _isPlaying = true;
      _safeNotify();
      await _player.play(DeviceFileSource(speech.path));
    } catch (err) {
      debugPrint('[PhrasePlayer] playback failed: $err');
      _isGenerating = false;
      _isPlaying = false;
      _safeNotify();
    }
  }

  /// Plays [text] slowed to [kSlowRate], pitch unchanged, or stops if it is
  /// already playing slowly. The word highlight follows along as it does at
  /// normal speed.
  Future<void> toggleSlow(String text) async {
    if (text.trim().isEmpty) return;
    if (_isPlayingSlow || _isPreparingSlow) {
      await stop();
      return;
    }

    final request = ++_request;
    if (_isPlaying || _isPlayingSyllables) await _player.stop();
    _isPlaying = false;
    _spokenWord = -1;
    _endSyllables();
    _isPreparingSlow = true;
    _safeNotify();

    try {
      final speech = await _tts.speakTimed(text);
      final slow = await _tts.slowSpeech(speech);
      if (_disposed || request != _request) return;
      _speech = speech;
      _phrase = text;
      _activeWords = slow.words;
      _isPreparingSlow = false;
      _isPlayingSlow = true;
      _safeNotify();
      await _player.play(DeviceFileSource(slow.path));
    } catch (err) {
      debugPrint('[PhrasePlayer] slow playback failed: $err');
      _endSlow();
      _safeNotify();
    }
  }

  void _endSlow() {
    _isPlayingSlow = false;
    _isPreparingSlow = false;
  }

  /// Plays a single word of the current phrase, slowed, cut from the audio
  /// already synthesized for it. Silently does nothing until the phrase has been heard
  /// once, since there is nothing to cut from.
  Future<void> playWord(int index) async {
    final speech = _speech;
    if (speech == null) return;

    try {
      final path = await _tts.wordClip(speech, index, slow: true);
      if (path == null) return;
      await _player.stop();
      _isPlaying = false;
      _endSlow();
      _endSyllables();
      _spokenWord = index;
      _safeNotify();
      await _player.play(DeviceFileSource(path));
    } catch (err) {
      debugPrint('[PhrasePlayer] word playback failed: $err');
    }
  }

  /// Builds the syllable audio for [text]'s first word, synthesizing [text]
  /// first if it has not been (a cache hit when the loading screen already
  /// did). Returns null when there is nothing to split.
  Future<SyllableAudio?> prepareSyllables(String text) async {
    if (text.trim().isEmpty) return null;
    if (_syllablesText == text && _syllables != null) return _syllables;
    _syllablesText = text;
    try {
      final speech = await _tts.speakTimed(text);
      final audio = await _tts.syllableAudio(speech, 0);
      // Moved on to another word while this was being built.
      if (_disposed || _syllablesText != text) return null;
      _syllables = audio;
      _safeNotify();
      return audio;
    } catch (err) {
      debugPrint('[PhrasePlayer] syllables failed for "$text": $err');
      return null;
    }
  }

  /// Plays [text]'s first word slowly, a syllable at a time, or stops if the
  /// syllables are already playing.
  Future<void> toggleSyllables(String text) async {
    if (_isPlayingSyllables) {
      await stop();
      return;
    }
    final request = ++_request;
    if (_isPlaying || _isPlayingSlow) await _player.stop();
    _isPlaying = false;
    _endSlow();
    _spokenWord = -1;
    _isPreparingSyllables = _syllables == null || _syllablesText != text;
    _safeNotify();

    final audio = await prepareSyllables(text);
    _isPreparingSyllables = false;
    if (audio == null || _disposed || request != _request) {
      _safeNotify();
      return;
    }
    await _startSyllables(audio.path, [
      for (var i = 0; i < audio.timeline.length; i++) (i, audio.timeline[i]),
    ]);
  }

  /// Plays syllable [index] alone, slowed.
  Future<void> playSyllable(int index) async {
    final audio = _syllables;
    if (audio == null || index < 0 || index >= audio.clipPaths.length) return;
    ++_request;
    await _player.stop();
    _isPlaying = false;
    _endSlow();
    _spokenWord = -1;
    // The clip is the syllable and nothing else, so it is lit throughout.
    final (start, end) = audio.timeline[index];
    await _startSyllables(audio.clipPaths[index], [
      (index, (Duration.zero, end - start)),
    ]);
  }

  Future<void> _startSyllables(
    String path,
    List<(int, (Duration, Duration))> timeline,
  ) async {
    _endSyllables();
    _isPlayingSyllables = true;
    _safeNotify();
    try {
      await _player.play(DeviceFileSource(path));
    } catch (err) {
      debugPrint('[PhrasePlayer] syllable playback failed: $err');
      _endSyllables();
      _safeNotify();
      return;
    }
    if (!_isPlayingSyllables) return; // stopped while starting

    final clock = Stopwatch()..start();
    _syllableTicker = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final now = clock.elapsed;
      var spoken = -1;
      for (final (index, (start, end)) in timeline) {
        if (now >= start && now < end) spoken = index;
      }
      if (spoken == _spokenSyllable) return;
      _spokenSyllable = spoken;
      _safeNotify();
    });
  }

  void _endSyllables() {
    _isPreparingSyllables = false;
    _syllableTicker?.cancel();
    _syllableTicker = null;
    _isPlayingSyllables = false;
    _spokenSyllable = -1;
  }

  Future<void> stop() async {
    _request++;
    await _player.stop();
    _isGenerating = false;
    _isPlaying = false;
    _spokenWord = -1;
    _endSlow();
    _endSyllables();
    _safeNotify();
  }

  /// Called when the screen moves to a different phrase.
  void reset() {
    _request++;
    _isGenerating = false;
    _speech = null;
    _phrase = null;
    _activeWords = const [];
    _spokenWord = -1;
    _endSlow();
    _endSyllables();
    _syllables = null;
    _syllablesText = null;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _endSyllables();
    _player.dispose();
    super.dispose();
  }
}
