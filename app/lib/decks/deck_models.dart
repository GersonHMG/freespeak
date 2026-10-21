// Plain value types for the flashcard tables (deck_schema.dart). Enums are
// stored by [Enum.name], so renaming a value is a schema change.

/// Where a deck came from.
enum DeckSource {
  /// Made by the learner.
  user,

  /// A bundled starter deck (seed_deck.dart's kStarterDeckAssets).
  starter,

  /// Built from Tatoeba by tool/build_seed_deck.py.
  tatoeba,
}

/// Whether a note's text is a single word or a sentence. Only the scorer's
/// presentation cares; scheduling treats both alike.
enum NoteKind { word, sentence }

/// How a card is studied, stored in `cards.mode`. Recall is the only mode:
/// a Pronounce mode existed briefly and was removed (schema v6 deletes its
/// cards); pronunciation practice is the session and Practice screens.
enum CardMode {
  /// Spanish prompt, the learner types or says the English.
  recall,
}

/// Where a card is in its life.
enum CardState {
  /// Never reviewed.
  newCard,

  /// Graded Difficult on its first look and waiting to be shown again in the
  /// same session (interval 0).
  learning,

  /// On a day-based interval.
  review,
}

/// Which cards a custom session draws.
enum CustomPick {
  /// A random mix of the whole deck.
  random,

  /// Cards the learner wrote (no `source_ref`), newest first.
  added,

  /// Cards whose last grade was Wrong or Partial.
  missed,
}

/// The learner's self-grade -- the three buttons after every card.
enum Grade { difficult, medium, easy }

/// How a Recall answer was given.
enum AnswerInput { typed, spoken }

// CardState.newCard is stored as 'new' -- `new` is a Dart keyword, so the
// enum value cannot carry the name the schema uses.
String cardStateToDb(CardState state) =>
    state == CardState.newCard ? 'new' : state.name;

CardState cardStateFromDb(String value) =>
    value == 'new' ? CardState.newCard : CardState.values.byName(value);

class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.nativeLang,
    required this.targetLang,
    required this.source,
    required this.newPerDay,
    required this.createdAt,
    this.icon,
    this.color,
  });

  final int id;
  final String name;

  /// The icon and tile colour the learner picked in the deck's settings,
  /// by name (lib/widgets/deck_look.dart); null until they do, and the
  /// default shows. An emoji left from before v10 reads as the default.
  final String? icon;
  final String? color;

  /// ISO 639-1 code of the prompt side, `es` for now.
  final String nativeLang;

  /// ISO 639-1 code of the answer side, `en`.
  final String targetLang;
  final DeckSource source;

  /// How many new cards the daily queue introduces per day.
  final int newPerDay;
  final DateTime createdAt;

  /// Whether the learner may rename the deck, delete it, and add, edit or
  /// delete its cards: only decks they made. The bundled starter decks (and
  /// Tatoeba ones) are read-only -- their cards can still be studied, and
  /// their daily new-card count changed.
  bool get isEditable => source == DeckSource.user;

  factory Deck.fromRow(Map<String, Object?> row) => Deck(
    id: row['id']! as int,
    name: row['name']! as String,
    nativeLang: row['native_lang']! as String,
    targetLang: row['target_lang']! as String,
    source: DeckSource.values.byName(row['source']! as String),
    newPerDay: row['new_per_day']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    icon: row['icon'] as String?,
    color: row['color'] as String?,
  );
}

class Note {
  const Note({
    required this.id,
    required this.deckId,
    required this.nativeText,
    required this.kind,
    required this.references,
    this.ownReferences = const [],
    this.sourceRef,
  });

  final int id;
  final int deckId;

  /// The Spanish prompt.
  final String nativeText;
  final NoteKind kind;

  /// Reference English translations, primary first. Never empty. Examples
  /// to compare with, not an answer key -- a translation can be right in
  /// many wordings.
  final List<String> references;

