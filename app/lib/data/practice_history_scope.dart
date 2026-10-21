// Makes the shared [PracticeHistoryStore] available to the widget tree, the
// same way [PronunciationScope] does for the detector and [PhononTtsScope]
// does for the synthesizer: it owns an open database, and there must be
// exactly one of it.

import 'package:flutter/widgets.dart';

import 'practice_history_store.dart';

class PracticeHistoryScope extends InheritedWidget {
  const PracticeHistoryScope({
    super.key,
    required this.store,
    required super.child,
  });

  final PracticeHistoryStore store;

  static PracticeHistoryStore of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PracticeHistoryScope>();
    assert(scope != null, 'No PracticeHistoryScope found in the widget tree');
    return scope!.store;
  }

  @override
  bool updateShouldNotify(PracticeHistoryScope oldWidget) =>
      store != oldWidget.store;
}
