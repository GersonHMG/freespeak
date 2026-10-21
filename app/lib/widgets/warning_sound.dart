// A cue for a "this loses progress" confirmation, shared across the app the
// same way tap_sound.dart is -- one player, since warnings never overlap
// each other.

import 'package:flutter/foundation.dart';

import 'cue_player.dart';

final _warningPlayer = newCuePlayer();

Future<void> playWarningSound() async {
  try {
    await playCue(_warningPlayer, 'sounds/ui/warning.ogg');
  } catch (err) {
    debugPrint('[playWarningSound] playback failed: $err');
  }
}
