// Makes the shared [MispronounceDetector] available to the widget tree, the
// same way [PhononTtsScope] does for the synthesizer and for the same reason:
// it owns a loaded model, and there must be exactly one of it.

import 'package:flutter/widgets.dart';

import 'mispronounce_detector.dart';

class PronunciationScope extends InheritedWidget {
  const PronunciationScope({
    super.key,
    required this.detector,
    required super.child,
  });

  final MispronounceDetector detector;

  static MispronounceDetector of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PronunciationScope>();
    assert(scope != null, 'No PronunciationScope found in the widget tree');
    return scope!.detector;
  }

  @override
  bool updateShouldNotify(PronunciationScope oldWidget) =>
      detector != oldWidget.detector;
}
