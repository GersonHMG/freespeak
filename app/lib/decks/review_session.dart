// One sitting of Recall reviews for a deck: the queue, where the learner is
// in it, and what grading a card does to it. Kept apart from the screen so
// the queue logic is testable without widgets.
//
// Two kinds of sitting:
//
// * the daily one ([ReviewSession.new]): today's due and new cards, graded
//   onto their schedules, [roundLength] cards at a time -- a round ends
//   after that many grades, and [keepGoing] starts another. When the queue
//   runs out it tops itself up (see [practiceMore]), so a round never ends
//   early on a "nothing due" wall, only once every card in the deck has
//   been through the sitting;
// * a custom one ([ReviewSession.practice]): cards picked up front (see
//   DeckStore.customCards), graded for practice only -- logged, counted
//   toward the daily goal, but no due date moves.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'deck_models.dart';
import 'deck_store.dart';

class ReviewSession extends ChangeNotifier {
  /// Cards shown in one round of the daily sitting, a card shown twice
  /// counted twice.
  static const int roundLength = 5;

  ReviewSession(this._store, {required this.deckId})
    : isPractice = false,
      _preset = null;

  /// A custom session over [cards], in the order given.
  ReviewSession.practice(
    this._store, {
    required this.deckId,
    required List<StudyCard> cards,
  }) : isPractice = true,
       _preset = cards;

  final DeckStore _store;
  final int deckId;

  /// A custom session: grades leave schedules alone, and it does not top
  /// itself up -- the learner picked what this sitting holds.
  final bool isPractice;

  final List<StudyCard>? _preset;

  Deck? _deck;
  List<StudyCard>? _queue;
  int _position = 0;
  int _reviewed = 0;
  final Map<Grade, int> _grades = {for (final grade in Grade.values) grade: 0};
  bool _isSaving = false;

  /// The deck being studied, once [load] has run -- what the screen reads
  /// its language labels from.
  Deck? get deck => _deck;

  /// False until [load] has fetched the queue.
  bool get isLoaded => _queue != null;

  /// The card to answer now, or null before loading, once the round is
  /// over, and once all are done.
  StudyCard? get current => isRoundOver ? null : _upNext;

  /// The next card in the queue, round or no round.
  StudyCard? get _upNext {
    final queue = _queue;
    return queue != null && _position < queue.length ? queue[_position] : null;
  }

  /// The daily sitting has shown this round's [roundLength] cards. A custom
  /// session has no rounds: it holds what the learner picked.
  bool get isRoundOver => !isPractice && _reviewed >= roundLength;

  /// Cards are left after this round -- what [keepGoing] would show.
  bool get hasMore => _upNext != null;

  /// Cards still to go this round, the current one included.
  int get remaining {
    final left = (_queue?.length ?? 0) - _position;
    return isPractice
        ? left
        : math.max(0, math.min(left, roundLength - _reviewed));
  }

  /// Grades given this round, a card shown twice counted twice.
  int get reviewed => _reviewed;

  /// How many of this round's grades were each [Grade].
  Map<Grade, int> get grades => Map.unmodifiable(_grades);

  /// Starts another round of the daily sitting on the cards still left.
  void keepGoing() {
    if (!isRoundOver || !hasMore) return;
    _reviewed = 0;
    _grades.updateAll((_, _) => 0);
    notifyListeners();
  }

  /// True while a grade is being written; further grades are ignored.
  bool get isSaving => _isSaving;

  Future<void> load({DateTime? now}) async {
    _deck = await _store.deck(deckId);
    _queue = [..._preset ?? await _store.studyQueue(deckId, now: now)];
    // Nothing due today is no reason to stop: start on more cards instead.
    if (!isPractice && _queue!.isEmpty) {
      _queue!.addAll(await _extra(now));
    }
    notifyListeners();
  }

  Future<List<StudyCard>> _extra(DateTime? now) => _store.extraCards(
    deckId,
    except: {for (final card in _queue!) card.cardId},
    now: now,
  );

  /// Appends up to [count] more cards once today's are done (see
  /// DeckStore.extraCards) and returns how many came. Zero means the deck
  /// has nothing left to give.
  Future<int> practiceMore({int count = 10, DateTime? now}) async {
    final queue = _queue;
    if (queue == null || isPractice) return 0;
    final extra = await _extra(now);
    queue.addAll(extra.take(count));
    notifyListeners();
    return extra.length;
  }

  /// Grades the current card, saves it, and moves on. In the daily sitting a
  /// card graded Difficult on its first look goes to the end of the queue,
  /// to be shown again; a custom session never requeues. Throws if saving
  /// fails; the card stays current.
  Future<void> grade(
    Grade grade, {
    required AnswerInput input,
    Grade? suggestedGrade,
    String? answerText,
    int? clarity,
    DateTime? now,
  }) async {
    final card = current;
    if (card == null || _isSaving) return;
    _isSaving = true;
    notifyListeners();
    try {
      final next = await _store.recordReview(
        cardId: card.cardId,
        grade: grade,
        input: input,
        suggestedGrade: suggestedGrade,
        answerText: answerText,
        clarity: clarity,
        practice: isPractice,
        now: now,
      );
      if (!isPractice && next.state == CardState.learning) {
        _queue!.add(
          StudyCard(cardId: card.cardId, schedule: next, note: card.note),
        );
      }
      _reviewed++;
      _grades[grade] = _grades[grade]! + 1;
      _position++;
      // The daily sitting keeps going: top up when the queue runs out, so
      // [hasMore] knows whether another round has anything to show.
      if (!isPractice && _upNext == null) {
        await _extra(now).then(_queue!.addAll);
      }
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
