import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/widgets/flash_card.dart';

void main() {
  Widget app({required bool showBack, VoidCallback? onTapFront}) => MaterialApp(
    home: Scaffold(
      body: FlashCard(
        showBack: showBack,
        onTapFront: onTapFront,
        front: const Text('front side'),
        back: const Text('back side'),
      ),
    ),
  );

  testWidgets('shows only the front until turned', (tester) async {
    await tester.pumpWidget(app(showBack: false));

    expect(find.text('front side'), findsOneWidget);
    expect(find.text('back side'), findsNothing);
  });

  testWidgets('turning over shows only the back, after the turn', (
    tester,
  ) async {
    await tester.pumpWidget(app(showBack: false));
    await tester.pumpWidget(app(showBack: true));

    // Early in the turn the front is still the face toward the learner.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('front side'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('back side'), findsOneWidget);
    expect(find.text('front side'), findsNothing);
  });

  testWidgets('turns back to the front', (tester) async {
    await tester.pumpWidget(app(showBack: true));
    expect(find.text('back side'), findsOneWidget);

    await tester.pumpWidget(app(showBack: false));
    await tester.pumpAndSettle();
    expect(find.text('front side'), findsOneWidget);
    expect(find.text('back side'), findsNothing);
  });

  testWidgets('tapping the front reports it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(showBack: false, onTapFront: () => taps++));

    await tester.tap(find.text('front side'));
    expect(taps, 1);
  });
}
