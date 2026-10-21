// Saving and restoring the night-mode choice. It lives with the other
// settings in deck_meta (DeckStore.setting), under `theme_mode`.

import 'package:flutter/material.dart';

import '../decks/deck_store.dart';
import 'lingo_theme.dart';

const String _themeModeKey = 'theme_mode';

/// Reads the saved choice into [lingoThemeMode]; no saved choice follows
/// the system.
Future<void> loadThemeMode(DeckStore store) async {
  final saved = await store.setting(_themeModeKey);
  lingoThemeMode.value =
      ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
}

/// Switches to [mode] at once and remembers it.
Future<void> saveThemeMode(DeckStore store, ThemeMode mode) async {
  lingoThemeMode.value = mode;
  await store.setSetting(_themeModeKey, mode.name);
}
