import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/credits.dart';
import 'package:lingo_node/screens/about_screen.dart';

void main() {
  setUpAll(registerCreditLicenses);

  testWidgets('About credits every project and opens their licences', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

    await tester.scrollUntilVisible(find.text('Credits'), 200);
    expect(find.text('Credits'), findsOneWidget);
    for (final name in [
      'Phonon by Gradium',
      'Vosk by Alpha Cephei',
      'Tatoeba',
    ]) {
      await tester.scrollUntilVisible(find.text(name), 200);
      expect(find.text(name), findsOneWidget);
    }

    await tester.scrollUntilVisible(find.text('Open-source licenses'), 200);
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('every credit has a bundled licence text', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final credit in kCredits) {
      final file = File(credit.licenseAsset);
      expect(file.readAsStringSync().trim(), isNotEmpty, reason: credit.name);
      final folder = '${file.parent.path}/';
      expect(
        pubspec.contains('- ${credit.licenseAsset}') ||
            pubspec.contains('- $folder'),
        isTrue,
        reason: '${credit.licenseAsset} is not declared in pubspec.yaml',
      );
    }
  });
}
