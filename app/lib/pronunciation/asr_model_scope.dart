// Makes the shared [AsrModelStore] available to Settings, the same way
// [PronunciationScope] does for the detector: downloads outlive the screen
// that started them, so there must be exactly one store.

import 'package:flutter/widgets.dart';

import 'asr_model_store.dart';

class AsrModelScope extends InheritedWidget {
  const AsrModelScope({super.key, required this.store, required super.child});

  final AsrModelStore store;

  /// The store, or null outside the app's scopes (a screen under test).
  static AsrModelStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AsrModelScope>()?.store;

  @override
  bool updateShouldNotify(AsrModelScope oldWidget) => store != oldWidget.store;
}
