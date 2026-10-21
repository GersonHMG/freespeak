// Makes the shared [DeckStore] available to the widget tree, the same way
// [PracticeHistoryScope] does for the store whose database it borrows.

import 'package:flutter/widgets.dart';

import 'deck_store.dart';

class DeckStoreScope extends InheritedWidget {
  const DeckStoreScope({super.key, required this.store, required super.child});

  final DeckStore store;

  static DeckStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DeckStoreScope>();
    assert(scope != null, 'No DeckStoreScope found in the widget tree');
    return scope!.store;
  }

  @override
  bool updateShouldNotify(DeckStoreScope oldWidget) => store != oldWidget.store;
}
