import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/pronunciation/asr_model_scope.dart';
import 'package:lingo_node/pronunciation/asr_model_store.dart';
import 'package:lingo_node/pronunciation/asr_models.dart';
import 'package:lingo_node/screens/speech_model_setup_screen.dart';
import 'package:lingo_node/widgets/speech_model_banner.dart';

void main() {
  late Directory root;
  late AsrModelStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('speech_setup_test');
    store = AsrModelStore(root: () async => root);
    selectedAsrModel.value = kWhisperTiny;
  });

  tearDown(() async {
    store.dispose();
    await root.delete(recursive: true);
  });

  /// Puts every file of [model] on "disk" at its full size.
  Future<void> fill(AsrModel model) async {
    final dir = await store.dirOf(model);
    await dir.create(recursive: true);
    for (final file in model.files) {
      final raf = await File('${dir.path}/${file.name}').open(
        mode: FileMode.write,
      );
      await raf.truncate(file.bytes);
      await raf.close();
    }
    await store.refresh();
  }

  testWidgets('offers every model and can be skipped', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SpeechModelSetupScreen(store: store, onDone: () => done = true),
      ),
    );

    expect(find.text('Download a speech model'), findsOneWidget);
    for (final model in kAsrModels) {
      expect(find.text(model.name), findsOneWidget);
    }
    expect(find.text('Download · 104 MB'), findsOneWidget);

    await tester.tap(find.text(kParakeetV2.name));
    await tester.pump();
    expect(find.text('Download · 661 MB'), findsOneWidget);

    await tester.ensureVisible(find.text('Skip for now'));
    await tester.tap(find.text('Skip for now'));
    expect(done, isTrue);
  });

  testWidgets('says it is ready once the model is downloaded', (tester) async {
    await tester.runAsync(() => fill(kWhisperTiny));
    await tester.pumpWidget(
      MaterialApp(home: SpeechModelSetupScreen(store: store, onDone: () {})),
    );

    expect(find.text("You're all set"), findsOneWidget);
    expect(find.text('Start practising'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
  });

  testWidgets('Home warns until a model is downloaded', (tester) async {
    Widget app() => MaterialApp(
      home: AsrModelScope(
        store: store,
        child: const Scaffold(body: SpeechModelBanner()),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text("Speaking can't be scored yet"), findsOneWidget);

    await tester.runAsync(() => fill(kWhisperTiny));
    await tester.pump();
    expect(find.text("Speaking can't be scored yet"), findsNothing);
  });
}