  /// Ways to say it the learner saved while studying, oldest first -- on
  /// top of [references], which stay the deck's own. Theirs to remove, on
  /// any deck.
  final List<String> ownReferences;

  /// The Tatoeba sentence id for seed notes; null for the learner's own.
  final String? sourceRef;

  /// The reference Recall lists first.
  String get primaryReference => references.first;

  /// The deck's references, then the learner's own.
  List<String> get allReferences => [...references, ...ownReferences];
}

/// [text] reduced to what makes two wordings the same answer: case,
/// punctuation and spacing ignored, apostrophes kept ("I'm" is not "Im").
String answerKey(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"[^\p{L}\p{N}\s']", unicode: true), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A card's schedule -- the part of a `cards` row the scheduler reads and
/// writes. Immutable; the scheduler returns a new one.
class CardSchedule {
  const CardSchedule({
    required this.state,
    required this.dueAt,
    required this.intervalDays,
    required this.ease,
    required this.reps,
    required this.lapses,
  });

  /// A card that has never been reviewed.
  static const CardSchedule fresh = CardSchedule(
    state: CardState.newCard,
    dueAt: null,
    intervalDays: 0,
    ease: 2.5,
    reps: 0,
    lapses: 0,
  );

  final CardState state;

  /// When the card is next shown; null while [CardState.newCard].
  final DateTime? dueAt;

  /// I, in whole days. 0 while new or [CardState.learning].
  final double intervalDays;

  /// E, the interval multiplier. Starts at 2.5, never below 1.3.
  final double ease;

  /// Reviews so far.
  final int reps;

  /// Difficult taps on a [CardState.review] card.
  final int lapses;

  factory CardSchedule.fromRow(Map<String, Object?> row) => CardSchedule(
    state: cardStateFromDb(row['state']! as String),
    dueAt: row['due_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['due_at']! as int),
    intervalDays: (row['interval_days']! as num).toDouble(),
    ease: (row['ease']! as num).toDouble(),
    reps: row['reps']! as int,
    lapses: row['lapses']! as int,
  );

  Map<String, Object?> toRow() => {
    'state': cardStateToDb(state),
    'due_at': dueAt?.millisecondsSinceEpoch,
    'interval_days': intervalDays,
    'ease': ease,
    'reps': reps,
    'lapses': lapses,
  };
}

/// A deck with the numbers a deck list shows beside it.
class DeckSummary {
  const DeckSummary({
    required this.deck,
    required this.cardCount,
    required this.dueCount,
    this.shownCount = 0,
    this.perfectCount = 0,
  });

  final Deck deck;

  /// Every card in the deck.
  final int cardCount;

  /// Today's queue for it -- what a Recall sitting would hold now.
  final int dueCount;

  /// Cards graded at least once.
  final int shownCount;

  /// Of [shownCount], the cards whose most recent grade is Perfect.
  final int perfectCount;

  /// [perfectCount] as a whole percentage of [shownCount]; null before any
  /// card has been shown, when there is nothing to measure yet.
  int? get progressPercent =>
      shownCount == 0 ? null : (100 * perfectCount / shownCount).round();
}

/// A card the learner has graded at least once, with how it went -- a row
/// of the Progress tab's "Cards practised" list.
class PractisedCard {
  const PractisedCard({
    required this.cardId,
    required this.nativeText,
    required this.reference,
    required this.grades,
    required this.lastGrade,
    required this.lastPractised,
  });

  final int cardId;

  /// The prompt, in the learner's language.
  final String nativeText;

  /// The primary reference translation.
  final String reference;

  /// How many times each grade was given to it; every grade is present.
  final Map<Grade, int> grades;

  /// The most recent grade, and when.
  final Grade lastGrade;
  final DateTime lastPractised;

  int get timesPractised => grades.values.fold(0, (a, b) => a + b);
}

/// One card ready to study: the card, its schedule and the note behind it.
class StudyCard {
  const StudyCard({
    required this.cardId,
    required this.schedule,
    required this.note,
  });

  final int cardId;
  final CardSchedule schedule;
  final Note note;
}
