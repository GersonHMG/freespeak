// Practice sentences, drawn from the bundled sentence dataset.
//
// The React Native app streamed these out of the same CSV; this is the
// equivalent for Flutter -- read the asset once, on app start, and hand back
// a session's worth of sentences rather than shipping a fixed hand-picked
// list.
//
// A session is a difficulty ramp, not a flat random sample: a fixed number of
// sentences per [SentenceDifficulty] tier, easy first and hard last, each
// tier's members chosen at random from everything the dataset offers at that
// tier. [difficultyOf] (lib/scoring/difficulty.dart) is the same classifier
// [rateSentence] grades an attempt against, so a sentence that lands in the
// "easy" slice here scores as easy later -- the ramp and the scoring agree by
// construction, not by coincidence.

import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../scoring/difficulty.dart';

const String _assetPath = 'assets/data_en.csv';

/// How many sentences a practice session draws from each difficulty tier, in
/// the order they should appear: easy sentences first, working up to hard.
/// [SentenceDifficulty.values] (not this map's own key order) decides that
/// order, so a caller's map can list its entries in any order without
/// changing the ramp.
const Map<SentenceDifficulty, int> kDefaultTierCounts = {
  SentenceDifficulty.easy: 2,
  SentenceDifficulty.medium: 3,
};

/// Loads [_assetPath] and returns a session's sentences: [tierCounts]
/// sentences from each difficulty tier, chosen at random within the tier,
/// ordered easy-to-hard regardless of [tierCounts]'s own key order.
///
/// The file is a single-column CSV (a header row, then one sentence per
/// line); some sentences are wrapped in double quotes because they contain a
/// comma, so those are unwrapped rather than doing a full CSV parse a single
/// column has no real use for. [random] is a constructor argument, not a
/// hidden global, so a test can pass a seeded one and get a deterministic
/// sample.
///
/// A tier with fewer sentences available than [tierCounts] asks for
/// contributes everything it has rather than throwing -- the bundled dataset
/// is large enough that this is not expected to happen, but a short tier is a
/// smaller session, not a crash.
Future<List<String>> loadSampleSentences({
  Map<SentenceDifficulty, int> tierCounts = kDefaultTierCounts,
  Random? random,
}) async {
  final raw = await rootBundle.loadString(_assetPath);
  final sentences = _parseSentences(raw);
  if (sentences.isEmpty) return const [];

  final byTier = <SentenceDifficulty, List<String>>{
    for (final tier in SentenceDifficulty.values) tier: <String>[],
  };
  for (final sentence in sentences) {
    byTier[difficultyOf(sentence)]!.add(sentence);
  }

  final rng = random ?? Random();
  final result = <String>[];
  for (final tier in SentenceDifficulty.values) {
    final count = tierCounts[tier] ?? 0;
    if (count <= 0) continue;
    final pool = byTier[tier]!..shuffle(rng);
    result.addAll(pool.take(count));
  }
  return result;
}

List<String> _parseSentences(String csv) {
  final lines = csv.split('\n');
  return [
    for (final line in lines.skip(1)) // skip the "sentence" header
      if (_unquote(line.trim()) case final sentence when sentence.isNotEmpty)
        sentence,
  ];
}

String _unquote(String line) {
  if (line.length >= 2 && line.startsWith('"') && line.endsWith('"')) {
    return line.substring(1, line.length - 1);
  }
  return line;
}

/// Used only when [loadSampleSentences] fails outright (a missing or
/// unreadable asset) -- enough to keep the practice screen usable rather than
/// stranding the learner on the loader.
const List<String> fallbackSampleSentences = [
  'The quick brown fox jumps over the lazy dog',
  "It's all over between us.",
  'A small forest brook flowed between the moss-covered trees.',
];
