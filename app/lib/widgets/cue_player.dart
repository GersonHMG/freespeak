// The player every short UI cue plays through: taps, warnings, grade cues,
// the scoring and celebration cues.
//
// By default every AudioPlayer asks Android for exclusive audio focus
// (AUDIOFOCUS_GAIN) when it starts, and a player that loses focus is paused
// -- silently, with no completion event. So a tap cue starting under the
// reference voice paused the voice (and PhrasePlayer, never told, went on
// thinking it was playing: the next tap on the hear button "stopped" it,
// i.e. did nothing), and a cue that started while another cue had focus
// was paused mid-play, so its next play resumed from that point instead of
// the start -- often right at the end, which is silence.
//
// A cue is a blip that should sound over whatever else is playing, not
// take the speaker away from it, so these players mix with others and never
// request focus at all. ReleaseMode.stop keeps the clip loaded between plays
// (a stop rewinds instead of releasing), so a repeated cue starts at once
// rather than re-preparing the file each time.
//
// [lowLatency] is for the button clicks: tens of milliseconds long, with
// nearly all their sound in the first few. MediaPlayer is slow to start
// such a clip, so on a cold audio output the click is gone before it is
// heard. SoundPool holds the decoded clip in memory and starts it at once.
// It sends no completion event, so its `playing` flag never clears by
// itself; playCue's stop-first is what lets the next play start.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

AudioPlayer newCuePlayer({bool lowLatency = false}) {
  final player = AudioPlayer();
  if (lowLatency) {
    player
        .setPlayerMode(PlayerMode.lowLatency)
        .catchError((Object err) => debugPrint('[cuePlayer] mode: $err'));
  }
  player
      .setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      )
      .catchError((Object err) => debugPrint('[cuePlayer] context: $err'));
  player
      .setReleaseMode(ReleaseMode.stop)
      .catchError((Object err) => debugPrint('[cuePlayer] release: $err'));
  return player;
}

/// Plays [assetPath] on [player] from the start: a cue still sounding from
/// the last tap is cut off and restarted rather than ignored -- calling play
/// on a player that is already playing the same source does nothing.
Future<void> playCue(AudioPlayer player, String assetPath) async {
  await player.stop();
  await player.play(AssetSource(assetPath));
}
