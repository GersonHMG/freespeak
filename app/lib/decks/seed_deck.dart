// The bundled starter decks: six everyday-use decks (common phrases, travel,
// food, work, phrasal verbs, idioms), 120 English sentences each, with their
// translation into every native language in [kStarterDeckAssets].
// tool/build_everyday_decks.py builds each asset from
// assets/sentences/everyday_<deck>_en.csv and everyday_<deck>_<code>.tsv.
// A language's decks are imported when the learner says they speak it (see
// [chooseNativeLanguage]), each once.
//
// The same format also carries decks built from Tatoeba
// (tool/build_seed_deck.py), whose [SeedDeck.attribution] is the credit
// line their CC BY licence requires.

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'deck_models.dart';
import 'deck_store.dart';
import 'languages.dart';

/// The everyday-use decks, in the order a language's decks are imported and
/// listed (tool/build_everyday_decks.py's DECKS). The first is the one Home
/// studies after the language is chosen.
const List<String> _kEverydayDecks = [
  'common_phrases',
  'travel_survival',
  'food_ordering',
  'work_meetings',
  'phrasal_verbs',
  'idioms_fillers',
];

/// The starter decks for each native language that has them, every one
/// translated into each of [kKnownNativeLangs]; English is the target of
/// them all.
final Map<String, List<String>> kStarterDeckAssets = {
  for (final code in kKnownNativeLangs)
    code: [
      for (final deck in _kEverydayDecks)
        'assets/decks/everyday_${deck}_${code}_en.json',
    ],
};

class SeedNote {
  const SeedNote({
    required this.nativeText,
    required this.references,
    this.kind = NoteKind.sentence,
    this.sourceRef,
  });

  final String nativeText;

  /// Primary first.
  final List<String> references;
  final NoteKind kind;
  final String? sourceRef;
}

/// A deck as the seed JSON describes it, before it has ids.
class SeedDeck {
  const SeedDeck({
    required this.name,
    required this.notes,
    this.source = DeckSource.starter,
    this.nativeLang = kDefaultNativeLang,
    this.targetLang = kDefaultTargetLang,
    this.newPerDay = 10,
    this.attribution,
  });

  final String name;
  final DeckSource source;
  final String nativeLang;
  final String targetLang;
  final int newPerDay;
  final String? attribution;
  final List<SeedNote> notes;

  factory SeedDeck.fromJson(Map<String, dynamic> json) => SeedDeck(
    name: json['name'] as String,
    source: DeckSource.values.byName(json['source'] as String),
    nativeLang: json['native_lang'] as String,
    targetLang: json['target_lang'] as String,
    attribution: json['attribution'] as String?,
    notes: [
      for (final note in json['notes'] as List<dynamic>)
        SeedNote(
          nativeText: note['native'] as String,
          references: [
            for (final ref in note['references'] as List<dynamic>)
              ref as String,
          ],
          sourceRef: note['source_ref'] as String?,
        ),
    ],
  );
}

/// Imports the bundled deck at [asset] into [store] unless it was imported
/// before. Returns the new deck's id, or null when there was nothing to do.
Future<int?> importSeedDeck(
  DeckStore store, {
  required String asset,
  AssetBundle? bundle,
}) async {
  final json = await (bundle ?? rootBundle).loadString(asset);
  final deck = SeedDeck.fromJson(jsonDecode(json) as Map<String, dynamic>);
  return store.importDeckOnce(asset, deck);
}

/// Records that the learner speaks [code] and makes a deck in it the one
/// Home studies, returning its id:
///
/// * a deck already in that language, if there is one, bundled ones first;
/// * otherwise -- no starter decks, or ones the learner imported and then
///   deleted -- a new, empty "My cards" deck for their own cards.
///
/// The language's starter decks are imported first, each unless it was
/// imported before, so a deck bundled since the language was last chosen
/// arrives too; with none in the language yet, its first one is the pick.
Future<int> chooseNativeLanguage(
  DeckStore store,
  String code, {
  AssetBundle? bundle,
}) async {
  for (final asset in kStarterDeckAssets[code] ?? const <String>[]) {
    await importSeedDeck(store, asset: asset, bundle: bundle);
  }
  var deckId = await store.deckForLanguage(code);
  deckId ??= await store.createDeck(
    name: 'My cards',
    nativeLang: code,
    targetLang: kDefaultTargetLang,
  );
  await store.setSetting('native_lang', code);
  await store.setSetting('active_deck', '$deckId');
  return deckId;
}
