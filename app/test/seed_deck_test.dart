import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/practice_history_store.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/deck_store.dart';
import 'package:lingo_node/decks/languages.dart';
import 'package:lingo_node/decks/seed_deck.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _json = '''
{
  "name": "Spanish starter",
  "source": "tatoeba",
  "native_lang": "es",
  "target_lang": "en",
  "license": "CC BY 2.0 FR",
  "attribution": "Sentences from Tatoeba",
  "notes": [
    {"source_ref": "1", "native": "Tengo hambre.",
     "references": ["I'm hungry.", "I am hungry."], "reference_refs": ["10", "11"]},
    {"source_ref": "2", "native": "¿Dónde está la estación?",
     "references": ["Where is the station?"], "reference_refs": ["12"]}
  ]
}
''';

const _asset = 'assets/decks/test_es_en.json';

/// Serves [_json] as [_asset], and nothing else.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.json);

  final String json;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    expect(key, _asset);
    return json;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

/// Serves assets straight from the project's files.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File(key).readAsStringSync();

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

SeedDeck _readDeck(String asset) => SeedDeck.fromJson(
  jsonDecode(File(asset).readAsStringSync()) as Map<String, dynamic>,
);

const _deckNames = [
  'Common phrases',
  'Travel & survival',
  'Food & ordering',
  'Work & meetings',
  'Phrasal verbs',
  'Idioms & fillers',
];

void main() {
  setUpAll(sqfliteFfiInit);

  late PracticeHistoryStore history;
  late DeckStore decks;

  setUp(() {
    history = PracticeHistoryStore(
      databaseFactory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    decks = DeckStore(history);
  });

  tearDown(() async {
    decks.dispose();
    await history.dispose();
  });

  test('SeedDeck.fromJson reads the deck and its notes', () {
    final deck = SeedDeck.fromJson(jsonDecode(_json) as Map<String, dynamic>);
    expect(deck.name, 'Spanish starter');
    expect(deck.source, DeckSource.tatoeba);
    expect(deck.attribution, 'Sentences from Tatoeba');
    expect(deck.notes, hasLength(2));
    expect(deck.notes.first.references, ["I'm hungry.", 'I am hungry.']);
    expect(deck.notes.first.sourceRef, '1');
    expect(deck.notes.first.kind, NoteKind.sentence);
  });

  test('importSeedDeck imports the deck with every note and card', () async {
    final deckId = await importSeedDeck(decks, asset: _asset, bundle: _Bundle(_json));

    expect(deckId, isNotNull);
    final deck = (await decks.decks()).single;
    expect(deck.source, DeckSource.tatoeba);
    final notes = await decks.notes(deckId!);
    expect(notes.map((n) => n.nativeText), [
      'Tengo hambre.',
      '¿Dónde está la estación?',
    ]);
    expect(notes.first.primaryReference, "I'm hungry.");

    final db = await history.database;
    expect(await db.query('cards'), hasLength(2)); // one Recall card each
  });

  test('importSeedDeck runs once, even after the deck is deleted', () async {
    final deckId = await importSeedDeck(decks, asset: _asset, bundle: _Bundle(_json));
    expect(await importSeedDeck(decks, asset: _asset, bundle: _Bundle(_json)), isNull);

    final db = await history.database;
    await db.delete('decks', where: 'id = ?', whereArgs: [deckId]);

    expect(await importSeedDeck(decks, asset: _asset, bundle: _Bundle(_json)), isNull);
    expect(await decks.decks(), isEmpty);
  });

  test('a bad note rolls back the whole import', () async {
    const deck = SeedDeck(
      name: 'Broken',
      notes: [
        SeedNote(nativeText: 'Hola', references: ['Hello']),
        SeedNote(nativeText: 'Adiós', references: []),
      ],
    );

    await expectLater(
      decks.importDeckOnce('broken', deck),
      throwsArgumentError,
    );

    expect(await decks.decks(), isEmpty);
    final db = await history.database;
    expect(await db.query('notes'), isEmpty);
    expect(await db.query('deck_meta'), isEmpty);
  });

  test('every known language has the six everyday decks', () {
    expect(kStarterDeckAssets.keys, kKnownNativeLangs);
    for (final MapEntry(key: code, value: assets)
        in kStarterDeckAssets.entries) {
      expect([for (final asset in assets) _readDeck(asset).name], _deckNames);
      for (final asset in assets) {
        final deck = _readDeck(asset);
        expect(deck.nativeLang, code, reason: asset);
        expect(deck.targetLang, 'en', reason: asset);
        expect(deck.source, DeckSource.starter, reason: asset);
        expect(deck.notes, hasLength(120), reason: asset);
        for (final note in deck.notes) {
          expect(note.nativeText.trim(), isNotEmpty, reason: asset);
          expect(note.references, hasLength(1), reason: asset);
          expect(note.sourceRef, isNotNull, reason: asset);
        }
      }
    }
  });

  test('a deck has the same English in every language, row for row', () {
    List<String> english(String asset) => [
      for (final note in _readDeck(asset).notes) note.references.single,
    ];

    final spanish = [for (final a in kStarterDeckAssets['es']!) english(a)];
    for (final assets in kStarterDeckAssets.values) {
      for (final (i, asset) in assets.indexed) {
        expect(english(asset), spanish[i], reason: asset);
      }
    }
    final all = spanish.expand((e) => e).map((s) => s.toLowerCase());
    expect(all.toSet(), hasLength(6 * 120)); // no sentence twice
  });

  group('chooseNativeLanguage', () {
    /// Serves the real starter deck files, as the app's bundle would.
    final files = _FileBundle();

    test('imports the six starter decks and studies the first', () async {
      final deckId = await chooseNativeLanguage(decks, 'fr', bundle: files);

      final all = await decks.decks();
      expect(all.map((d) => d.name), _deckNames);
      expect(all.every((d) => d.nativeLang == 'fr'), isTrue);
      final deck = await decks.deck(deckId);
      expect(deck.name, 'Common phrases');
      expect(await decks.notes(deckId), hasLength(120));
      expect(await decks.nativeLanguage(), 'fr');
      expect(await decks.activeDeckId(), deckId);
    });

    test('a language without decks gets an empty deck of its own', () async {
      final deckId = await chooseNativeLanguage(decks, 'de', bundle: files);

      final deck = await decks.deck(deckId);
      expect(deck.nativeLang, 'de');
      expect(deck.name, 'My cards');
      expect(await decks.notes(deckId), isEmpty);
      expect(await decks.activeDeckId(), deckId);
    });

    test('switching back reuses the decks already there', () async {
      final spanish = await chooseNativeLanguage(decks, 'es', bundle: files);
      await chooseNativeLanguage(decks, 'pt', bundle: files);

      expect(await chooseNativeLanguage(decks, 'es', bundle: files), spanish);
      expect(await decks.decks(), hasLength(12));
      expect(await decks.activeDeckId(), spanish);
    });

    test('a deleted starter deck stays deleted', () async {
      final first = await chooseNativeLanguage(decks, 'hi', bundle: files);
      final db = await history.database;
      await db.delete('decks', where: 'id = ?', whereArgs: [first]);

      final next = await chooseNativeLanguage(decks, 'hi', bundle: files);

      expect((await decks.deck(next)).name, 'Travel & survival');
      expect(await decks.decks(), hasLength(5));
    });

    test('an own deck in the language gets the starter decks too', () async {
      final own = await decks.createDeck(
        name: 'My cards',
        nativeLang: 'ar',
        targetLang: 'en',
      );

      final deckId = await chooseNativeLanguage(decks, 'ar', bundle: files);

      expect(deckId, isNot(own));
      expect((await decks.deck(deckId)).name, 'Common phrases');
      expect(await decks.decks(), hasLength(7));
    });
  });
}
