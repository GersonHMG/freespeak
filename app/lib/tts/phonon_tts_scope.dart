// Makes the shared, already-loaded [PhononTts] engine available to the
// widget tree.

import 'package:flutter/widgets.dart';

import 'phonon_tts.dart';

class PhononTtsScope extends InheritedWidget {
  const PhononTtsScope({super.key, required this.tts, required super.child});

  final PhononTts tts;

  static PhononTts of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PhononTtsScope>();
    assert(scope != null, 'No PhononTtsScope found in the widget tree');
    return scope!.tts;
  }

  @override
  bool updateShouldNotify(PhononTtsScope oldWidget) => tts != oldWidget.tts;
}
