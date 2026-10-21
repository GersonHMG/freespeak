// Recall's own learner settings, saved with the others in deck_meta
// (DeckStore.setting), the same way theme_setting.dart keeps night mode.

import 'package:flutter/foundation.dart';

import 'deck_store.dart';

const String _speakOnFlipKey = 'speak_on_flip';

/// Whether a Recall card says its main reference aloud once it has turned
/// over. On by default; off leaves the hear buttons as the only way to
/// hear it.
final ValueNotifier<bool> speakOnFlip = ValueNotifier(true);

/// Reads the saved choices; none saved keeps the defaults.
Future<void> loadRecallSettings(DeckStore store) async {
  speakOnFlip.value = await store.setting(_speakOnFlipKey) != 'false';
}

/// Switches speaking on flip at once and remembers it.
Future<void> saveSpeakOnFlip(DeckStore store, bool value) async {
  speakOnFlip.value = value;
  await store.setSetting(_speakOnFlipKey, '$value');
}
