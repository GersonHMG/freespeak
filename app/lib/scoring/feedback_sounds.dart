// Audio cues for scoring milestones: a well-scored sentence, finishing a
// whole session, and reaching the daily goal.
//
// Its own [AudioPlayer], separate from [PhrasePlayer] (the reference voice)
// and [UserAttemptPlayer] (the learner's own recording) -- the same reasoning
// both of those already follow: a cue that shared either player's channel
// could cut off speech that is still playing, or be cut off by it.
//
// Each screen that wants a cue owns its own instance -- [SessionScreen]'s
// dies with it when [SessionCompleteScreen] replaces it, so the completion
// cue is never reached through a player that has already been disposed.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../widgets/cue_player.dart';
import 'score_band.dart';

class FeedbackSoundPlayer {
  final AudioPlayer _player = newCuePlayer();

  // Separate players from the one above, not just separate calls -- the
  // finish cue, the counting cue, and the goal-reached cue can all be
  // sounding around the same moment (see SessionCompleteScreen, which plays
  // the finish and goal-reached cues right as the counting cue is tailing
  // off), and sharing one AudioPlayer would mean starting one cue cuts the
  // others off mid-play.
  final AudioPlayer _secondaryPlayer = newCuePlayer();
  final AudioPlayer _tertiaryPlayer = newCuePlayer();

  /// Plays the cue for [band], if it has one. Only [ScoreBand.green] does
  /// today -- a miss here is silence, not a fallback sound, so a middling
  /// attempt is not mistaken for a good one.
  Future<void> playFor(ScoreBand band) async {
    if (band != ScoreBand.green) return;
    await _play(_player, 'sounds/correct.mp3');
  }

  /// Plays the cue for finishing a whole session, unconditionally --
  /// reaching the end of the phrase set is worth marking regardless of how
  /// well it went, unlike the per-sentence cue above.
  Future<void> playSessionFinish() =>
      _play(_player, 'sounds/session_finish.ogg');

  /// Plays while a number is animating upward -- SessionCompleteScreen's
  /// points count and accuracy ring.
  Future<void> playCounting() => _play(_secondaryPlayer, 'sounds/ui/count.ogg');

  /// Plays once, when a session's finish pushes the day's total at or past
  /// the daily goal.
  Future<void> playGoalReached() =>
      _play(_tertiaryPlayer, 'sounds/trumpets_success.mp3');

  /// Plays once, when a Recall session's last card is done, under its
  /// confetti.
  Future<void> playCelebration() =>
      _play(_tertiaryPlayer, 'sounds/celebration_sound.wav');

  Future<void> _play(AudioPlayer player, String assetPath) async {
    try {
      await playCue(player, assetPath);
    } catch (err) {
      debugPrint('[FeedbackSoundPlayer] playback failed: $err');
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _secondaryPlayer.dispose();
    await _tertiaryPlayer.dispose();
  }
}
