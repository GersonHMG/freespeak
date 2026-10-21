import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_scope.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/deck_store_scope.dart';
import 'package:lingo_node/screens/language_onboarding_screen.dart';
import 'package:lingo_node/screens/practice_mode_screen.dart';
import 'package:lingo_node/screens/settings_screen.dart';
import 'package:lingo_node/theme/lingo_theme.dart';
import 'package:lingo_node/theme/theme_setting.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Serves assets straight from the project's files, so the starter decks
/// load in a widget test the way they do in the app.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File(key).readAsStringSync();

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

void main() {
  setUpAll(sqfliteFfiInit);

  late PracticeHistoryStore history;
  late DeckStore decks;

  setUp(() {
    history = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    decks = DeckStore(history);
  });

  tearDown(() async {
    decks.dispose();
    await history.dispose();
  });

  Widget app(Widget home) => DefaultAssetBundle(
    bundle: _FileBundle(),
    child: PracticeHistoryScope(
      store: history,
      child: DeckStoreScope(
        store: decks,
        child: MaterialApp(home: home),
      ),
    ),
  );

  group('first launch', () {
    testWidgets('lists the languages with cards, then Another language', (
      tester,
    ) async {
      await tester.pumpWidget(app(const LanguageOnboardingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('What language do you speak?'), findsOneWidget);
      for (final name in [
        'Español',
        'Português',
        'Français',
        '中文',
        'हिन्दी',
        'العربية',
      ]) {
        await tester.scrollUntilVisible(find.text(name), 200);
        expect(find.text(name), findsOneWidget);
      }
      // No other named language: those without cards go under
      // "Another language", last.
      for (final name in ['Deutsch', '日本語']) {
        expect(find.text(name), findsNothing);
      }
      await tester.scrollUntilVisible(find.text('Another language'), 200);
      expect(find.text('Another language'), findsOneWidget);
    });

    testWidgets("Another language asks for the learner's own cards", (
      tester,
    ) async {
      await tester.pumpWidget(app(const LanguageOnboardingScreen()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Another language'), 200);
      await tester.tap(find.text('Another language'));
      await tester.pumpAndSettle();

      expect(find.text('Make your own cards'), findsOneWidget);
      expect(find.text('Add my first card'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      expect(await decks.nativeLanguage(), 'und');
      final deck = await decks.deck((await decks.activeDeckId())!);
      expect(deck.name, 'My cards');
      expect(await decks.notes(deck.id), isEmpty);
    });
  });

  testWidgets('Settings shows the language and changes it', (tester) async {
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Not chosen'), findsOneWidget);
    // One target language: no "I'm learning" row to choose it.
    expect(find.text("I'm learning"), findsNothing);

    await tester.tap(find.text('I speak'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(find.text('Français (French)'), findsOneWidget);
    expect(await decks.nativeLanguage(), 'fr');
  });

  testWidgets('Settings switches to night mode and remembers it', (
    tester,
  ) async {
    addTearDown(() => lingoThemeMode.value = ThemeMode.system);
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Night'), findsOneWidget);

    await tester.tap(find.text('Night'));
    await tester.pumpAndSettle();
    expect(lingoThemeMode.value, ThemeMode.dark);
    expect(await decks.setting('theme_mode'), 'dark');

    lingoThemeMode.value = ThemeMode.light;
    await loadThemeMode(decks);
    expect(lingoThemeMode.value, ThemeMode.dark);
  });

  testWidgets('Delete all data needs "delete" typed, then starts over', (
    tester,
  ) async {
    addTearDown(() => lingoThemeMode.value = ThemeMode.system);
    final deckId = await decks.createDeck(name: 'Mine');
    await decks.addNote(
      deckId: deckId,
      nativeText: 'Hola.',
      references: ['Hi.'],
    );
    await decks.setSetting('native_lang', 'es');
    final db = await history.database;
    await db.insert('attempts', {
      'timestamp': 0,
      'sentence': 'Hi.',
      'sentence_length': 1,
      'sentence_score': 90,
      'points': 90,
    });

    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete all data'), 200);
    await tester.tap(find.text('Delete all data'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all data?'), findsOneWidget);

    FilledButton confirm() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete everything'),
    );
    expect(confirm().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'delet');
    await tester.pump();
    expect(confirm().onPressed, isNull);

    // Cancel keeps everything.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await decks.decks(), hasLength(1));

    await tester.tap(find.text('Delete all data'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Delete ');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();

    expect(await decks.decks(), isEmpty);
    expect(await db.query('cards'), isEmpty);
    expect(await db.query('attempts'), isEmpty);
    expect(await decks.nativeLanguage(), isNull);
    // Back to the first-launch question.
    expect(find.byType(LanguageOnboardingScreen), findsOneWidget);
  });

  testWidgets('More holds My decks and Settings', (tester) async {
    await tester.pumpWidget(app(const PracticeModeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('More'), findsOneWidget);
    expect(find.text('My decks'), findsOneWidget);
    expect(find.text('Add a card'), findsNothing);
    // One entry for missed words and sentences.
    expect(find.text('Revisit mispronunciations'), findsOneWidget);
    expect(find.text('Revisit words'), findsNothing);
    expect(find.text('Revisit sentences'), findsNothing);

    await tester.scrollUntilVisible(find.text('Settings'), 200);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('I speak'), findsOneWidget);
  });

  testWidgets('the language list is flags and names only', (tester) async {
    await tester.pumpWidget(app(const LanguageOnboardingScreen()));
    await tester.pumpAndSettle();

    expect(find.text('🇪🇸'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    // No headings or descriptions around the languages.
    expect(find.text('READY-MADE CARDS'), findsNothing);
    expect(find.textContaining('starter deck'), findsNothing);
  });
}
