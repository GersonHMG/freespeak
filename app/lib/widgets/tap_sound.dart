// A short click cue for buttons that don't already have their own sound
// effect. Shared across the app rather than one AudioPlayer per button, since
// taps never overlap enough to need independent playback state.

import 'package:flutter/foundation.dart';

import 'cue_player.dart';

final _tapPlayer = newCuePlayer(lowLatency: true);

Future<void> playTapSound() async {
  try {
    await playCue(_tapPlayer, 'sounds/ui/tap_sound.ogg');
  } catch (err) {
    debugPrint('[playTapSound] playback failed: $err');
  }
}

final _menuTapPlayer = newCuePlayer(lowLatency: true);

/// The home menus' own tap (assets/sounds/buttons_sound/tap.wav): the Home
/// tab's buttons, the bottom bar, and the More tab's menu rows. Quick taps
/// restart it rather than queue (see playCue).
///
/// The file opens with 40 ms of silence: an idle Android audio output drops
/// the first moments of whatever wakes it, and the click itself is spent
/// within about 10 ms, so without the lead-in it is the click that is lost.
Future<void> playMenuTapSound() async {
  try {
    await playCue(_menuTapPlayer, 'sounds/buttons_sound/tap.wav');
  } catch (err) {
    debugPrint('[playMenuTapSound] playback failed: $err');
  }
}
