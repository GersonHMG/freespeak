import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/widgets/grade_buttons.dart';

void main() {
  Widget app({Grade? suggested, ValueChanged<Grade>? onGrade}) => MaterialApp(
    home: Scaffold(
      body: GradeButtons(suggested: suggested, onGrade: onGrade ?? (_) {}),
    ),
  );

  testWidgets('shows Wrong, Partial and Perfect with their icons', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    for (final label in ['Wrong', 'Partial', 'Perfect']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('a tap reports its grade', (tester) async {
    final tapped = <Grade>[];
    await tester.pumpWidget(app(onGrade: tapped.add));

    await tester.tap(find.text('Wrong'));
    await tester.tap(find.text('Partial'));
    await tester.tap(find.text('Perfect'));

    expect(tapped, [Grade.difficult, Grade.medium, Grade.easy]);
  });

  testWidgets('the suggested grade is drawn with white text', (tester) async {
    await tester.pumpWidget(app(suggested: Grade.easy));

    Color? colorOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;
    expect(colorOf('Perfect'), Colors.white);
    expect(colorOf('Wrong'), isNot(Colors.white));
  });

  test('every grade has its own cue', () {
    expect(
      Grade.values.map(GradeButtons.soundFor).toSet(),
      hasLength(Grade.values.length),
    );
  });
}
