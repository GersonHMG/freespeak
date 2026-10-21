// The flashcard scheduler: a three-grade variant of SM-2.
//
// A new card's first grade (and a learning card's next one) sets a fixed
// first interval:
//
//   Difficult -> 0 days, shown again at the end of the same session
//   Medium    -> 1 day
//   Easy      -> 3 days
//
// After that, with interval I in days and ease E:
//
//   Difficult: I' = 1                               E' = max(1.3, E - 0.2)
//   Medium:    I' = max(I + 1, round(I * E))        E' = E
//   Easy:      I' = max(I_medium + 1, round(I * E * 1.3))
//                                                   E' = E + 0.15
//
// Intervals are whole days. The max(...) terms keep Medium from repeating
// an interval when I * E rounds down to I, and keep Easy strictly ahead of
// what Medium would have given -- at small intervals with a low ease,
// I * E * 1.3 alone can land below Medium's I + 1.
//
// A due time is the start of the day I' days after the review, local time,
// so a card graded in the evening is due all of that later day rather than
// from the same hour.
//
// There is no automatic fail: the learner's tap is the grade.

import 'dart:math' as math;

import 'deck_models.dart';

const double kMinEase = 1.3;
const double kStartEase = 2.5;

/// The schedule after grading [card] [grade] at [now].
CardSchedule scheduleReview(CardSchedule card, Grade grade, DateTime now) {
  final firstLook =
      card.state == CardState.newCard || card.state == CardState.learning;

  if (firstLook) {
    if (grade == Grade.difficult) {
      return CardSchedule(
        state: CardState.learning,
        dueAt: now,
        intervalDays: 0,
        ease: card.ease,
        reps: card.reps + 1,
        lapses: card.lapses,
      );
    }
    final days = grade == Grade.easy ? 3 : 1;
    return CardSchedule(
      state: CardState.review,
      dueAt: startOfDay(now, plusDays: days),
      intervalDays: days.toDouble(),
      ease: card.ease,
      reps: card.reps + 1,
      lapses: card.lapses,
    );
  }

  final i = card.intervalDays;
  final e = card.ease;
  final medium = math.max(i + 1, (i * e).roundToDouble());

  final (double next, double ease, int lapses) = switch (grade) {
    Grade.difficult => (1, math.max(kMinEase, e - 0.2), card.lapses + 1),
    Grade.medium => (medium, e, card.lapses),
    Grade.easy => (
      math.max(medium + 1, (i * e * 1.3).roundToDouble()),
      e + 0.15,
      card.lapses,
    ),
  };

  return CardSchedule(
    state: CardState.review,
    dueAt: startOfDay(now, plusDays: next.toInt()),
    intervalDays: next,
    ease: ease,
    reps: card.reps + 1,
    lapses: lapses,
  );
}

/// Local midnight at the start of [time]'s day, [plusDays] days on.
/// Built from calendar fields, not by adding 24-hour durations, so a
/// daylight-saving change in between does not shift it off midnight.
DateTime startOfDay(DateTime time, {int plusDays = 0}) =>
    DateTime(time.year, time.month, time.day + plusDays);
